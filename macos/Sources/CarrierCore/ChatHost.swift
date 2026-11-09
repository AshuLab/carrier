import Foundation

// The app's side of the chat host's socket (docs/specs/chat-host.md, sessions-in-the-app.md): the requests it needs so far,
// a monitor that says whether the host answers, and the rule for the Sessions + flag. The slices that use more requests add them to `ChatHost`.

public struct ChatAgent: Decodable, Equatable {
    public let name: String
    public let harness: String
    public let model: String?
    /// Whether the agent's binary was found on the host's machine.
    public let found: Bool

    public init(name: String, harness: String, model: String? = nil, found: Bool) {
        self.name = name
        self.harness = harness
        self.model = model
        self.found = found
    }
}

/// A session as the host's `list` carries it: times are milliseconds since the epoch.
public struct ChatSession: Decodable, Equatable {
    public enum State: String, Decodable { case working, waitingApproval = "waiting_approval", idle, preparing }
    /// Whether the host is preparing the session from its plan, or a step failed; nil for a session that is not (or a host that does not say).
    public enum Preparation: String, Decodable { case running, failed }

    public let id: String
    public let agent: String
    public let harness: String
    public let folder: String
    public let title: String?
    public let state: State
    public let createdAt: Int
    public let lastActiveAt: Int
    public let archived: Bool
    /// Set for a session in a worktree: `base` is the repository's folder, which is where the session is grouped. The host says
    /// `{kind: "folder"}` for a session in the base folder itself, which is nil here.
    public let workspace: Workspace?
    /// Whether the session's agent process runs: a closed one is resumed before a message is sent to it.
    public let live: Bool
    public let preparation: Preparation?
    /// True while the clock spares the session because its worktree holds unsaved work. A host that leaves it out is not keeping it.
    public let kept: Bool
    /// When the clock deletes the session, in milliseconds since the epoch; nil when it will not, and from a host that leaves it out.
    public let deleteAt: Int?
    /// What the agent last wrote, on one line and cut; nil before it answered, and from a host or a reply that leaves it out.
    public let lastMessage: String?
    /// The turns that finished, and the model of the last; zero and nil from a host or a reply that leaves them out.
    public let turns: Int
    public let model: String?

    public struct Workspace: Decodable, Equatable {
        public let base: String
        public let branch: String?
    }

    private enum CodingKeys: String, CodingKey { case id, agent, harness, folder, title, state, createdAt, lastActiveAt, archived, workspace, live, preparation, kept, deleteAt, lastMessage, turns, model }
    private struct Kind: Decodable {
        let kind: String
        let base: String?
        let branch: String?
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        agent = try values.decode(String.self, forKey: .agent)
        harness = try values.decode(String.self, forKey: .harness)
        folder = try values.decode(String.self, forKey: .folder)
        title = try values.decodeIfPresent(String.self, forKey: .title)
        state = try values.decode(State.self, forKey: .state)
        createdAt = try values.decode(Int.self, forKey: .createdAt)
        lastActiveAt = try values.decode(Int.self, forKey: .lastActiveAt)
        archived = try values.decode(Bool.self, forKey: .archived)
        live = try values.decode(Bool.self, forKey: .live)
        // a value this app does not know is no preparation, as a host that leaves the field out
        preparation = (try? values.decodeIfPresent(Preparation.self, forKey: .preparation)) ?? nil
        kept = try values.decodeIfPresent(Bool.self, forKey: .kept) ?? false
        deleteAt = try values.decodeIfPresent(Int.self, forKey: .deleteAt)
        lastMessage = try values.decodeIfPresent(String.self, forKey: .lastMessage)
        turns = try values.decodeIfPresent(Int.self, forKey: .turns) ?? 0
        model = try values.decodeIfPresent(String.self, forKey: .model)
        let placed = try values.decodeIfPresent(Kind.self, forKey: .workspace)
        guard let placed, placed.kind == "worktree" else { workspace = nil; return }
        guard let base = placed.base else { throw DecodingError.keyNotFound(CodingKeys.workspace, .init(codingPath: decoder.codingPath, debugDescription: "a worktree without its base folder")) }
        workspace = Workspace(base: base, branch: placed.branch)
    }
}

