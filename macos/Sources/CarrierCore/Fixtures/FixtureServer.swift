import CoreGraphics
import Foundation

public enum FixtureError: Error, Equatable {
    case unreadable(String)
    case socket(String)
}

/// A fake Carrier for the app's `--fixture` mode: a control server on a temporary socket that answers the snapshot and the
/// requests from the golden files (macos/Tests/Fixtures), and `availableRepos` with a made-up list, so the app is exercised through its real client path with no engine.
/// A second socket, `<home>/chat/state/chat.sock`, is a fake chat host: `agents` and `list` from `chat-agents.json` and `chat-list.json`,
/// `events` from the `chat-events-*.json` files (each names its session; a listed session with none has no events) with the approvals
/// asked and not answered as pending, `answer`, which records the answer as an event, `archive` and `delete` on the listed sessions
/// (kept in memory, refused for a working or waiting one as the host does), `deletePreview`, which says what `chat-delete-preview.json`
/// holds for the sessions it names and `worktree: null` for the other listed ones, and the worktree requests from `chat-workspace.json`
/// (`workspace`, by folder; one not listed is a plain folder), `chat-fetch.json` (`fetch`, by folder; `ifStale` is accepted and the answer is the same: a window that has passed; a git folder not listed there is refused as a remote that cannot be reached), `chat-github-repos.json` (`githubRepos`, by page, the login on page 1 only; a page not listed is refused), `chat-branches.json` (`repoBranches`, by `owner/repo`; one not listed is refused like a repository the login cannot see, and `cloneProject` refuses it the same way while one it or `chat-github-repos.json` lists starts cloning and stays at git's progress line), `chat-project-worktrees.json` (`projectWorktrees`, by the folder's name; a project not listed has its main clone and no worktrees; `removeProjectWorktree` refuses one whose state is `sessionOpen` or `uncommitted` as the host does and otherwise drops it from that list, and `cleanProjectWorktrees` answers `chat-project-cleanup.json`'s removed and skipped by the same name, `run` dropping the removed ones), `chat-project-disk.json` (`projectDisk`, by the folder's name, its `main` part standing for the folder itself; a project not listed has never been measured and nothing is ever measuring), `chat-project-clones.json` (`projectClones`: the clones running or failed at the start, which `cloneProject` and `dismissClone` change in memory; the file is optional), `newProject` (makes `<parent or the projects folder>/local/<name>` and registers it in the home's `projects.json` with origin `created`, refusing a name the host would refuse and a folder that is already there; no git runs), `chat-providers.json` (`providers`), `chat-usage.json` (`usage`, the same sample for any filter; `usageOverride` is accepted and changes nothing), `chat-names.json` (`suggestName`,
/// which cycles through its suggestions, and `checkName`, free unless the file says otherwise); `open` makes a session in memory (in a
/// worktree when asked, refused as the host does for a folder that is not a git repository, a branch it did not list and a bad name)
/// and `send` adds the message to its events; `switchAgent` gives an idle session another listed agent and a notice that says so; anything else is an error.
/// It owns a temporary home (`home`) holding an `engine.json` (`fixtureConfig`: the watched repos, profiles and roles, which also give the Providers page accounts in use), a `chat.json` with two chat agents, a `projects.json` with four projects (`writeProjects`) and a `providers.json` with the golden reply's accounts (`providers` follows it: Antigravity stays "found, not added" until an Add writes it), and the engine's socket in `engine/state/`, so pointing `CARRIER_HOME` at it
/// makes `controlSocketPath()` find the socket. `stop()` removes the home and everything in it.
/// The `engine.json` of the fixture home: the repos of the fixture snapshot, the profiles and the three global roles, and one repo that
/// overrides the reviewer's model, so the Watching page shows an inherited role and a mixed one.
public let fixtureConfig = """
{
  "repos": [
    {"name": "acme/web"},
    {"name": "acme/api", "agents": {"reviewer": {"model": "gpt-5-mini"}}},
    {"name": "acme/a-really-long-repository-name-for-the-sidebar"}
  ],
  "profiles": {
    "acme-author": {"kind": "forge", "agent": "acme-author"},
    "acme-reviewer": {"kind": "forge", "agent": "acme-reviewer"},
    "acme-lead": {"kind": "forge", "agent": "acme-lead"}
  },
  "agents": {
    "author": {"profile": "acme-author", "provider": "claude", "model": "claude-sonnet-5-5", "effort": "high"},
    "reviewer": {"profile": "acme-reviewer", "provider": "codex", "model": "gpt-5", "effort": "high"},
    "leadReviewer": {"profile": "acme-lead", "provider": "claude", "model": "claude-opus-5"}
  },
  "failover": {
    "roles": {
      "author": [{"provider": "codex", "model": "gpt-5"}, {"provider": "claude-work"}],
      "reviewer": [{"provider": "claude", "model": "claude-opus-5"}]
    }
  }
}
"""

/// The Agent Forge registry of the fixture home (`AGENT_FORGE_CONFIG` points at it under `--fixture`): the three bots of the roles and a spare one.
/// A key would never be in a file the app reads, so none is here either.
public let fixtureForgeRegistry = """
{"agents": [{"name": "acme-author", "appId": "1000001"}, {"name": "acme-reviewer", "appId": "1000002"}, {"name": "acme-lead"}, {"name": "acme-spare", "label": "A bot no role uses"}]}
"""

/// The golden doctor output the fixture home holds, for the app to answer its doctor run with in `--fixture` mode.
public func doctorFixtureOutput(home: String) -> String? { try? String(contentsOfFile: home + "/doctor.json", encoding: .utf8) }

public final class FixtureServer {
    public let home: String
    /// A listed session with `fixtureRefuseSend` (a sentence) refuses its sends with it, so the refusal's banner can be looked at.
    /// The sessions the list marks `fixtureUnread` and `fixturePinned`: the app, which keeps what the person has seen and pinned, starts with them so.
    public let unreadSessionIds: [String]
    public let pinnedSessionIds: [String]
    public var socketPath: String { CarrierPlaces(folder: home).controlSocket }
    public var chatSocketPath: String { CarrierPlaces(folder: home).chatSocket }

