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
    public enum State: String, Decodable { case working, waitingApproval = "waiting_approval", idle }

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

    public struct Workspace: Decodable, Equatable {
        public let base: String
        public let branch: String?
    }

    private enum CodingKeys: String, CodingKey { case id, agent, harness, folder, title, state, createdAt, lastActiveAt, archived, workspace, live }
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

/// What the app needs from the chat host's socket; the real one speaks to the socket, tests use a fake.
public protocol ChatHost {
    func agents() async throws -> [ChatAgent]
    func list(archived: Bool) async throws -> [ChatSession]
    /// Creates a session with the agent in the folder (the agent's configured `options` apply on the host's side) and returns its id;
    /// with a `worktree` it works in a new worktree of the folder instead. The host refuses a folder inside Carrier's own folders, a
    /// provider that is not logged in, and a worktree request for a folder that is not a git repository, a branch it did not list
    /// and a name that is invalid or taken.
    func open(agent: String, folder: String, worktree: WorktreeRequest?) async throws -> String
    /// `open` with the options the person chose before the session existed (an id and a value each, as `agentOptions` listed them); the host
    /// refuses a value the provider does not list.
    func open(agent: String, folder: String, worktree: WorktreeRequest?, options: [String: String]) async throws -> String
    /// What an agent offers, with the values it would start with, before a session exists; the host starts the agent to know, and keeps the answer.
    func agentOptions(_ agent: String) async throws -> [ChatOption]
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
    /// The events of a session after the cursor, at most `limit` (the host takes 1 to 200).
    func events(_ id: String, after: Int, limit: Int) async throws -> ChatEvents
    /// Opens a closed session's agent again; the host refuses a `send` to one that is not live.
    func resume(_ id: String) async throws
    /// The host refuses it while the agent is answering ("The agent is still answering") and when it is over its character limit.
    func send(_ id: String, _ text: String) async throws
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
    /// What deleting these sessions would discard, one entry per id in the order asked; the host refuses the whole request when an id is unknown.
    func deletePreview(_ ids: [String]) async throws -> [SessionDeletePreview]
}

extension ChatHost {
    /// A host that knows nothing of options at open: the options are left out.
    public func open(agent: String, folder: String, worktree: WorktreeRequest?, options: [String: String]) async throws -> String {
        try await open(agent: agent, folder: folder, worktree: worktree)
    }

    /// A host that cannot list an agent's options before a session says it lists none.
    public func agentOptions(_ agent: String) async throws -> [ChatOption] { [] }
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

    public func open(agent: String, folder: String, worktree: WorktreeRequest?) async throws -> String {
        try await open(agent: agent, folder: folder, worktree: worktree, options: [:])
    }

    public func open(agent: String, folder: String, worktree: WorktreeRequest?, options: [String: String]) async throws -> String {
        let placed = worktree.map { request in
            ",\"worktree\":{\"from\":\(jsonString(request.from))" + (request.name.map { ",\"name\":\(jsonString($0))" } ?? "") + "}"
        } ?? ""
        let chosen = options.isEmpty ? "" : ",\"options\":{" + options.sorted { $0.key < $1.key }.map { "\(jsonString($0.key)):\(jsonString($0.value))" }.joined(separator: ",") + "}"
        let fields = ",\"agent\":\(jsonString(agent)),\"folder\":\(jsonString(folder))" + placed + chosen
        let path = socketPath()
        let reply: OpenedReply = try await Task.detached { try chatRequest(path, "open", requires: .open, fields: fields) }.value
        return reply.session.id
    }

    public func agentOptions(_ agent: String) async throws -> [ChatOption] {
        let fields = ",\"agent\":\(jsonString(agent))"
        let path = socketPath()
        // starting the agent to read its options takes a few seconds
        let reply: OptionsReply = try await Task.detached { try chatRequest(path, "agentOptions", requires: .agentOptions, fields: fields, timeout: 30) }.value
        return reply.options
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
            guard try client.hello().protocolVersion == 1 else { throw ControlError.remote("incompatible chat host") }
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

    public func events(_ id: String, after: Int, limit: Int) async throws -> ChatEvents {
        let fields = ",\"sessionId\":\"\(try wireId(id))\",\"after\":\(after),\"limit\":\(limit)"
        let path = socketPath()
        return try await Task.detached { try chatRequest(path, "events", requires: .events, fields: fields) }.value
    }

    public func resume(_ id: String) async throws {
        let fields = ",\"sessionId\":\"\(try wireId(id))\""
        let path = socketPath()
        let _: AnyReply = try await Task.detached { try chatRequest(path, "resume", requires: .resume, fields: fields) }.value
    }

    /// The text goes on the wire JSON-encoded, so quotes, newlines and anything else in it stay inside the string.
    public func send(_ id: String, _ text: String) async throws {
        let fields = ",\"sessionId\":\"\(try wireId(id))\",\"text\":" + jsonString(text)
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
private struct OptionsReply: Decodable { let options: [ChatOption] }

private struct OpenedReply: Decodable {
    struct Session: Decodable { let id: String }
    let session: Session
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
    _ path: String, _ command: String, requires capability: ControlClient.Capability, fields: String = "", timeout: TimeInterval = 5, abortable: Abortable? = nil
) throws -> Reply {
    guard let client = ControlClient.connect(path: path, timeout: timeout) else { throw ControlError.closed }
    abortable?.attach(client)
    defer {
        abortable?.detach()
        client.close()
    }
    guard try client.hello().protocolVersion == 1 else { throw ControlError.remote("incompatible chat host") }
    guard let data = try client.request(command, requires: capability, fields: fields) else {
        throw ControlError.remote("the chat host does not support \(command)")
    }
    do { return try JSONDecoder().decode(Reply.self, from: data) } catch { throw ControlError.badLine }
}

public let hostNotRunning = "The chat host is not running"