/// What `deletePreview` says of one session: `worktree` is nil for a session in a base folder, else what deleting would discard from it.
public struct SessionDeletePreview: Decodable, Equatable {
    public let sessionId: String
    public let worktree: Worktree?

    /// `dirty` is the files with uncommitted changes, `unpushed` the commits on the branch that no other branch or remote branch holds.
    public struct Worktree: Decodable, Equatable {
        public let path: String
        public let branch: String
        public let dirty: Int
        public let unpushed: Int

        public init(path: String, branch: String, dirty: Int, unpushed: Int) {
            self.path = path
            self.branch = branch
            self.dirty = dirty
            self.unpushed = unpushed
        }
    }

    public init(sessionId: String, worktree: Worktree?) {
        self.sessionId = sessionId
        self.worktree = worktree
    }
}

/// The reply of `cloneRepo`: where the repository is, and whether it was already there (and so fetched, not cloned).
public struct ClonedRepo: Decodable, Equatable {
    public let folder: String
    public let repo: String
    public let fetched: Bool

    public init(folder: String, repo: String, fetched: Bool) {
        self.folder = folder
        self.repo = repo
        self.fetched = fetched
    }
}

/// The reply of `githubRepos`: one page of the repositories the person's `gh` login can read, whether the host has another, and (page 1
/// only) the login.
public struct GithubReposPage: Decodable, Equatable {
    public let repos: [AvailableRepo]
    public let hasMore: Bool
    public let login: String?

    public init(repos: [AvailableRepo], hasMore: Bool, login: String? = nil) {
        self.repos = repos
        self.hasMore = hasMore
        self.login = login
    }
}

/// The reply of `repoBranches`: the default branch of a repository that need not be on disk and its branches (the first hundred, as GitHub lists
/// them), and whether there are more.
public struct RepoBranches: Decodable, Equatable {
    public let defaultBranch: String
    public let branches: [String]
    public let hasMore: Bool

    public init(defaultBranch: String, branches: [String], hasMore: Bool = false) {
        self.defaultBranch = defaultBranch
        self.branches = branches
        self.hasMore = hasMore
    }

    private enum CodingKeys: String, CodingKey { case defaultBranch = "default", branches, hasMore }
}

