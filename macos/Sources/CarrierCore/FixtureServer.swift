import Foundation

public enum FixtureError: Error, Equatable {
    case unreadable(String)
    case socket(String)
}

/// A fake Carrier for the app's `--fixture` mode: a control server on a temporary socket that answers the snapshot and the
/// requests from the golden files (macos/Tests/Fixtures), and `availableRepos` with a made-up list, so the app is exercised through its real client path with no engine.
/// A second socket, `<home>/chat/chat.sock`, is a fake chat host: `agents` and `list` from `chat-agents.json` and `chat-list.json`,
/// `events` from the `chat-events-*.json` files (each names its session; a listed session with none has no events) with the approvals
/// asked and not answered as pending, `answer`, which records the answer as an event, `archive` and `delete` on the listed sessions
/// (kept in memory, refused for a working or waiting one as the host does), `deletePreview`, which says what `chat-delete-preview.json`
/// holds for the sessions it names and `worktree: null` for the other listed ones, and the worktree requests from `chat-workspace.json`
/// (`workspace`, by folder; one not listed is a plain folder), `chat-fetch.json` (`fetch`, by folder), `chat-clone.json` (`cloneRepo`, by
/// `owner/repo`; one not listed is refused as the host does for a repository it cannot see), `chat-names.json` (`suggestName`,
/// which cycles through its suggestions, and `checkName`, free unless the file says otherwise); `open` makes a session in memory (in a
/// worktree when asked, refused as the host does for a folder that is not a git repository, a branch it did not list and a bad name)
/// and `send` adds the message to its events; anything else is an error.
/// It owns a temporary home (`home`) holding a `config.json` whose `root` is the home itself, so pointing `CARRIER_HOME` at it
/// makes `controlSocketPath()` find the socket. `stop()` removes the home and everything in it.
public final class FixtureServer {
    public let home: String
    public var socketPath: String { home + "/orchestrator/control.sock" }
    public var chatSocketPath: String { home + "/chat/chat.sock" }

    private let listener: Int32
    private let chatListener: Int32
    private let chatAgents: Data
    /// The golden replies of the worktree requests, and which of the suggested names `suggestName` answers next.
    private let chatWorkspaces: [String: [String: Any]]
    private let chatFetches: [String: [String: Any]]
    private let chatClones: [String: [String: Any]]
    private let chatProjects: [String: [String: Any]]
    private let chatNames: [String: Any]
    private var suggested = 0
    /// `archive` and `delete` change it; the sockets' threads share it, so it is read and written with `lock`.
    private var chatSessions: [[String: Any]]
    /// What `deletePreview` says of the sessions in a worktree, by session id: the entries of `chat-delete-preview.json`.
    private var chatWorktrees: [String: Any] = [:]
    /// Each session's golden conversation: its events and the message being written.
    private var chatConversations: [String: (events: [[String: Any]], streaming: String)] = [:]
    /// What the provider offers in each golden conversation that lists options; `setOption` changes the current value here.
    private var chatOptions: [String: [[String: Any]]] = [:]
    /// Under `longTranscript`, every listed session answers this instead.
    private var longChat: [[String: Any]]?
    private let chatHello = Data("{\"event\":\"hello\",\"protocol\":1,\"pid\":0,\"startedAt\":0,\"version\":\"fixture\",\"capabilities\":[\"agents\",\"list\",\"open\",\"send\",\"events\",\"answer\",\"setOption\",\"archive\",\"delete\",\"deletePreview\",\"workspace\",\"fetch\",\"suggestName\",\"checkName\",\"cloneRepo\",\"createProject\"]}\n".utf8)
    private let data: [String: Data]
    private let hello: Data
    private var stopped = false
    private let lock = NSLock()

