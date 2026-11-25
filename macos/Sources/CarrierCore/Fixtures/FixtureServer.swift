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

    let listener: Int32
    private let chatListener: Int32
    let chatAgents: Data
    /// The golden replies of the worktree requests, and which of the suggested names `suggestName` answers next.
    let chatWorkspaces: [String: [String: Any]]
    let chatFetches: [String: [String: Any]]
    let chatGithubRepos: [String: [String: Any]]
    let chatBranches: [String: [String: Any]]
    /// `chat-project-worktrees.json`: the `projectWorktrees` reply by the project folder's name; any other project has its main clone and no worktrees.
    let chatProjectWorktrees: [String: [String: Any]]
    /// `chat-project-disk.json`: the `projectDisk` figure by the project folder's name.
    let chatProjectDisk: [String: [String: Any]]
    /// `chat-project-cleanup.json`: what `cleanProjectWorktrees` removes and skips, by the project folder's name; any other project has nothing to clean up.
    let chatProjectCleanup: [String: [String: Any]]
    /// The worktrees `removeProjectWorktree` and Clean up took, which `projectWorktrees` no longer lists (read with `lock`).
    var removedWorktrees: Set<String> = []
    /// The clones from Settings the host runs or has failed: `chat-project-clones.json` at the start, then what `cloneProject` and `dismissClone` change (read with `lock`).
    var chatClones: [[String: Any]]
    let chatProviders: [String: Any]
    let chatNames: [String: Any]
    /// The golden `usage` reply, for any filter.
    let chatUsage: [String: Any]
    var suggested = 0
    /// `archive` and `delete` change it; the sockets' threads share it, so it is read and written with `lock`.
    var chatSessions: [[String: Any]]
    /// What `deletePreview` says of the sessions in a worktree, by session id: the entries of `chat-delete-preview.json`.
    var chatWorktrees: [String: Any] = [:]
    /// Each session's golden conversation: its events and the message being written.
    var chatConversations: [String: (events: [[String: Any]], streaming: String)] = [:]
    /// What the provider offers in each golden conversation that lists options; `setOption` changes the current value here.
    var chatOptions: [String: [[String: Any]]] = [:]
    /// How many times the chat socket was asked each request, for the tests that count what the app asks (read with `lock`).
    var chatAsked: [String: Int] = [:]
    /// How many connections the chat socket accepted (each one gets a hello), for the tests that count what the app opens.
    var chatConnected = 0
    /// The same two counts for the engine's socket.
    var engineAsked: [String: Int] = [:]
    var engineConnected = 0
    /// Under `longTranscript`, every listed session answers this instead.
    var longChat: [[String: Any]]?
    /// Sessions already titled by `regenerateTitle` or `regenerateTitles`, so a second bulk ask sees 0 left.
    var regeneratedSessionIds: Set<String> = []
    let chatHello = Data("{\"event\":\"hello\",\"protocol\":1,\"pid\":0,\"startedAt\":0,\"version\":\"fixture\",\"capabilities\":[\"agents\",\"list\",\"open\",\"resume\",\"send\",\"events\",\"answer\",\"setOption\",\"archive\",\"delete\",\"deletePreview\",\"workspace\",\"fetch\",\"suggestName\",\"checkName\",\"cloneRepo\",\"createProject\",\"githubRepos\",\"repoBranches\",\"providers\",\"plan\",\"usage\",\"usageOverride\",\"accountIdentity\",\"accountPalette\",\"switchAgent\",\"interrupt\",\"stopTask\",\"worktreeStart\",\"fetchIfStale\",\"projects\",\"worktreeIntegration\",\"textGenerators\",\"regenerateTitle\",\"regenerateTitles\",\"config\"]}\n".utf8)
    let data: [String: Data]
    let hello: Data
    var stopped = false
    let lock = NSLock()

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
    static let controls: Set<String> = ["pause", "resume", "checkNow", "stop", "resumeEpic", "recoverEpic", "reload"]

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
            try Data(accounts.utf8).write(to: URL(fileURLWithPath: places.providers))
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

    static func answer(_ id: Int, _ data: Any) -> Data {
        let body = (try? JSONSerialization.data(withJSONObject: data, options: .sortedKeys)).map { String(decoding: $0, as: UTF8.self) } ?? "null"
        return line("{\"id\":\(id),\"ok\":true,\"data\":" + body + "}")
    }

    /// The refusal as the host answers it: its words in `error`, and its `code` and `params` beside them (the codes are in `text-codes.json`).
    static func refused(_ id: Int?, _ code: String, _ reason: String, _ params: [String: TextParam] = [:]) -> Data {
        let reply: [String: Any] = ["id": id as Any? ?? NSNull(), "ok": false, "error": reason, "code": code, "params": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(params))) ?? [:]]
        return line(String(decoding: (try? JSONSerialization.data(withJSONObject: reply, options: .sortedKeys)) ?? Data(), as: UTF8.self))
    }

    /// The approvals asked and not answered yet, as the host lists them in `events`.
    static func pending(_ events: [[String: Any]]) -> [[String: Any]] {
        let answered = Set(events.filter { $0["kind"] as? String == "approval_answered" }.compactMap { $0["approvalId"] as? String })
        return events.filter { $0["kind"] as? String == "approval" && answered.contains($0["approvalId"] as? String ?? "") == false }
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