/// What the app needs from the chat host's socket; the real one speaks to the socket, tests use a fake.
public protocol ChatHost {
    func agents() async throws -> [ChatAgent]
    func list(archived: Bool) async throws -> [ChatSession]
    /// Creates a session from the plan, in one request that carries the first message, and returns its id at once: the host prepares it in
    /// the background (the `step` events of its conversation say how far). Only for a host whose hello lists `plan`. The host refuses a
    /// folder inside Carrier's own folders, a provider that is not logged in, and a message over its limit.
    func open(plan: SessionPlan) async throws -> String
    /// Repeats the steps of a failed preparation that did not finish (what was made is reused); refused in words for a session that is not in
    /// a failed preparation. Only for a host whose hello lists `plan`.
    func retryPreparation(_ id: String) async throws
    /// Stops the running step and deletes the session with its worktree; answers the plan it was opened with, for the draft to take back.
    /// Refused in words for a session that is not being prepared. Only for a host whose hello lists `plan`.
    func cancelPreparation(_ id: String) async throws -> SessionPlan
    /// What an agent offers (its options with the values it would start with, and the commands to invoke) before a session exists; the host
    /// starts the agent to know, and keeps the answer.
    func agentOptions(_ agent: String) async throws -> AgentOffer
    /// What a folder is as a git repository (`WorkspaceInfo.git` is false for a plain folder); refused for a folder the host will not open.
    func workspace(_ folder: String) async throws -> WorkspaceInfo
    /// Fetches the folder's `origin` and answers what the folder is after it; a fetch that fails or takes too long is refused in words.
    func fetch(_ folder: String) async throws -> WorkspaceInfo
    /// A free generated name for a worktree of the folder: the part after `carrier/`.
    func suggestName(_ folder: String) async throws -> String
    /// Whether a typed name (the part after `carrier/`) is valid and free, and why not.
    func checkName(_ folder: String, _ name: String) async throws -> NameCheck
    /// The optional requests this host answers, from its hello.
    func capabilities() async throws -> Set<ControlClient.Capability>
    /// Clones `owner/repo` into the host's projects folder, or fetches it when it is already there. It can take minutes; cancelling the
    /// task closes the request's connection, which makes the host stop and remove the half-made clone. Refused in words (not found
    /// or not visible to the person's `gh` login, `gh` missing or signed out, no network, too slow).
    func cloneRepo(_ repo: String) async throws -> ClonedRepo
    /// Makes `<projects folder>/local/<name>` with `git init -b main` and answers its path. Refused in words for a name that is taken
    /// or not a plain folder name.
    func createProject(_ name: String) async throws -> String
    /// One page (1 to 100) of the repositories the person's `gh` login can read, thirty at a time, newest push first. Refused in words
    /// (`gh` missing or signed out, no network, too slow). Gh can take seconds.
    func githubRepos(page: Int) async throws -> GithubReposPage
    /// The default branch and the branches of `owner/repo`, read from GitHub with the person's `gh` login: the repository need not be on this
    /// Mac. Refused in words (`gh` missing or signed out, no network, not found or not visible, too slow). Only for a host whose hello lists `repoBranches`.
    func repoBranches(_ repo: String) async throws -> RepoBranches
    /// The state of `git`, `gh` and each chat agent on the host's machine; `refresh` skips the answer the host kept for thirty seconds.
    /// Only for a host whose hello lists `health`.
    func health(refresh: Bool) async throws -> HostHealth
    /// The events of a session after the cursor, at most `limit` (the host takes 1 to 200).
    func events(_ id: String, after: Int, limit: Int) async throws -> ChatEvents
    /// Opens a closed session's agent again; the host refuses a `send` to one that is not live.
    func resume(_ id: String) async throws
    /// The host refuses it while the agent is answering ("The agent is still answering") and when it is over its character limit.
    func send(_ id: String, _ text: String) async throws
    /// `send` that invokes a command the session listed: `text` is what follows its name (nothing is allowed), and the host shows it as the
    /// slash and the name and tells the provider in the provider's own way.
    func send(_ id: String, _ text: String, command: String?) async throws
    /// Ends the turn that is in progress.
    func interrupt(_ id: String) async throws
    /// Passes the person's choice for a pending approval to the agent; the host refuses one that is not pending and a choice the provider did not list.
    func answer(_ id: String, approval: String, choice: String) async throws

    /// Changes one of the session's options; the host refuses a value the provider does not list and an option that can only change between turns.
    func setOption(_ id: String, option: String, value: String) async throws
    /// Sets or clears the archived mark; the host refuses a session that is working or waiting for an approval.
    func archive(_ id: String, _ archived: Bool) async throws
    /// Removes the session and its transcript, and the worktree and branch of one in a worktree; refused like `archive` for a working or waiting
    /// one, and for a worktree that cannot be removed (the session stays).
    func delete(_ id: String) async throws
    /// Gives the session a title of the person's own; the host refuses an empty one and keeps it from then on. Only for a host whose hello lists `rename`.
    func rename(_ id: String, _ title: String) async throws
    /// Asks the host to write the session's title again from what was said in it and answers the new one. Only for a host whose hello lists `regenerateTitle`.
    func regenerateTitle(_ id: String) async throws -> String
    /// What deleting these sessions would discard, one entry per id in the order asked; the host refuses the whole request when an id is unknown.
    func deletePreview(_ ids: [String]) async throws -> [SessionDeletePreview]
}