    /// request name -> golden file
    private static let files = [
        "snapshot": "snapshot.json", "sessions": "reply-sessions.json", "events": "reply-events.json",
        "epic": "reply-epic.json", "files": "reply-files.json",
    ]
    /// What `availableRepos` answers: a few owners, some private, one already in the golden snapshot's repos.
    static let availableRepos = """
    {"repos":[{"name":"AshuLab/web","private":true,"pushedAt":"2026-10-22T10:00:00Z"},\
    {"name":"AshuLab/agent-forge","private":false,"pushedAt":"2026-10-20T08:30:00Z"},\
    {"name":"AshuLab/docs","private":false,"pushedAt":"2026-09-02T12:00:00Z"},\
    {"name":"vemec/encaja","private":true,"pushedAt":"2026-10-22T06:00:00Z"},\
    {"name":"vemec/dotfiles","private":false,"pushedAt":null},\
    {"name":"acme/web","private":true,"pushedAt":"2026-08-01T09:00:00Z"},\
    {"name":"acme/api","private":true,"pushedAt":"2026-10-15T09:00:00Z"}],"hasMore":false}
    """

    /// Accepted and answered with nothing, as the real engine would; the fixture has no one to pause or stop.
    private static let controls: Set<String> = ["pause", "resume", "checkNow", "stop", "resumeEpic"]