    private let listener: Int32
    private let chatListener: Int32
    private let chatAgents: Data
    /// The golden replies of the worktree requests, and which of the suggested names `suggestName` answers next.
    private let chatWorkspaces: [String: [String: Any]]
    private let chatFetches: [String: [String: Any]]
    private let chatGithubRepos: [String: [String: Any]]
    private let chatBranches: [String: [String: Any]]
    /// `chat-project-worktrees.json`: the `projectWorktrees` reply by the project folder's name; any other project has its main clone and no worktrees.
    private let chatProjectWorktrees: [String: [String: Any]]
    /// `chat-project-disk.json`: the `projectDisk` figure by the project folder's name.
    private let chatProjectDisk: [String: [String: Any]]
    /// `chat-project-cleanup.json`: what `cleanProjectWorktrees` removes and skips, by the project folder's name; any other project has nothing to clean up.
    private let chatProjectCleanup: [String: [String: Any]]
    /// The worktrees `removeProjectWorktree` and Clean up took, which `projectWorktrees` no longer lists (read with `lock`).
    private var removedWorktrees: Set<String> = []
    /// The clones from Settings the host runs or has failed: `chat-project-clones.json` at the start, then what `cloneProject` and `dismissClone` change (read with `lock`).
    private var chatClones: [[String: Any]]
    private let chatProviders: [String: Any]
    private let chatNames: [String: Any]
    /// The golden `usage` reply, for any filter.
    private let chatUsage: [String: Any]
    private var suggested = 0
    /// `archive` and `delete` change it; the sockets' threads share it, so it is read and written with `lock`.
    private var chatSessions: [[String: Any]]
    /// What `deletePreview` says of the sessions in a worktree, by session id: the entries of `chat-delete-preview.json`.
    private var chatWorktrees: [String: Any] = [:]
    /// Each session's golden conversation: its events and the message being written.
    private var chatConversations: [String: (events: [[String: Any]], streaming: String)] = [:]
    /// What the provider offers in each golden conversation that lists options; `setOption` changes the current value here.
    private var chatOptions: [String: [[String: Any]]] = [:]
    /// How many times the chat socket was asked each request, for the tests that count what the app asks (read with `lock`).
    private var chatAsked: [String: Int] = [:]
    /// How many connections the chat socket accepted (each one gets a hello), for the tests that count what the app opens.
    private var chatConnected = 0
    /// The same two counts for the engine's socket.
    private var engineAsked: [String: Int] = [:]
    private var engineConnected = 0
    /// Under `longTranscript`, every listed session answers this instead.
    private var longChat: [[String: Any]]?
    /// Sessions already titled by `regenerateTitle` or `regenerateTitles`, so a second bulk ask sees 0 left.
    private var regeneratedSessionIds: Set<String> = []
    let chatHello = Data("{\"event\":\"hello\",\"protocol\":1,\"pid\":0,\"startedAt\":0,\"version\":\"fixture\",\"capabilities\":[\"agents\",\"list\",\"open\",\"resume\",\"send\",\"events\",\"answer\",\"setOption\",\"archive\",\"delete\",\"deletePreview\",\"workspace\",\"fetch\",\"suggestName\",\"checkName\",\"cloneRepo\",\"createProject\",\"githubRepos\",\"repoBranches\",\"providers\",\"plan\",\"usage\",\"usageOverride\",\"accountIdentity\",\"accountPalette\",\"switchAgent\",\"interrupt\",\"stopTask\",\"worktreeStart\",\"fetchIfStale\",\"projects\",\"textGenerators\",\"regenerateTitle\",\"regenerateTitles\",\"config\"]}\n".utf8)
    private let data: [String: Data]
    let hello: Data
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