extension ChatHost {
    /// A host that cannot prepare a session from a plan has nothing to try again.
    public func retryPreparation(_ id: String) async throws { throw ControlError.remote("the chat host does not support retryPreparation") }

    /// A host that cannot prepare a session from a plan has nothing to cancel.
    public func cancelPreparation(_ id: String) async throws -> SessionPlan { throw ControlError.remote("the chat host does not support cancelPreparation") }

    /// A host that cannot list an agent's options before a session says it lists none.
    public func agentOptions(_ agent: String) async throws -> AgentOffer { AgentOffer() }

    /// A host that cannot list the branches of a repository refuses; the app only asks one that lists `repoBranches`.
    public func repoBranches(_ repo: String) async throws -> RepoBranches { throw ControlError.remote("the chat host does not support repoBranches") }

    /// A host that cannot say how the machine is refuses; the app only asks one that lists `health`.
    public func health(refresh: Bool) async throws -> HostHealth { throw ControlError.remote("the chat host does not support health") }

    /// A host that cannot rename refuses; the app only asks one that lists `rename`.
    public func rename(_ id: String, _ title: String) async throws { throw ControlError.remote("the chat host does not support rename") }

    /// A host that cannot write titles refuses; the app only asks one that lists `regenerateTitle`.
    public func regenerateTitle(_ id: String) async throws -> String { throw ControlError.remote("the chat host does not support regenerateTitle") }

    /// A host that knows no commands sends the text as it is.
    public func send(_ id: String, _ text: String, command: String?) async throws { try await send(id, text) }
}

/// The chat host over its socket: one connection per call (a host with no client attached may end itself), with the blocking
/// socket work off the caller's thread. A host that is not there, or goes away mid-call, is `ControlError.closed`; an error reply is `.remote`.
public struct SocketChatHost: ChatHost {
    private let socketPath: () -> String

    public init(socketPath: @escaping () -> String = { chatSocketPath() }) { self.socketPath = socketPath }

    public func agents() async throws -> [ChatAgent] {
        let path = socketPath()
        return try await Task.detached { try chatRequest(path, "agents", requires: .agents) }.value
    }

    public func list(archived: Bool) async throws -> [ChatSession] {
        let path = socketPath()
        let reply: ChatSessionsReply = try await Task.detached { try chatRequest(path, "list", requires: .list, fields: ",\"archived\":\(archived)") }.value
        return reply.sessions
    }

    public func open(plan: SessionPlan) async throws -> String {
        let fields = ",\"plan\":" + plan.wire
        let path = socketPath()
        let reply: OpenedReply = try await Task.detached { try chatRequest(path, "open", requires: .plan, fields: fields) }.value
        return reply.session.id
    }

    public func retryPreparation(_ id: String) async throws {
        let fields = ",\"sessionId\":\"\(try wireId(id))\""
        let path = socketPath()
        let _: AnyReply = try await Task.detached { try chatRequest(path, "retryPreparation", requires: .plan, fields: fields) }.value
    }

    /// Deleting a worktree takes git a while, so the wait for the reply is longer than the 5 seconds of the other requests.
    public func cancelPreparation(_ id: String) async throws -> SessionPlan {
        let fields = ",\"sessionId\":\"\(try wireId(id))\""
        let path = socketPath()
        let reply: CancelledReply = try await Task.detached { try chatRequest(path, "cancelPreparation", requires: .plan, fields: fields, timeout: 30) }.value
        return try reply.plan.plan
    }

    public func agentOptions(_ agent: String) async throws -> AgentOffer {
        let fields = ",\"agent\":\(jsonString(agent))"
        let path = socketPath()
        // starting the agent to read its options takes a few seconds
        return try await Task.detached { try chatRequest(path, "agentOptions", requires: .agentOptions, fields: fields, timeout: 30) }.value
    }