    /// `longTranscript`: `events` answers with a made-up transcript of thousands of events instead of the golden file.
    public init(fixtures: String, longTranscript: Bool = false) throws {
        var data: [String: Data] = [:]
        for (name, file) in Self.files {
            do {
                // compact: a reply is one line
                let json = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: fixtures + "/" + file)))
                data[name] = try JSONSerialization.data(withJSONObject: json, options: .sortedKeys)
            } catch { throw FixtureError.unreadable("\(fixtures)/\(file)") }
        }
        // the golden file holds several replies: every file of `reply-files.json` opens to the first
        do {
            let replies = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: fixtures + "/reply-filediff.json"))) as? [Any]
            guard let first = replies?.first else { throw FixtureError.unreadable("\(fixtures)/reply-filediff.json") }
            data["fileDiff"] = try JSONSerialization.data(withJSONObject: first, options: .sortedKeys)
        } catch { throw FixtureError.unreadable("\(fixtures)/reply-filediff.json") }
        if longTranscript {
            let reply = EventsReply(events: longTranscriptEvents(rounds: 400), next: 3600, running: true, structured: true)
            data["events"] = try JSONEncoder().encode(reply)
        }
        data["availableRepos"] = Data(Self.availableRepos.utf8)
        do {
            chatAgents = try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: fixtures + "/chat-agents.json"))), options: .sortedKeys)
            let list = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: fixtures + "/chat-list.json"))) as? [String: Any]
            guard let sessions = list?["sessions"] as? [[String: Any]] else { throw FixtureError.unreadable("\(fixtures)/chat-list.json") }
            chatSessions = sessions
        } catch { throw FixtureError.unreadable("\(fixtures)/chat-agents.json or chat-list.json") }
        func golden<Value>(_ file: String, as _: Value.Type) throws -> Value {
            guard let value = (try? JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: fixtures + "/" + file)))) as? Value else {
                throw FixtureError.unreadable("\(fixtures)/\(file)")
            }
            return value
        }
        chatWorkspaces = try golden("chat-workspace.json", as: [String: [String: Any]].self)
        chatFetches = try golden("chat-fetch.json", as: [String: [String: Any]].self)
        chatClones = try golden("chat-clone.json", as: [String: [String: Any]].self)
        chatProjects = try golden("chat-project.json", as: [String: [String: Any]].self)
        chatNames = try golden("chat-names.json", as: [String: Any].self)
        guard let previews = (try? JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: fixtures + "/chat-delete-preview.json"))) as? [String: Any])?["sessions"] as? [[String: Any]]
        else { throw FixtureError.unreadable("\(fixtures)/chat-delete-preview.json") }
        for entry in previews { if let id = entry["sessionId"] as? String { chatWorktrees[id] = entry["worktree"] } }
        let goldens = ((try? FileManager.default.contentsOfDirectory(atPath: fixtures)) ?? []).filter { $0.hasPrefix("chat-events-") && $0.hasSuffix(".json") }
        for file in goldens.sorted() {
            guard let golden = (try? JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: fixtures + "/" + file)))) as? [String: Any],
                let session = golden["sessionId"] as? String, let events = golden["events"] as? [[String: Any]]
            else { throw FixtureError.unreadable("\(fixtures)/\(file)") }
            chatConversations[session] = (events, golden["streaming"] as? String ?? "")
            chatOptions[session] = golden["options"] as? [[String: Any]] ?? []
        }
        if longTranscript {
            longChat = try JSONSerialization.jsonObject(with: JSONEncoder().encode(longChatEvents(rounds: 500))) as? [[String: Any]]
        }
        self.data = data
        let names = ["sessions", "events", "epic", "files", "fileDiff", "availableRepos", "availableReposPaged", "resumeEpic"].map { "\"\($0)\"" }.joined(separator: ",")
        hello = Data("{\"event\":\"hello\",\"protocol\":1,\"pid\":\(getpid()),\"startedAt\":0,\"version\":\"fixture\",\"capabilities\":[\(names)]}\n".utf8)

        // /tmp, not the default temp folder: a socket path holds 103 bytes and that folder takes about 70
        var template = Array("/tmp/carrier-fixture-XXXXXX".utf8CString)
        guard mkdtemp(&template) != nil else { throw FixtureError.socket("cannot create a temporary folder") }
        let home = String(cString: template)
        self.home = home
        do {
            let orchestrator = home + "/orchestrator"
            try FileManager.default.createDirectory(atPath: orchestrator, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: ["root": home]).write(to: URL(fileURLWithPath: home + "/config.json"))
            try FileManager.default.createDirectory(atPath: home + "/chat", withIntermediateDirectories: true)
            listener = try Self.listen(path: orchestrator + "/control.sock")
            do { chatListener = try Self.listen(path: home + "/chat/chat.sock") } catch {
                Darwin.close(listener)
                throw error
            }
        } catch {
            try? FileManager.default.removeItem(atPath: home)
            throw error
        }
        Thread.detachNewThread { [self] in accept(listener, chat: false) }
        Thread.detachNewThread { [self] in accept(chatListener, chat: true) }
    }

    public func stop() {
        lock.lock(); stopped = true; lock.unlock()
        try? FileManager.default.removeItem(atPath: home)
    }

    private var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }

    private static func listen(path: String) throws -> Int32 {
        var address = sockaddr_un()
        guard path.utf8.count < MemoryLayout.size(ofValue: address.sun_path) else { throw FixtureError.socket("path too long: \(path)") }
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path.utf8) }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw FixtureError.socket("socket() failed") }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, Darwin.listen(fd, 4) == 0 else {
            Darwin.close(fd)
            throw FixtureError.socket("cannot listen on \(path)")
        }
        return fd
    }

    private func accept(_ listener: Int32, chat: Bool) {
        while isStopped == false {
            var ready = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
            guard poll(&ready, 1, 50) > 0 else { continue }
            let fd = Darwin.accept(listener, nil, nil)
            guard fd >= 0 else { continue }
            Thread.detachNewThread { [self] in
                var on: Int32 = 1
                setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
                serve(fd, chat: chat)
                Darwin.close(fd)
            }
        }
        Darwin.close(listener)
    }

    /// The hello, then one reply per line until the client leaves or the server stops.
    private func serve(_ fd: Int32, chat: Bool) {
        guard send(chat ? chatHello : hello, to: fd) else { return }
        var pending = Data()
        while isStopped == false {
            var ready = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&ready, 1, 50) >= 0 else { return }
            guard ready.revents != 0 else { continue }
            var chunk = [UInt8](repeating: 0, count: 4096)
            let n = read(fd, &chunk, chunk.count)
            guard n > 0 else { return }
            pending.append(contentsOf: chunk[..<n])
            while let end = pending.firstIndex(of: 0x0A) {
                let line = pending[pending.startIndex..<end]
                pending.removeSubrange(pending.startIndex...end)
                guard send(chat ? chatReply(to: Data(line)) : reply(to: Data(line)), to: fd) else { return }
            }
        }
    }

    private func reply(to line: Data) -> Data {
        let request = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
        guard let id = request?["id"] as? Int else { return Self.line("{\"id\":null,\"ok\":false,\"error\":\"invalid request\"}") }
        guard let cmd = request?["cmd"] as? String else { return Self.line("{\"id\":\(id),\"ok\":false,\"error\":\"invalid request\"}") }
        if let body = data[cmd] { return Self.line("{\"id\":\(id),\"ok\":true,\"data\":" + String(decoding: body, as: UTF8.self) + "}") }
        if Self.controls.contains(cmd) { return Self.line("{\"id\":\(id),\"ok\":true}") }
        return Self.line("{\"id\":\(id),\"ok\":false,\"error\":\"unknown request\"}")
    }

    private func chatReply(to line: Data) -> Data {
        let request = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
        guard let id = request?["id"] as? Int else { return Self.line("{\"id\":null,\"ok\":false,\"error\":\"invalid request\"}") }
        switch request?["cmd"] as? String {
        case "agents":
            return Self.line("{\"id\":\(id),\"ok\":true,\"data\":" + String(decoding: chatAgents, as: UTF8.self) + "}")
        case "list":
            let archived = request?["archived"] as? Bool ?? false
            let sessions = locked { chatSessions.filter { ($0["archived"] as? Bool) == archived } }
            guard let body = try? JSONSerialization.data(withJSONObject: ["sessions": sessions], options: .sortedKeys) else { break }
            return Self.line("{\"id\":\(id),\"ok\":true,\"data\":" + String(decoding: body, as: UTF8.self) + "}")
        case "events":
            guard let session = request?["sessionId"] as? String, locked({ chatSessions.contains(where: { $0["id"] as? String == session }) }) else {
                return Self.line("{\"id\":\(id),\"ok\":false,\"error\":\"unknown session\"}")
            }
            let after = request?["after"] as? Int ?? 0
            let limit = min(max(request?["limit"] as? Int ?? 200, 1), 200)
            lock.lock()
            let conversation = longChat.map { ($0, "") } ?? chatConversations[session] ?? ([], "")
            lock.unlock()
            let page = Array(conversation.0.filter { ($0["id"] as? Int ?? 0) > after }.prefix(limit))
            let reply: [String: Any] = [
                "events": page, "cursor": page.last?["id"] as? Int ?? after, "streaming": conversation.1,
                "approvals": Self.pending(conversation.0), "options": chatOptions[session] ?? [],
                "session": ["state": locked { chatSessions.first { $0["id"] as? String == session }?["state"] as? String } ?? "idle"],
            ]
            guard let body = try? JSONSerialization.data(withJSONObject: reply, options: .sortedKeys) else { break }
            return Self.line("{\"id\":\(id),\"ok\":true,\"data\":" + String(decoding: body, as: UTF8.self) + "}")
        case "workspace", "fetch":
            guard let folder = request?["folder"] as? String else { break }
            if request?["cmd"] as? String == "workspace" {
                return Self.answer(id, chatWorkspaces[folder] ?? ["folder": folder, "git": false, "bare": false, "linkedWorktree": false, "repo": NSNull(), "branch": NSNull(), "defaultBranch": NSNull(), "dirty": 0, "branches": [], "fetchedAt": NSNull()])
            }
            if let fetched = chatFetches[folder] { return Self.answer(id, fetched) }
            let git = chatWorkspaces[folder]?["git"] as? Bool ?? false
            return Self.refused(id, git ? "The fetch of origin failed" : "That folder is not a git repository")
        case "cloneRepo":
            guard let repo = request?["repo"] as? String else { break }
            return chatClones[repo].map { Self.answer(id, $0) } ?? Self.refused(id, "\(repo) was not found, or your GitHub login cannot see it")
        case "createProject":
            guard let name = request?["name"] as? String else { break }
            return chatProjects[name].map { Self.answer(id, $0) } ?? Self.refused(id, "\(name) is already a project; choose another name")
        case "suggestName":
            let names = chatNames["suggestions"] as? [String] ?? []
            guard request?["folder"] is String, names.isEmpty == false else { break }
            return Self.answer(id, ["name": locked { defer { suggested += 1 }; return names[suggested % names.count] }])
        case "checkName":
            guard request?["folder"] is String, let name = request?["name"] as? String else { break }
            return Self.answer(id, nameCheck(name))
        case "open":
            return open(id, request ?? [:])
        case "send":
            guard let session = request?["sessionId"] as? String, let text = request?["text"] as? String else { break }
            let found = locked { () -> Bool in
                guard chatSessions.contains(where: { $0["id"] as? String == session }) else { return false }
                let events = chatConversations[session]?.events ?? []
                chatConversations[session, default: ([], "")].events = events + [["id": (events.last?["id"] as? Int ?? 0) + 1, "at": Int(Date().timeIntervalSince1970 * 1000), "kind": "user", "text": text]]
                return true
            }
            return found ? Self.answer(id, [String: Any]()) : Self.refused(id, "unknown session")
        case "answer":
            guard let session = request?["sessionId"] as? String, let approval = request?["approvalId"] as? String, let choice = request?["choiceId"] as? String else { break }
            lock.lock()
            defer { lock.unlock() }
            var events = chatConversations[session]?.events ?? []
            guard let asked = Self.pending(events).first(where: { $0["approvalId"] as? String == approval }) else {
                return Self.line("{\"id\":\(id),\"ok\":false,\"error\":\"That approval is not pending: it is unknown or was already answered\"}")
            }
            guard (asked["choices"] as? [[String: Any]] ?? []).contains(where: { $0["id"] as? String == choice }) else {
                return Self.line("{\"id\":\(id),\"ok\":false,\"error\":\"That is not one of the choices\"}")
            }
            events.append(["id": (events.last?["id"] as? Int ?? 0) + 1, "at": Int(Date().timeIntervalSince1970 * 1000), "kind": "approval_answered", "approvalId": approval, "choiceId": choice])
            chatConversations[session]?.events = events
            return Self.line("{\"id\":\(id),\"ok\":true,\"data\":{}}")
        case "setOption":
            guard let session = request?["sessionId"] as? String, let option = request?["option"] as? String, let value = request?["value"] as? String,
                let at = chatOptions[session]?.firstIndex(where: { $0["id"] as? String == option })
            else { return Self.line("{\"id\":\(id),\"ok\":false,\"error\":\"This agent has no such option\"}") }
            let listed = (chatOptions[session]?[at]["values"] as? [[String: Any]])?.contains { $0["id"] as? String == value } ?? false
            guard listed else { return Self.line("{\"id\":\(id),\"ok\":false,\"error\":\"The agent does not offer that value for \(option)\"}") }
            chatOptions[session]?[at]["current"] = value
            return Self.line("{\"id\":\(id),\"ok\":true,\"data\":{}}")
        case "archive", "delete":
            let verb = request?["cmd"] as? String ?? ""
            guard let session = request?["sessionId"] as? String, let archived = verb == "delete" ? false : request?["archived"] as? Bool else { break }
            let refusal: String? = locked {
                guard let at = chatSessions.firstIndex(where: { $0["id"] as? String == session }) else { return "unknown session" }
                // as the host does: a session that is working or waiting for an approval is not archived or deleted
                let state = chatSessions[at]["state"] as? String
                if verb == "delete" || archived, state != "idle" {
                    return "This session is \(state == "working" ? "working" : "waiting for an approval"); interrupt or close it first, then \(verb) it"
                }
                if verb == "delete" { chatSessions.remove(at: at) } else { chatSessions[at]["archived"] = archived }
                return nil
            }
            if let refusal { return Self.line("{\"id\":\(id),\"ok\":false,\"error\":\"\(refusal)\"}") }
            return Self.line("{\"id\":\(id),\"ok\":true,\"data\":{}}")
        case "deletePreview":
            guard let asked = request?["sessionIds"] as? [String] else { break }
            let listed = locked { Set(chatSessions.compactMap { $0["id"] as? String }) }
            // as the host does: one unknown id refuses the whole request
            guard asked.allSatisfy(listed.contains) else { return Self.line("{\"id\":\(id),\"ok\":false,\"error\":\"There is no such session\"}") }
            let sessions = asked.map { ["sessionId": $0, "worktree": chatWorktrees[$0] ?? NSNull()] as [String: Any] }
            guard let body = try? JSONSerialization.data(withJSONObject: ["sessions": sessions], options: .sortedKeys) else { break }
            return Self.line("{\"id\":\(id),\"ok\":true,\"data\":" + String(decoding: body, as: UTF8.self) + "}")
        default: break
        }
        return Self.line("{\"id\":\(id),\"ok\":false,\"error\":\"unknown request\"}")
    }

    /// The golden check of a worktree name: free unless `chat-names.json` says why not.
    private func nameCheck(_ name: String) -> [String: Any] {
        (chatNames["checks"] as? [String: [String: Any]])?[name] ?? chatNames["free"] as? [String: Any] ?? ["valid": true, "free": true]
    }

    /// `open`: a session in memory, in a worktree of the folder when asked; refused as the host does.
    private func open(_ id: Int, _ request: [String: Any]) -> Data {
        guard let agent = request["agent"] as? String, let folder = request["folder"] as? String else { return Self.refused(id, "invalid request") }
        guard let chosen = ((try? JSONSerialization.jsonObject(with: chatAgents)) as? [[String: Any]])?.first(where: { $0["name"] as? String == agent }) else {
            return Self.refused(id, "There is no chat agent named \"\(agent)\"")
        }
        var session: [String: Any] = [
            "id": UUID().uuidString.lowercased(), "agent": agent, "harness": chosen["harness"] as? String ?? agent, "folder": folder, "workspace": ["kind": "folder"],
            "state": "idle", "createdAt": Int(Date().timeIntervalSince1970 * 1000), "lastActiveAt": Int(Date().timeIntervalSince1970 * 1000), "archived": false, "live": true,
        ]
        if let worktree = request["worktree"] as? [String: Any] {
            guard let info = chatWorkspaces[folder], info["git"] as? Bool == true, info["bare"] as? Bool != true else { return Self.refused(id, "Worktrees need a git repository") }
            let from = worktree["from"] as? String ?? ""
            guard (info["branches"] as? [[String: Any]])?.contains(where: { $0["name"] as? String == from }) == true else {
                return Self.refused(id, "The branch to start from is not one this repository lists")
            }
            let names = chatNames["suggestions"] as? [String] ?? []
            let name = worktree["name"] as? String ?? names.first ?? "worktree"
            let check = nameCheck(name)
            guard check["valid"] as? Bool == true, check["free"] as? Bool == true else { return Self.refused(id, check["reason"] as? String ?? "That name cannot be used") }
            let path = "/Users/dev/.carrier/chat/worktrees/local/\(URL(fileURLWithPath: folder).lastPathComponent)/\(name)"
            session["folder"] = path
            session["workspace"] = ["kind": "worktree", "branch": "carrier/\(name)", "from": from, "base": folder, "path": path]
        }
        locked { chatSessions.insert(session, at: 0) }
        return Self.answer(id, ["session": session, "options": [Any]()])
    }

    private static func answer(_ id: Int, _ data: Any) -> Data {
        let body = (try? JSONSerialization.data(withJSONObject: data, options: .sortedKeys)).map { String(decoding: $0, as: UTF8.self) } ?? "null"
        return line("{\"id\":\(id),\"ok\":true,\"data\":" + body + "}")
    }

    private static func refused(_ id: Int, _ reason: String) -> Data {
        let text = (try? JSONSerialization.data(withJSONObject: reason, options: .fragmentsAllowed)).map { String(decoding: $0, as: UTF8.self) } ?? "\"\""
        return line("{\"id\":\(id),\"ok\":false,\"error\":" + text + "}")
    }

    private func locked<Value>(_ body: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    /// The approvals asked and not answered yet, as the host lists them in `events`.
    private static func pending(_ events: [[String: Any]]) -> [[String: Any]] {
        let answered = Set(events.filter { $0["kind"] as? String == "approval_answered" }.compactMap { $0["approvalId"] as? String })
        return events.filter { $0["kind"] as? String == "approval" && answered.contains($0["approvalId"] as? String ?? "") == false }
    }

    private static func line(_ text: String) -> Data { Data((text + "\n").utf8) }

    private func send(_ data: Data, to fd: Int32) -> Bool {
        var sent = 0
        while sent < data.count {
            let n = data.withUnsafeBytes { write(fd, $0.baseAddress! + sent, data.count - sent) }
            if n > 0 { sent += n } else if n < 0 && errno == EINTR { continue } else { return false }
        }
        return true
    }
}