    /// The requests that change the roles, personas, failover, lead reviewer or orchestrator profile in `engine.json`: `engineRolesReply` writes them.
    static let roleRequests: Set<String> = ["editRole", "editRepoRole", "editPersona", "editFailover", "setLeadReviewer", "setOrchestratorProfile"]
    /// Accepted and answered with nothing, as the real engine would; the fixture has no one to pause or stop.
    private static let controls: Set<String> = ["pause", "resume", "checkNow", "stop", "resumeEpic", "recoverEpic", "reload"]

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
            let nowMs = Int(Date().timeIntervalSince1970 * 1000)
            chatSessions = sessions.map { Self.relativeTimes($0, nowMs: nowMs) }
            unreadSessionIds = sessions.filter { $0["fixtureUnread"] as? Bool == true }.compactMap { $0["id"] as? String }
            pinnedSessionIds = sessions.filter { $0["fixturePinned"] as? Bool == true }.compactMap { $0["id"] as? String }
        } catch { throw FixtureError.unreadable("\(fixtures)/chat-agents.json or chat-list.json") }
        func golden<Value>(_ file: String, as _: Value.Type) throws -> Value {
            guard let value = (try? JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: fixtures + "/" + file)))) as? Value else {
                throw FixtureError.unreadable("\(fixtures)/\(file)")
            }
            return value
        }
        chatWorkspaces = try golden("chat-workspace.json", as: [String: [String: Any]].self)
        chatFetches = try golden("chat-fetch.json", as: [String: [String: Any]].self)
        chatGithubRepos = try golden("chat-github-repos.json", as: [String: [String: Any]].self)
        chatBranches = try golden("chat-branches.json", as: [String: [String: Any]].self)
        chatProjectWorktrees = try golden("chat-project-worktrees.json", as: [String: [String: Any]].self)
        chatProjectDisk = try golden("chat-project-disk.json", as: [String: [String: Any]].self)
        chatProjectCleanup = try golden("chat-project-cleanup.json", as: [String: [String: Any]].self)
        chatClones = (try? golden("chat-project-clones.json", as: [String: Any].self))?["clones"] as? [[String: Any]] ?? []
        chatProviders = try golden("chat-providers.json", as: [String: Any].self)
        chatNames = try golden("chat-names.json", as: [String: Any].self)
        chatUsage = try golden("chat-usage.json", as: [String: Any].self)
        guard let previews = (try? JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: fixtures + "/chat-delete-preview.json"))) as? [String: Any])?["sessions"] as? [[String: Any]]
        else { throw FixtureError.unreadable("\(fixtures)/chat-delete-preview.json") }
        for entry in previews { if let id = entry["sessionId"] as? String { chatWorktrees[id] = entry["worktree"] } }
        let goldens = ((try? FileManager.default.contentsOfDirectory(atPath: fixtures)) ?? []).filter { $0.hasPrefix("chat-events-") && $0.hasSuffix(".json") }
        for file in goldens.sorted() {
            guard let golden = (try? JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: fixtures + "/" + file)))) as? [String: Any],
                let session = golden["sessionId"] as? String, let events = golden["events"] as? [[String: Any]]
            else { throw FixtureError.unreadable("\(fixtures)/\(file)") }
            // an event with `ago` (milliseconds) happened that long before the launch, so a call still going has run for that long
            let nowMs = Int(Date().timeIntervalSince1970 * 1000)
            chatConversations[session] = (events.map { event in
                var event = event
                if let ago = event.removeValue(forKey: "ago") as? Int { event["at"] = nowMs - ago }
                return event
            }, golden["streaming"] as? String ?? "")
            chatOptions[session] = golden["options"] as? [[String: Any]] ?? []
        }
        if longTranscript {
            longChat = try JSONSerialization.jsonObject(with: JSONEncoder().encode(longChatEvents(rounds: 500))) as? [[String: Any]]
        }
        self.data = data
        let names = ["sessions", "events", "epic", "files", "fileDiff", "availableRepos", "availableReposPaged", "resumeEpic", "resumeFromStage", "resumeReviewerOptions", "recoverEpic", "reload", "config"].map { "\"\($0)\"" }.joined(separator: ",")
        hello = Data("{\"event\":\"hello\",\"protocol\":1,\"pid\":\(getpid()),\"startedAt\":0,\"version\":\"fixture\",\"capabilities\":[\(names)]}\n".utf8)

        // /tmp, not the default temp folder: a socket path holds 103 bytes and that folder takes about 70
        var template = Array("/tmp/carrier-fixture-XXXXXX".utf8CString)
        guard mkdtemp(&template) != nil else { throw FixtureError.socket("cannot create a temporary folder") }
        let home = String(cString: template)
        self.home = home
        do {
            let places = CarrierPlaces(folder: home)
            try FileManager.default.createDirectory(atPath: places.engineState, withIntermediateDirectories: true)
            try Data(fixtureConfig.utf8).write(to: URL(fileURLWithPath: places.engineConfig))
            try Data(fixtureForgeRegistry.utf8).write(to: URL(fileURLWithPath: home + "/agent-forge.json"))
            // what the app's doctor run answers in `--fixture` mode (`doctorFixtureOutput`)
            try Data(contentsOf: URL(fileURLWithPath: fixtures + "/doctor.json")).write(to: URL(fileURLWithPath: home + "/doctor.json"))
            try FileManager.default.createDirectory(atPath: places.chatState, withIntermediateDirectories: true)
            let chatConfig = #"{"agents":{"claude":{"account":"claude"},"codex":{"account":"codex"},"work":{"account":"claude-work"}}}"#
            try Data(chatConfig.utf8).write(to: URL(fileURLWithPath: places.chatConfig))
            // the accounts of the golden reply, without Antigravity: it is found and has no account, so the page shows its Add row
            let accounts = #"{"providers":{"claude":{"harness":"claude"},"claude-work":{"harness":"claude","displayName":"Work","configDir":"/Users/demo/.claude-work"},"codex":{"harness":"codex","command":"/opt/homebrew/bin/codex"}}}"#
            try ProvidersFile(folder: home).write(Data(accounts.utf8))
            try Self.writeProjects(home: home)
            listener = try Self.listen(path: places.controlSocket)
            do { chatListener = try Self.listen(path: places.chatSocket) } catch {
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

    /// The Projects page's list: a project with a GitHub origin (`acme/web`, the fixture's epic repository, which gives that epic's rows the project's image), one whose name and remote are very long, a folder that is not a repository, one
    /// that is not there (with a missing image copy that falls back to colour and mark), and one with a copied icon image; then the folders of the fixture's sessions, one with a name, colour and mark, one with the image and one with nothing set.
    private static func writeProjects(home: String) throws {
        let long = "a-project-with-a-name-so-long-that-the-row-has-to-cut-it-before-it-reaches-the-chevron"
        var entries: [[String: Any]] = []
        for (folder, remote) in [
            ("carrier", "git@github.com:AshuLab/carrier.git"),
            (long, "https://github.com/some-organisation-with-a-long-name/" + long + ".git"),
            ("notes", ""),
            ("studio", "git@github.com:acme/web.git"),
        ] {
            let path = home + "/projects/" + folder
            try FileManager.default.createDirectory(atPath: path + "/.git", withIntermediateDirectories: true)
            if remote.isEmpty == false {
                try Data("[core]\n\tbare = false\n[remote \"origin\"]\n\turl = \(remote)\n\tfetch = +refs/heads/*:refs/remotes/origin/*\n".utf8).write(to: URL(fileURLWithPath: path + "/.git/config"))
            } else {
                try FileManager.default.removeItem(atPath: path + "/.git")
            }
            entries.append(["path": path, "origin": "added"] as [String: Any])
        }
        entries[0]["pinned"] = true
        entries[0]["tags"] = ["swift", "macos"]
        entries[0]["icon"] = ["color": "teal", "mark": "bolt"]
        entries[0]["actions"] = [
            ["name": "Install", "command": "pnpm install", "when": "newWorktree"],
            ["name": "Bootstrap", "command": "pnpm bootstrap", "when": "afterClone", "on": false, "onFail": "stop"],
        ]
        entries[1]["name"] = "A project with a name so long that the row has to cut it before it reaches the chevron"
        entries[1]["tags"] = ["api", "automation", "backend", "cli", "docker", "graphql", "postgres", "typescript"]
        entries[2]["icon"] = ["color": "orange"]
        entries[2]["tags"] = ["design", "docs", "planning", "research"]
        if let iconImage = Self.fixtureProjectIconImage(), let saved = try? ProjectIconStore(folder: home).save(cgImage: iconImage) {
            entries[3]["icon"] = ["image": saved]
        }
        let studio = entries.remove(at: 3)
        entries.append(["path": "/Users/demo/gone", "name": "Moved away", "origin": "cloned", "icon": ["color": "purple", "mark": "star", "image": "missing.png"]])
        entries.append(studio)
        // the folders of the fixture's sessions: one with a name, a colour and a mark, one with an image and one with nothing set
        entries.append(["path": "/Users/dev/carrier", "name": "Carrier app", "origin": "added", "icon": ["color": "red", "mark": "star"]])
        entries.append(["path": "/Users/dev/agent-forge", "origin": "added"])
        if let image = studio["icon"] { entries[entries.count - 1]["icon"] = image }
        entries.append(["path": "/Users/dev/web", "origin": "added"])
        let file = try JSONSerialization.data(withJSONObject: ["projects": entries], options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try file.write(to: URL(fileURLWithPath: CarrierPlaces(folder: home).projects))
    }

    private static func fixtureProjectIconImage() -> CGImage? {
        let size = 128
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(red: 0.16, green: 0.44, blue: 0.68, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        context.setFillColor(red: 0.96, green: 0.72, blue: 0.24, alpha: 1)
        context.fillEllipse(in: CGRect(x: 28, y: 28, width: 72, height: 72))
        return context.makeImage()
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
        locked { if chat { chatConnected += 1 } else { engineConnected += 1 } }
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
                // this thread lives as long as the connection, so each request frees what it autoreleases (the JSON of the request)
                let sent = autoreleasepool { send(chat ? chatReply(to: Data(line)) : reply(to: Data(line)), to: fd) }
                guard sent else { return }
            }
        }
    }

    /// What the engine's socket was asked so far, by request name, and how many connections it accepted.
    var engineRequests: [String: Int] { locked { engineAsked } }
    var engineConnections: Int { locked { engineConnected } }

    private func reply(to line: Data) -> Data {
        let request = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
        if let cmd = request?["cmd"] as? String { locked { engineAsked[cmd, default: 0] += 1 } }
        guard let id = request?["id"] as? Int else { return Self.refused(nil, "request.invalid", "invalid request") }
        guard let cmd = request?["cmd"] as? String else { return Self.refused(id, "request.invalid", "invalid request") }
        if let body = data[cmd] { return Self.line("{\"id\":\(id),\"ok\":true,\"data\":" + String(decoding: body, as: UTF8.self) + "}") }
        if Self.controls.contains(cmd) { return Self.line("{\"id\":\(id),\"ok\":true}") }
        if cmd == "setWatchedRepos" || cmd == "editBehavior", let answer = engineConfigReply(id, request ?? [:]) { return answer }
        if Self.roleRequests.contains(cmd), let answer = engineRolesReply(id, request ?? [:]) { return answer }
        return Self.refused(id, "request.invalid", "unknown request")
    }

    /// What the chat socket was asked so far, by request name.
    var chatRequests: [String: Int] { locked { chatAsked } }

    /// How many connections the chat socket has accepted so far.
    var chatConnections: Int { locked { chatConnected } }

    /// `cloneProject`: a repository the golden branches or the listing know starts cloning and stays at git's progress line, as a long clone would; one it does not know is refused
    /// like a repository the login cannot see; one already cloning is shared; one that is a project of the fixture home is refused as the host does.
    private func cloneProject(_ id: Int, _ repo: String, parent: String?) -> Data {
        let key = repo.lowercased()
        let folder = (parent ?? currentProjectsFolderOfFixture) + "/" + repo
        if let running = locked({ chatClones.first { ($0["repo"] as? String)?.lowercased() == key && $0["state"] as? String == "cloning" } }) { return Self.answer(id, running) }
        let listed = chatGithubRepos.values.flatMap { ($0["repos"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String } }
        guard (Array(chatBranches.keys) + listed).contains(where: { $0.lowercased() == key }) else { return Self.refused(id, "github.repoNotFound", "\(repo) was not found, or your GitHub login cannot see it", ["repo": .string(repo)]) }
        let clone: [String: Any] = ["repo": repo, "folder": folder, "state": "cloning", "progress": "Receiving objects: 45%"]
        locked {
            chatClones.removeAll { ($0["repo"] as? String)?.lowercased() == key }
            chatClones.append(clone)
        }
        return Self.answer(id, clone)
    }

    /// `newProject`: the folder and the entry, as the host makes them, without git; refused as the host refuses.
    private func newProject(_ id: Int, _ name: String, parent: String?) -> Data {
        if let refusal = projectNameProblem(name) { return Self.refused(id, "project.nameInvalid", refusal.text, ["name": .string(name)]) }
        let folder = (parent ?? currentProjectsFolderOfFixture) + "/local/" + name
        guard FileManager.default.fileExists(atPath: folder) == false else { return Self.refused(id, "project.nameTaken", "\(name) is already a project; choose another name", ["name": .string(name)]) }
        do {
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            let file = ProjectsFile(folder: home)
            try file.add(folder: folder)
            try file.update(path: folder, key: "origin", value: "created")
        } catch {
            return Self.refused(id, "project.initFailed", "git could not start the project \(name)", ["name": .string(name)])
        }
        return Self.answer(id, ["folder": folder])
    }

    private var currentProjectsFolderOfFixture: String { CarrierPlaces(folder: home).chatProjects }

    private func chatReply(to line: Data) -> Data {
        let request = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
        if let cmd = request?["cmd"] as? String { locked { chatAsked[cmd, default: 0] += 1 } }
        guard let id = request?["id"] as? Int else { return Self.refused(nil, "request.invalid", "invalid request") }
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
                return Self.refused(id, "session.unknown", "unknown session")
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
                "session": locked {
                    let listed = chatSessions.first { $0["id"] as? String == session }
                    var summary: [String: Any] = ["state": listed?["state"] as? String ?? "idle"]
                    if let preparation = listed?["preparation"] as? String { summary["preparation"] = preparation }
                    // what the real host adds to the summary of `events`, from the row its list gives
                    for key in ["agent", "archived", "live", "background"] { if let value = listed?[key] { summary[key] = value } }
                    return summary
                },
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
            return git ? Self.refused(id, "workspace.fetchFailed", "The fetch of origin failed") : Self.refused(id, "workspace.notGit", "That folder is not a git repository")
        case "githubRepos":
            guard let page = request?["page"] as? Int else { break }
            return chatGithubRepos[String(page)].map { Self.answer(id, $0) } ?? Self.refused(id, "github.noAnswer", "GitHub did not answer; check \"gh auth status\"")
        case "repoBranches":
            guard let repo = request?["repo"] as? String else { break }
            return chatBranches[repo].map { Self.answer(id, $0) } ?? Self.refused(id, "github.repoNotFound", "\(repo) was not found, or your GitHub login cannot see it", ["repo": .string(repo)])
        case "cloneProject":
            guard let repo = request?["repo"] as? String else { break }
            return cloneProject(id, repo, parent: request?["parent"] as? String)
        case "newProject":
            guard let name = request?["name"] as? String else { break }
            return newProject(id, name, parent: request?["parent"] as? String)
        case "projectClones":
            return Self.answer(id, ["clones": locked { chatClones }])
        case "projectWorktrees":
            guard let folder = request?["folder"] as? String else { break }
            var reply = chatProjectWorktrees[(folder as NSString).lastPathComponent] ?? ["main": ["branch": "main"], "worktrees": [Any]()]
            let main = reply["main"] as? [String: Any]
            reply["main"] = ["path": folder, "branch": main?["branch"] ?? NSNull(), "state": main?["state"] ?? "clean"]
            let gone = locked { removedWorktrees }
            reply["worktrees"] = (reply["worktrees"] as? [[String: Any]])?.filter { gone.contains($0["path"] as? String ?? "") == false }
            return Self.answer(id, reply)
        case "projectDisk":
            guard let folders = request?["folders"] as? [String] else { break }
            return Self.answer(id, ["projects": folders.map { folder in
                guard var figure = chatProjectDisk[(folder as NSString).lastPathComponent] else {
                    return ["folder": folder, "bytes": NSNull(), "measuredAt": NSNull(), "parts": [String: Any]()] as [String: Any]
                }
                // the golden file names the project's own folder "main", as the host's answer names it by its real path
                figure["parts"] = (figure["parts"] as? [String: Any] ?? [:]).reduce(into: [String: Any]()) { $0[$1.key == "main" ? folder : $1.key] = $1.value }
                figure["folder"] = folder
                return figure
            }, "measuring": [String]()])
        case "removeProjectWorktree":
            guard let folder = request?["folder"] as? String, let path = request?["path"] as? String else { break }
            let listed = chatProjectWorktrees[(folder as NSString).lastPathComponent]?["worktrees"] as? [[String: Any]] ?? []
            guard let found = listed.first(where: { $0["path"] as? String == path }), locked({ removedWorktrees.contains(path) }) == false else { return Self.refused(id, "worktree.unknown", "That is not a worktree of this project") }
            switch found["state"] as? String {
            case "sessionOpen": return Self.refused(id, "worktree.sessionOpen", "Its session is open")
            case "uncommitted": return Self.refused(id, "worktree.uncommitted", "It has uncommitted changes")
            default:
                locked { _ = removedWorktrees.insert(path) }
                return Self.answer(id, [String: Any]())
            }
        case "cleanProjectWorktrees":
            guard let folder = request?["folder"] as? String else { break }
            let planned = chatProjectCleanup[(folder as NSString).lastPathComponent] ?? ["removed": [Any](), "skipped": [Any]()]
            let gone = locked { removedWorktrees }
            let removed = (planned["removed"] as? [[String: Any]] ?? []).filter { gone.contains($0["path"] as? String ?? "") == false }
            if request?["run"] as? Bool == true { locked { removedWorktrees.formUnion(removed.compactMap { $0["path"] as? String }) } }
            return Self.answer(id, ["removed": removed, "skipped": planned["skipped"] ?? [Any]()])
        case "dismissClone":
            guard let repo = request?["repo"] as? String else { break }
            return Self.answer(id, ["clones": locked {
                chatClones.removeAll { ($0["repo"] as? String)?.lowercased() == repo.lowercased() && $0["state"] as? String == "failed" }
                return chatClones
            }])
        case "providers":
            return Self.answer(id, providersReply())
        case "usage":
            return Self.answer(id, chatUsage)
        case "usageOverride":
            guard let model = request?["model"] as? String, let action = request?["action"] as? String else { break }
            return Self.answer(id, ["model": model, "action": action])
        case "suggestName":
            let names = chatNames["suggestions"] as? [String] ?? []
            guard request?["folder"] is String, names.isEmpty == false else { break }
            return Self.answer(id, ["name": locked { defer { suggested += 1 }; return names[suggested % names.count] }])
        case "checkName":
            guard request?["folder"] is String, let name = request?["name"] as? String else { break }
            return Self.answer(id, nameCheck(name))
        case "open":
            if let plan = request?["plan"] as? [String: Any] { return openPlan(id, plan) }
            return open(id, request ?? [:])
        case "resume":
            // a closed session wakes: the next list says it is live
            guard let session = request?["sessionId"] as? String else { break }
            let found = locked { () -> Bool in
                guard let at = chatSessions.firstIndex(where: { $0["id"] as? String == session }) else { return false }
                chatSessions[at]["live"] = true
                return true
            }
            return found ? Self.answer(id, [String: Any]()) : Self.refused(id, "session.unknown", "unknown session")
        case "switchAgent":
            guard let session = request?["sessionId"] as? String, let agent = request?["agent"] as? String else { break }
            return switchAgent(id, session, to: agent)
        case "send":
            guard let session = request?["sessionId"] as? String, let text = request?["text"] as? String else { break }
            // a session whose list entry says `fixtureRefuseSend` refuses every send with those words (a provider that is not signed in)
            if let refusal = locked({ chatSessions.first { $0["id"] as? String == session }?["fixtureRefuseSend"] as? String }) { return Self.refused(id, "agent.notLoggedIn", refusal) }
            let found = locked { () -> Bool in
                guard chatSessions.contains(where: { $0["id"] as? String == session }) else { return false }
                let events = chatConversations[session]?.events ?? []
                chatConversations[session, default: ([], "")].events = events + [["id": (events.last?["id"] as? Int ?? 0) + 1, "at": Int(Date().timeIntervalSince1970 * 1000), "kind": "user", "text": text]]
                return true
            }
            return found ? Self.answer(id, [String: Any]()) : Self.refused(id, "session.unknown", "unknown session")
        case "answer":
            guard let session = request?["sessionId"] as? String, let approval = request?["approvalId"] as? String, let choice = request?["choiceId"] as? String else { break }
            lock.lock()
            defer { lock.unlock() }
            var events = chatConversations[session]?.events ?? []
            guard let asked = Self.pending(events).first(where: { $0["approvalId"] as? String == approval }) else {
                return Self.refused(id, "session.approval.notPending", "That approval is not pending: it is unknown or was already answered")
            }
            guard (asked["choices"] as? [[String: Any]] ?? []).contains(where: { $0["id"] as? String == choice }) else {
                return Self.refused(id, "session.approval.choiceUnknown", "That is not one of the choices")
            }
            var answered: [String: Any] = ["id": (events.last?["id"] as? Int ?? 0) + 1, "at": Int(Date().timeIntervalSince1970 * 1000), "kind": "approval_answered", "approvalId": approval, "choiceId": choice]
            if let answers = request?["answers"] as? [String: String] { answered["answers"] = answers }
            events.append(answered)
            chatConversations[session]?.events = events
            return Self.line("{\"id\":\(id),\"ok\":true,\"data\":{}}")
        case "setOption":
            guard let session = request?["sessionId"] as? String, let option = request?["option"] as? String, let value = request?["value"] as? String,
                let at = chatOptions[session]?.firstIndex(where: { $0["id"] as? String == option })
            else { return Self.refused(id, "session.option.unknown", "This agent has no such option", ["option": .string(request?["option"] as? String ?? "")]) }
            let listed = (chatOptions[session]?[at]["values"] as? [[String: Any]])?.contains { $0["id"] as? String == value } ?? false
            guard listed else { return Self.refused(id, "session.option.valueUnknown", "The agent does not offer that value for \(option)", ["option": .string(option), "value": .string(value)]) }
            chatOptions[session]?[at]["current"] = value
            return Self.line("{\"id\":\(id),\"ok\":true,\"data\":{}}")
        case "stopTask":
            guard let session = request?["sessionId"] as? String, let task = request?["taskId"] as? String else { break }
            lock.lock()
            defer { lock.unlock() }
            // a task the session waits for in the background: as the host does, it is gone from the session's row
            if let at = chatSessions.firstIndex(where: { $0["id"] as? String == session }), var tasks = chatSessions[at]["background"] as? [[String: Any]],
                let found = tasks.firstIndex(where: { $0["id"] as? String == task }) {
                tasks.remove(at: found)
                chatSessions[at]["background"] = tasks
                return Self.line("{\"id\":\(id),\"ok\":true,\"data\":{}}")
            }
            // else a running subagent: the host answers at once and the agent says the task stopped, here the event comes with the answer
            var events = chatConversations[session]?.events ?? []
            let own = events.filter { $0["kind"] as? String == "task" && $0["taskId"] as? String == task }
            let ended = own.contains { ["completed", "failed", "stopped"].contains($0["state"] as? String ?? "") }
            guard let started = own.first(where: { $0["state"] as? String == "started" }), ended == false else {
                return Self.refused(id, "session.task.notRunning", "That task is not running")
            }
            events.append(["id": (events.last?["id"] as? Int ?? 0) + 1, "at": Int(Date().timeIntervalSince1970 * 1000), "kind": "task", "callId": started["callId"] as Any, "taskId": task, "state": "stopped"])
            chatConversations[session]?.events = events
            return Self.line("{\"id\":\(id),\"ok\":true,\"data\":{}}")
        case "interrupt":
            guard let session = request?["sessionId"] as? String else { break }
            // with no turn running it stops what the session waits for in the background
            locked { if let at = chatSessions.firstIndex(where: { $0["id"] as? String == session }) { chatSessions[at]["background"] = [] as [[String: Any]] } }
            return Self.line("{\"id\":\(id),\"ok\":true,\"data\":{}}")
        case "regenerateTitle":
            guard let session = request?["sessionId"] as? String else { break }
            // a session whose list entry says `fixtureRefuseTitle` refuses with those words (no text generator chosen); any other gets a made-up title
            return locked {
                guard let at = chatSessions.firstIndex(where: { $0["id"] as? String == session }) else { return Self.refused(id, "session.unknown", "There is no such session") }
                if let refusal = chatSessions[at]["fixtureRefuseTitle"] as? String { return Self.refused(id, "title.noGenerator", refusal) }
                regeneratedSessionIds.insert(session)
                chatSessions[at]["title"] = "Regenerated title"
                return Self.answer(id, ["title": "Regenerated title"])
            }
        case "regenerateTitles":
            let whole = (try? ProvidersFile(folder: home).read()).flatMap { $0 }
                .flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
            let chosen = whole?["textGenerator"] as? String
            let declared = (whole?["textGenerators"] as? [String: Any])?[chosen ?? ""] != nil
            guard chosen != nil, declared else {
                return Self.refused(id, "title.noGenerator", "Could not write titles: no text generator is chosen; choose one in Providers")
            }
            return locked {
                var started = 0
                for index in chatSessions.indices {
                    guard chatSessions[index]["parentSessionId"] as? String == nil,
                        chatSessions[index]["fixtureRefuseTitle"] == nil,
                        let sessionId = chatSessions[index]["id"] as? String,
                        regeneratedSessionIds.contains(sessionId) == false
                    else { continue }
                    regeneratedSessionIds.insert(sessionId)
                    chatSessions[index]["title"] = "Regenerated title"
                    started += 1
                }
                return Self.answer(id, ["started": started])
            }
        case "editChatSettings":
            guard let changes = request?["changes"] as? [String: Any] else { break }
            return editChatSettings(id, changes)
        case "setAccounts", "addAccount", "editAccount", "removeAccount", "setTextGenerator":
            switch fixtureProvidersChange(request ?? [:], home: home) {
            case .data(let data): return Self.answer(id, data)
            case .refused(let reason): return Self.refused(id, reason.code ?? "request.invalid", reason.text, reason.params)
            }
        case "addProject", "removeProject", "editProject", "moveProject", "editProjectIcon", "editProjectDefaults", "editProjectTags", "setProjectActions", "setProjectsFolder":
            guard let cmd = request?["cmd"] as? String, let request, let change = ProjectsChange(cmd: cmd, request: request) else { break }
            let (data, refusal) = applyProjectsChange(change, home: home)
            if let refusal { return Self.refused(id, refusal.code ?? "request.internal", refusal.text, refusal.params) }
            return Self.answer(id, data ?? [:])
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

    /// `editChatSettings` as the host answers it: the scratch `chat.json` read again, each key set (null removes it), the four keys checked as the host's schema does, and written only when
    /// all hold; the reply is the keys as the file now has them. A file that is not a JSON object is refused and left as it was.
    private func editChatSettings(_ id: Int, _ changes: [String: Any]) -> Data {
        let url = URL(fileURLWithPath: CarrierPlaces(folder: home).chatConfig)
        var file: [String: Any] = [:]
        if let data = try? Data(contentsOf: url) {
            guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                return Self.refused(id, "config.problem", "chat.json is not a JSON object, so it was not changed", ["path": "(file)", "problem": "notAnObject"])
            }
            file = object
        }
        for (key, value) in changes { file[key] = value is NSNull ? nil : value }
        func refusal(_ path: String, _ problem: String, _ words: String) -> Data {
            Self.refused(id, "config.problem", "\(path): \(words)", ["path": .string(path), "problem": .string(problem)])
        }
        /// the days of an age: nil for "never" or a key that is not there, and whether the value is one the schema takes
        func age(_ key: String) -> (days: Int?, valid: Bool) {
            guard let value = file[key], value as? String != "never" else { return (nil, true) }
            guard let days = value as? Int, days > 0 else { return (nil, false) }
            return (days, true)
        }
        let (archive, delete) = (age("archiveAfterDays"), age("deleteAfterDays"))
        guard archive.valid else { return refusal("archiveAfterDays", "too_small", "Too small: expected number to be >0") }
        guard delete.valid else { return refusal("deleteAfterDays", "too_small", "Too small: expected number to be >0") }
        if let start = file["worktreeStart"], ["remote", "local"].contains(start as? String ?? "") == false { return refusal("worktreeStart", "invalid_value", "Invalid option: expected one of \"remote\"|\"local\"") }
        if let idle = file["idleCloseMinutes"], [10, 30, 60].contains(idle as? Int ?? 0) == false { return refusal("idleCloseMinutes", "invalid_union", "must be 10, 30 or 60 (minutes)") }
        if let archive = archive.days, let delete = delete.days, delete <= archive { return refusal("deleteAfterDays", "custom", "must be greater than archiveAfterDays") }
        guard let data = try? JSONSerialization.data(withJSONObject: file, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]), (try? data.write(to: url, options: .atomic)) != nil else {
            return Self.refused(id, "request.internal", "internal error")
        }
        return Self.answer(id, ["saved": changes.keys.reduce(into: [String: Any]()) { $0[$1] = file[$1] }])
    }

    /// The golden check of a worktree name: free unless `chat-names.json` says why not.
    private func nameCheck(_ name: String) -> [String: Any] {
        (chatNames["checks"] as? [String: [String: Any]])?[name] ?? chatNames["free"] as? [String: Any] ?? ["valid": true, "free": true]
    }

    /// `open`: a session in memory, in a worktree of the folder when asked; refused as the host does. A plan opens the same session with its
    /// text already sent and every step done at once.
    private func openPlan(_ id: Int, _ plan: [String: Any]) -> Data {
        let place = plan["workspace"] as? [String: Any]
        // a repository is cloned by the host under its projects folder, which the fixture only names
        let folder = place?["folder"] as? String ?? (place?["repo"] as? String).map { "/Users/dev/projects/\($0)" }
        guard let folder, let text = plan["text"] as? String else { return Self.refused(id, "request.invalid", "invalid request") }
        var request: [String: Any] = ["agent": plan["agent"] as Any, "folder": folder]
        if var from = plan["branch"] as? String {
            // as the host does: a remote start of a branch the repository lists as `origin/<name>` is cut from that ref
            let listed = (chatWorkspaces[folder]?["branches"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
            if (plan["worktree"] as? [String: Any])?["startFrom"] as? String == "remote", from.hasPrefix("origin/") == false, listed.contains("origin/\(from)") { from = "origin/\(from)" }
            request["worktree"] = ["from": from, "name": (plan["worktree"] as? [String: Any])?["name"] as Any].compactMapValues { $0 is NSNull ? nil : $0 }
        }
        let opened = open(id, request)
        guard let reply = (try? JSONSerialization.jsonObject(with: opened.dropLast())) as? [String: Any], reply["ok"] as? Bool == true,
            let session = (reply["data"] as? [String: Any])?["session"] as? [String: Any], let sessionId = session["id"] as? String else { return opened }
        let now = Int(Date().timeIntervalSince1970 * 1000)
        locked {
            chatConversations[sessionId, default: ([], "")].events = ["agent", "message"].enumerated().map { at, step in
                ["id": at + 1, "at": now, "kind": "step", "step": step, "status": "done"]
            } + [["id": 3, "at": now, "kind": "user", "text": text]]
        }
        return opened
    }

    /// As the host does: an idle session takes another listed agent and gets the notice of the switch; a working or waiting one, the agent it has and one that is not listed are refused.
    private func switchAgent(_ id: Int, _ session: String, to agent: String) -> Data {
        guard let chosen = ((try? JSONSerialization.jsonObject(with: chatAgents)) as? [[String: Any]])?.first(where: { $0["name"] as? String == agent }) else {
            return Self.refused(id, "agent.unknown", "There is no chat agent named \"\(agent)\"", ["agent": .string(agent)])
        }
        return locked {
            guard let at = chatSessions.firstIndex(where: { $0["id"] as? String == session }) else { return Self.refused(id, "session.unknown", "There is no such session") }
            let from = chatSessions[at]["agent"] as? String ?? ""
            let state = chatSessions[at]["state"] as? String
            if state != "idle" { return Self.refused(id, "session.switchAgent.busy", "This session is \(state == "working" ? "working" : "waiting for an approval"); interrupt it or wait, then switch its agent", ["state": .string(state ?? "")]) }
            if from == agent { return Self.refused(id, "session.switchAgent.same", "This session already has the agent \"\(agent)\"", ["agent": .string(agent)]) }
            if chosen["found"] as? Bool == false { return Self.refused(id, "agent.notFound", "The agent \"\(agent)\" is not found on this machine", ["agent": .string(agent)]) }
            chatSessions[at]["agent"] = agent
            chatSessions[at]["harness"] = chosen["harness"] as? String ?? agent
            chatSessions[at]["live"] = true
            let events = chatConversations[session]?.events ?? []
            let notice: [String: Any] = ["id": (events.last?["id"] as? Int ?? 0) + 1, "at": Int(Date().timeIntervalSince1970 * 1000), "kind": "notice", "text": "The agent changed from \(from) to \(agent).", "switched": ["from": from, "to": agent]]
            chatConversations[session, default: ([], "")].events = events + [notice]
            var summary = chatSessions[at]
            for key in ["live", "kept", "deleteAt", "lastMessage", "turns", "model"] { summary[key] = nil }
            return Self.answer(id, ["session": summary, "options": [Any]()])
        }
    }

    private func open(_ id: Int, _ request: [String: Any]) -> Data {
        guard let agent = request["agent"] as? String, let folder = request["folder"] as? String else { return Self.refused(id, "request.invalid", "invalid request") }
        guard let chosen = ((try? JSONSerialization.jsonObject(with: chatAgents)) as? [[String: Any]])?.first(where: { $0["name"] as? String == agent }) else {
            return Self.refused(id, "agent.unknown", "There is no chat agent named \"\(agent)\"", ["agent": .string(agent)])
        }
        var session: [String: Any] = [
            "id": UUID().uuidString.lowercased(), "agent": agent, "harness": chosen["harness"] as? String ?? agent, "folder": folder, "workspace": ["kind": "folder"],
            "state": "idle", "createdAt": Int(Date().timeIntervalSince1970 * 1000), "lastActiveAt": Int(Date().timeIntervalSince1970 * 1000), "archived": false, "live": true,
        ]
        if let worktree = request["worktree"] as? [String: Any] {
            guard let info = chatWorkspaces[folder], info["git"] as? Bool == true, info["bare"] as? Bool != true else { return Self.refused(id, "worktree.notGit", "Worktrees need a git repository") }
            let from = worktree["from"] as? String ?? ""
            guard (info["branches"] as? [[String: Any]])?.contains(where: { $0["name"] as? String == from }) == true else {
                return Self.refused(id, "worktree.startNotListed", "The branch to start from is not one this repository lists")
            }
            let names = chatNames["suggestions"] as? [String] ?? []
            let name = worktree["name"] as? String ?? names.first ?? "worktree"
            let check = nameCheck(name)
            guard check["valid"] as? Bool == true, check["free"] as? Bool == true else { return Self.refused(id, check["code"] as? String ?? "request.invalid", check["reason"] as? String ?? "That name cannot be used") }
            let path = "/Users/dev/.carrier/chat/worktrees/local/\(URL(fileURLWithPath: folder).lastPathComponent)/\(name)"
            session["folder"] = path
            session["workspace"] = ["kind": "worktree", "branch": "carrier/\(name)", "from": from, "base": folder, "path": path]
        }
        locked { chatSessions.insert(session, at: 0) }
        return Self.answer(id, ["session": session, "options": [Any]()])
    }

    /// The golden `providers` reply as `<home>/providers.json` leaves it, so an Add, an edit or a Remove made in the app shows in the page as it
    /// would against a real host: an account of the file is listed (what the golden reply knows of its name, else what this Mac has of its
    /// harness) with the file's display name, binary, folder; a harness the file gives no account is "found, not added".
    private func providersReply() -> [String: Any] {
        var reply = chatProviders
        let whole = (try? ProvidersFile(folder: home).read()).flatMap { $0 }
            .flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
        let file = whole?["providers"] as? [String: [String: Any]] ?? [:]
        // the generator in use, as the host reads it: the entry `textGenerator` names
        reply["textGenerator"] = (whole?["textGenerator"] as? String).flatMap { name in
            (whole?["textGenerators"] as? [String: [String: Any]])?[name].map { ["name": name].merging($0) { $1 } }
        }
        let golden = reply["accounts"] as? [[String: Any]] ?? []
        let unadded = reply["unadded"] as? [[String: Any]] ?? []
        // what this Mac has of each harness
        var seen: [String: [String: Any]] = [:]
        for entry in golden + unadded {
            guard let harness = entry["harness"] as? String, seen[harness] == nil else { continue }
            seen[harness] = ["path": entry["path"] ?? "", "version": entry["version"] as Any]
        }
        // the golden reply's accounts keep their order, those the app added follow by name
        let goldenNames = golden.compactMap { $0["name"] as? String }
        let order = goldenNames.filter { file[$0] != nil } + file.keys.filter { goldenNames.contains($0) == false }.sorted()
        reply["accounts"] = order.compactMap { name -> [String: Any]? in
            guard let account = file[name], let harness = account["harness"] as? String else { return nil }
            var entry = golden.first { $0["name"] as? String == name }
                ?? ["name": name, "harness": harness, "found": seen[harness] != nil, "path": seen[harness]?["path"] ?? "", "state": "unknown"]
            if entry["version"] == nil, let version = seen[harness]?["version"] as? String { entry["version"] = version }
            for key in ["displayName", "command", "configDir"] { entry[key] = account[key] }
            return entry
        }
        let taken = Set(file.values.compactMap { $0["harness"] as? String })
        reply["unadded"] = seen.keys.sorted().filter { taken.contains($0) == false }.map { harness in
            var entry: [String: Any] = ["harness": harness, "path": seen[harness]?["path"] ?? ""]
            if let version = seen[harness]?["version"] as? String { entry["version"] = version }
            return entry
        }
        return reply
    }

    static func answer(_ id: Int, _ data: Any) -> Data {
        let body = (try? JSONSerialization.data(withJSONObject: data, options: .sortedKeys)).map { String(decoding: $0, as: UTF8.self) } ?? "null"
        return line("{\"id\":\(id),\"ok\":true,\"data\":" + body + "}")
    }

    /// The refusal as the host answers it: its words in `error`, and its `code` and `params` beside them (the codes are in `text-codes.json`).
    static func refused(_ id: Int?, _ code: String, _ reason: String, _ params: [String: TextParam] = [:]) -> Data {
        let reply: [String: Any] = ["id": id as Any? ?? NSNull(), "ok": false, "error": reason, "code": code, "params": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(params))) ?? [:]]
        return line(String(decoding: (try? JSONSerialization.data(withJSONObject: reply, options: .sortedKeys)) ?? Data(), as: UTF8.self))
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

extension FixtureServer {
    /// A time that is "N ms ago" in the golden list is made relative to the launch, so ages ("now", "5m", "3h") and the working clock look
    /// as they do live: `lastActiveAgo` sets `lastActiveAt`, `createdAgo` `createdAt`, and `startedAgo` the `startedAt` of a background task.
    static func relativeTimes(_ session: [String: Any], nowMs: Int) -> [String: Any] {
        var session = session
        for (ago, field) in [("lastActiveAgo", "lastActiveAt"), ("createdAgo", "createdAt")] {
            if let ms = session.removeValue(forKey: ago) as? Int { session[field] = nowMs - ms }
        }
        session["background"] = (session["background"] as? [[String: Any]])?.map { task in
            var task = task
            if let ms = task.removeValue(forKey: "startedAgo") as? Int { task["startedAt"] = nowMs - ms }
            return task
        }
        if session["background"] == nil { session.removeValue(forKey: "background") }
        return session
    }
}