    public func workspace(_ folder: String) async throws -> WorkspaceInfo {
        let fields = ",\"folder\":\(jsonString(folder))"
        let path = socketPath()
        return try await Task.detached { try chatRequest(path, "workspace", requires: .workspace, fields: fields) }.value
    }

    public func fetch(_ folder: String) async throws -> WorkspaceInfo {
        let fields = ",\"folder\":\(jsonString(folder))"
        let path = socketPath()
        return try await Task.detached { try chatRequest(path, "fetch", requires: .fetch, fields: fields) }.value
    }

    public func suggestName(_ folder: String) async throws -> String {
        let fields = ",\"folder\":\(jsonString(folder))"
        let path = socketPath()
        let reply: SuggestedName = try await Task.detached { try chatRequest(path, "suggestName", requires: .suggestName, fields: fields) }.value
        return reply.name
    }

    public func checkName(_ folder: String, _ name: String) async throws -> NameCheck {
        let fields = ",\"folder\":\(jsonString(folder)),\"name\":\(jsonString(name))"
        let path = socketPath()
        return try await Task.detached { try chatRequest(path, "checkName", requires: .checkName, fields: fields) }.value
    }

    public func capabilities() async throws -> Set<ControlClient.Capability> {
        let path = socketPath()
        return try await Task.detached {
            guard let client = ControlClient.connect(path: path) else { throw ControlError.closed }
            defer { client.close() }
            _ = try client.supportedHello()
            return client.capabilities
        }.value
    }

    /// A git command has ten minutes on the host, so the wait for the reply is longer than the 5 seconds of the other requests.
    public func cloneRepo(_ repo: String) async throws -> ClonedRepo {
        let fields = ",\"repo\":\(jsonString(repo))"
        let path = socketPath()
        let connection = Abortable()
        return try await withTaskCancellationHandler {
            try await Task.detached { try chatRequest(path, "cloneRepo", requires: .cloneRepo, fields: fields, timeout: 11 * 60, abortable: connection) }.value
        } onCancel: { connection.abort() }
    }

    public func createProject(_ name: String) async throws -> String {
        struct Created: Decodable { let folder: String }
        let fields = ",\"name\":\(jsonString(name))"
        let path = socketPath()
        let reply: Created = try await Task.detached { try chatRequest(path, "createProject", requires: .createProject, fields: fields) }.value
        return reply.folder
    }

    /// A page has the host's 30 seconds for `gh`, so the wait for the reply is longer than the 5 seconds of the other requests.
    public func githubRepos(page: Int) async throws -> GithubReposPage {
        let fields = ",\"page\":\(page)"
        let path = socketPath()
        return try await Task.detached { try chatRequest(path, "githubRepos", requires: .githubRepos, fields: fields, timeout: 40) }.value
    }

    /// Both of the host's `gh` calls have its 30 seconds, so the wait for the reply is longer than the 5 seconds of the other requests.
    public func repoBranches(_ repo: String) async throws -> RepoBranches {
        let fields = ",\"repo\":\(jsonString(repo))"
        let path = socketPath()
        return try await Task.detached { try chatRequest(path, "repoBranches", requires: .repoBranches, fields: fields, timeout: 40) }.value
    }

    /// The probes of a request run in parallel with five seconds each, so the wait is longer than the 5 seconds of the other requests.
    public func health(refresh: Bool) async throws -> HostHealth {
        let fields = refresh ? ",\"refresh\":true" : ""
        let path = socketPath()
        return try await Task.detached { try chatRequest(path, "health", requires: .health, fields: fields, timeout: 15) }.value
    }

    public func events(_ id: String, after: Int, limit: Int) async throws -> ChatEvents {
        let fields = ",\"sessionId\":\"\(try wireId(id))\",\"after\":\(after),\"limit\":\(limit)"
        let path = socketPath()
        return try await Task.detached { try chatRequest(path, "events", requires: .events, fields: fields, also: (.reasoning, ",\"reasoning\":true")) }.value
    }

    public func resume(_ id: String) async throws {
        let fields = ",\"sessionId\":\"\(try wireId(id))\""
        let path = socketPath()
        let _: AnyReply = try await Task.detached { try chatRequest(path, "resume", requires: .resume, fields: fields) }.value
    }

    /// The text goes on the wire JSON-encoded, so quotes, newlines and anything else in it stay inside the string.
    public func send(_ id: String, _ text: String) async throws { try await send(id, text, command: nil) }

    public func send(_ id: String, _ text: String, command: String?) async throws {
        let fields = ",\"sessionId\":\"\(try wireId(id))\",\"text\":" + jsonString(text) + (command.map { ",\"command\":" + jsonString($0) } ?? "")
        let path = socketPath()
        let _: AnyReply = try await Task.detached { try chatRequest(path, "send", requires: .send, fields: fields) }.value
    }

    public func interrupt(_ id: String) async throws {
        let fields = ",\"sessionId\":\"\(try wireId(id))\""
        let path = socketPath()
        let _: AnyReply = try await Task.detached { try chatRequest(path, "interrupt", requires: .interrupt, fields: fields) }.value
    }

    /// Both ids go on the wire JSON-encoded, as they come from the provider.
    public func answer(_ id: String, approval: String, choice: String) async throws {
        let encoder = JSONEncoder()
        let fields = ",\"sessionId\":\"\(try wireId(id))\",\"approvalId\":" + String(decoding: try encoder.encode(approval), as: UTF8.self)
            + ",\"choiceId\":" + String(decoding: try encoder.encode(choice), as: UTF8.self)
        let path = socketPath()
        let _: AnyReply = try await Task.detached { try chatRequest(path, "answer", requires: .answer, fields: fields) }.value
    }

    public func setOption(_ id: String, option: String, value: String) async throws {
        let encoder = JSONEncoder()
        let fields = ",\"sessionId\":\"\(try wireId(id))\",\"option\":" + String(decoding: try encoder.encode(option), as: UTF8.self)
            + ",\"value\":" + String(decoding: try encoder.encode(value), as: UTF8.self)
        let path = socketPath()
        let _: AnyReply = try await Task.detached { try chatRequest(path, "setOption", requires: .setOption, fields: fields) }.value
    }

    public func archive(_ id: String, _ archived: Bool) async throws {
        let fields = ",\"sessionId\":\"\(try wireId(id))\",\"archived\":\(archived)"
        let path = socketPath()
        let _: AnyReply = try await Task.detached { try chatRequest(path, "archive", requires: .archive, fields: fields) }.value
    }

    public func delete(_ id: String) async throws {
        let fields = ",\"sessionId\":\"\(try wireId(id))\""
        let path = socketPath()
        let _: AnyReply = try await Task.detached { try chatRequest(path, "delete", requires: .delete, fields: fields) }.value
    }

    public func rename(_ id: String, _ title: String) async throws {
        let fields = ",\"sessionId\":\"\(try wireId(id))\",\"title\":" + jsonString(title)
        let path = socketPath()
        let _: AnyReply = try await Task.detached { try chatRequest(path, "rename", requires: .rename, fields: fields) }.value
    }

    private struct TitleReply: Decodable { let title: String }

    public func regenerateTitle(_ id: String) async throws -> String {
        let fields = ",\"sessionId\":\"\(try wireId(id))\""
        let path = socketPath()
        let reply: TitleReply = try await Task.detached { try chatRequest(path, "regenerateTitle", requires: .regenerateTitle, fields: fields) }.value
        return reply.title
    }

    /// The host takes 1 to 500 ids a request, so a longer list goes in several; a commit shared by two worktrees counts for both only when they are asked together.
    public func deletePreview(_ ids: [String]) async throws -> [SessionDeletePreview] {
        let wired = try ids.map(wireId)
        let path = socketPath()
        var previews: [SessionDeletePreview] = []
        for start in stride(from: 0, to: wired.count, by: 500) {
            let list = wired[start..<min(start + 500, wired.count)].map { "\"\($0)\"" }.joined(separator: ",")
            let reply: DeletePreviewReply = try await Task.detached { try chatRequest(path, "deletePreview", requires: .deletePreview, fields: ",\"sessionIds\":[\(list)]") }.value
            previews += reply.sessions
        }
        return previews
    }
}

/// Only a UUID goes on the wire as the session id, as the host accepts nothing else.
private func wireId(_ id: String) throws -> String {
    guard let id = UUID(uuidString: id)?.uuidString.lowercased() else { throw ControlError.remote("not a valid session id") }
    return id
}

/// A string as a JSON literal, so quotes, newlines and anything else in it stay inside the string on the wire.
private func jsonString(_ text: String) -> String { String(decoding: (try? JSONEncoder().encode(text)) ?? Data("\"\"".utf8), as: UTF8.self) }

/// The reply of `open`: only the new session's id is read.
/// Where a plan works: a folder that exists, a repository `owner/name` (the host clones it into its projects folder when the message is sent, or
/// fetches it when it is there already), or a new project of this name (the host makes `<projects folder>/local/<name>` when the message is sent).
public enum PlanWorkspace: Equatable {
    case folder(String)
    case repo(String)
    case project(String)
}

/// What a new session is before it exists (docs/adr/0018): where it works, the agent and the options the person chose (an id and a value each,
/// as `agentOptions` listed them), the first message and the branch to check out, or for a worktree the branch it starts from and its name.
public struct SessionPlan: Equatable {
    public let agent: String
    public let workspace: PlanWorkspace
    /// The branch to check out in the folder, when the person picked one other than the checked-out one and asked for no worktree.
    public let branch: String?
    public let worktree: WorktreeRequest?
    public let options: [String: String]
    public let text: String

    /// The folder of a plan for a folder; nil for a repository or a new project.
    public var folder: String? {
        if case .folder(let path) = workspace { return path }
        return nil
    }

    public init(agent: String, folder: String, branch: String? = nil, worktree: WorktreeRequest? = nil, options: [String: String] = [:], text: String) {
        self.init(agent: agent, workspace: .folder(folder), branch: branch, worktree: worktree, options: options, text: text)
    }

    public init(agent: String, workspace: PlanWorkspace, branch: String? = nil, worktree: WorktreeRequest? = nil, options: [String: String] = [:], text: String) {
        self.agent = agent
        self.workspace = workspace
        self.branch = branch
        self.worktree = worktree
        self.options = options
        self.text = text
    }

    /// The plan as the host's request takes it; every string goes on the wire JSON-encoded.
    var wire: String {
        let place = switch workspace {
        case .folder(let path): "{\"kind\":\"folder\",\"folder\":\(jsonString(path))}"
        case .repo(let name): "{\"kind\":\"repo\",\"repo\":\(jsonString(name))}"
        case .project(let name): "{\"kind\":\"project\",\"name\":\(jsonString(name))}"
        }
        var fields = [
            "\"workspace\":\(place)", "\"agent\":\(jsonString(agent))", "\"text\":\(jsonString(text))",
        ]
        if options.isEmpty == false { fields.append("\"options\":{" + options.sorted { $0.key < $1.key }.map { "\(jsonString($0.key)):\(jsonString($0.value))" }.joined(separator: ",") + "}") }
        // a worktree is cut from the branch, so the one field serves both
        if let branch = worktree?.from ?? branch { fields.append("\"branch\":\(jsonString(branch))") }
        if let worktree { fields.append("\"worktree\":{" + (worktree.name.map { "\"name\":\(jsonString($0))" } ?? "") + "}") }
        return "{" + fields.joined(separator: ",") + "}"
    }
}

/// What an agent offers before a session exists.
public struct AgentOffer: Decodable, Equatable {
    public let options: [ChatOption]
    public let commands: [ChatCommand]

    public init(options: [ChatOption] = [], commands: [ChatCommand] = []) {
        self.options = options
        self.commands = commands
    }

    private enum CodingKeys: String, CodingKey { case options, commands }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        options = try values.decodeIfPresent([ChatOption].self, forKey: .options) ?? []
        commands = try values.decodeIfPresent([ChatCommand].self, forKey: .commands) ?? []
    }
}

/// The reply of `open`: only the new session's id is read.
private struct OpenedReply: Decodable {
    struct Session: Decodable { let id: String }
    let session: Session
}

/// The reply of `cancelPreparation`: the plan as the host stored it.
private struct CancelledReply: Decodable {
    struct Stored: Decodable {
        struct Workspace: Decodable {
            let kind: String
            let folder: String?
            let repo: String?
            let name: String?
        }
        struct Worktree: Decodable { let name: String? }
        let workspace: Workspace
        let agent: String
        let text: String
        let options: [String: String]?
        let branch: String?
        let worktree: Worktree?

        /// A worktree is cut from the branch, so the one field serves both, as the plan's wire has it.
        var plan: SessionPlan {
            get throws {
                let place: PlanWorkspace
                switch (workspace.kind, workspace.folder, workspace.repo, workspace.name) {
                case ("folder", let folder?, _, _): place = .folder(folder)
                case ("repo", _, let repo?, _): place = .repo(repo)
                case ("project", _, _, let name?): place = .project(name)
                default: throw ControlError.badLine
                }
                let cut = worktree.flatMap { wanted in branch.map { WorktreeRequest(from: $0, name: wanted.name) } }
                return SessionPlan(agent: agent, workspace: place, branch: worktree == nil ? branch : nil, worktree: cut, options: options ?? [:], text: text)
            }
        }
    }
    let plan: Stored
}

private struct SuggestedName: Decodable { let name: String }

/// A reply whose content the app does not read: any JSON will do.
private struct AnyReply: Decodable { init(from decoder: Decoder) throws {} }

private struct DeletePreviewReply: Decodable { let sessions: [SessionDeletePreview] }

private struct ChatSessionsReply: Decodable { let sessions: [ChatSession] }

/// The connection of a request that can be cancelled from another thread, for as long as the request lasts.
private final class Abortable: @unchecked Sendable {
    private let lock = NSLock()
    private var client: ControlClient?
    private var aborted = false

    func attach(_ client: ControlClient) {
        lock.lock()
        defer { lock.unlock() }
        self.client = client
        if aborted { client.abort() }
    }

    func detach() {
        lock.lock()
        defer { lock.unlock() }
        client = nil
    }

    func abort() {
        lock.lock()
        defer { lock.unlock() }
        aborted = true
        client?.abort()
    }
}

/// Connects, reads the hello, makes one request the host said it can answer and decodes its reply.
fileprivate func chatRequest<Reply: Decodable>(
    _ path: String, _ command: String, requires capability: ControlClient.Capability, fields: String = "", also: (capability: ControlClient.Capability, fields: String)? = nil,
    timeout: TimeInterval = 5, abortable: Abortable? = nil
) throws -> Reply {
    guard let client = ControlClient.connect(path: path, timeout: timeout) else { throw ControlError.closed }
    abortable?.attach(client)
    defer {
        abortable?.detach()
        client.close()
    }
    _ = try client.supportedHello()
    // fields only a host that lists their capability understands: an older one is not sent them
    let sent = fields + (also.flatMap { client.capabilities.contains($0.capability) ? $0.fields : nil } ?? "")
    guard let data = try client.request(command, requires: capability, fields: sent) else {
        throw ControlError.remote("the chat host does not support \(command)")
    }
    do { return try JSONDecoder().decode(Reply.self, from: data) } catch { throw ControlError.badLine }
}

public let hostNotRunning = "The chat host is not running"
