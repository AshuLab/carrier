import Foundation

// The app's side of the chat host's socket (docs/specs/chat-host.md, sessions-in-the-app.md): the requests it needs so far,
// a monitor that says whether the host answers, and the rule for the Sessions + flag. The slices that use more requests add them to `ChatHost`.

public struct ChatAgent: Decodable, Equatable {
    public let name: String
    public let harness: String
    public let model: String?
    /// Whether the agent's binary was found on the host's machine.
    public let found: Bool
    /// The account of `providers.json` the agent runs on, which has its icon, color and label; nil from a host that does not say (the agent's
    /// name is the account's then, as the host names them when `chat.json` lists no agents).
    public let account: String?

    public init(name: String, harness: String, model: String? = nil, found: Bool, account: String? = nil) {
        self.name = name
        self.harness = harness
        self.model = model
        self.found = found
        self.account = account
    }
}

/// The account behind each chat agent, as the host last said (`SocketChatHost.agents`): the app looks an agent's icon, color and label up by it.
/// An agent not here is named as its account, as the host names them when `chat.json` lists no agents. It also keeps each agent's harness,
/// which is what its tool's mark is looked up by: an account named by the person has the name they gave, not the tool's.
public enum AgentAccounts {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var known: [String: String] = [:]
    nonisolated(unsafe) private static var harnesses: [String: String] = [:]

    static func remember(_ agents: [ChatAgent]) {
        let pairs = agents.compactMap { agent in agent.account.map { (agent.name, $0) } }
        lock.lock()
        defer { lock.unlock() }
        known = Dictionary(pairs, uniquingKeysWith: { first, _ in first })
        harnesses = Dictionary(agents.map { ($0.name, $0.harness) }, uniquingKeysWith: { first, _ in first })
    }

    /// The harness an agent runs on (`claude`, `codex`…), which its tool's mark is looked up by; an agent not known is its own name, as it was.
    public static func harness(of agent: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        return harnesses[agent] ?? agent
    }

    public static func account(of agent: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        return known[agent] ?? agent
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
    /// Whether the host said anything of how the session went: an older one does not, and then no message is not "no reply yet".
    public let reportsActivity: Bool
    /// The lines it changed and its pull request: nil from a host that does not say, while none is known, or for a value this app does not know.
    public let diff: SessionDiff?
    public let pullRequest: SessionPullRequest?
    /// What the agent waits for after its turn ended; empty from a host that does not say.
    public let background: [BackgroundTask]
    /// The session that started this one by delegating, for a child session; nil for any other, and from a host that does not say.
    public let parentSessionId: String?
    /// The child sessions this one started, oldest first; empty from a host that does not say. The list of sessions leaves the children themselves out.
    public let children: [Child]

    /// A child session as its parent lists it. `level` is the permission level it runs at (0 reads only, 1 asks before each change, 2 edits without asking), nil when the host does not say.
    public struct Child: Decodable, Equatable {
        public let id: String
        public let agent: String
        public let harness: String
        public let state: State
        public let level: Int?
        /// True while the child waits for an approval or a question.
        public let needsPerson: Bool
    }

    public struct Workspace: Decodable, Equatable {
        public let base: String
        public let branch: String?
    }

    private enum CodingKeys: String, CodingKey { case id, agent, harness, folder, title, state, createdAt, lastActiveAt, archived, workspace, live, preparation, kept, deleteAt, lastMessage, turns, model, parentSessionId, children, diff, pr, background }
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
        reportsActivity = values.contains(.turns)
        model = try values.decodeIfPresent(String.self, forKey: .model)
        // a shape this app does not know is no data, never a list it cannot read
        diff = (try? values.decodeIfPresent(SessionDiff.self, forKey: .diff)) ?? nil
        pullRequest = (try? values.decodeIfPresent(SessionPullRequest.self, forKey: .pr)) ?? nil
        background = (try? values.decodeIfPresent([BackgroundTask].self, forKey: .background)) ?? []
        parentSessionId = try values.decodeIfPresent(String.self, forKey: .parentSessionId)
        children = try values.decodeIfPresent([Child].self, forKey: .children) ?? []
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

/// A clone the person started from Settings, as the host lists it: running with git's latest progress line, or failed with its reason until it is dismissed.
/// One that finished is a project in `projects.json` and is no longer listed.
public struct ProjectClone: Decodable, Equatable, Identifiable, Sendable {
    public enum State: String, Decodable, Sendable { case cloning, failed }

    /// `owner/name`.
    public let repo: String
    /// Where it is being made.
    public let folder: String
    public let state: State
    /// Git's latest progress line ("Receiving objects: 45%"), once it has said one.
    public let progress: String?
    /// Why a failed clone failed, in the host's words.
    public let error: String?

    public var id: String { repo.lowercased() }

    public init(repo: String, folder: String, state: State, progress: String? = nil, error: String? = nil) {
        self.repo = repo
        self.folder = folder
        self.state = state
        self.progress = progress
        self.error = error
    }
}

struct ProjectClonesReply: Decodable { let clones: [ProjectClone] }
struct NewProjectReply: Decodable { let folder: String }

/// What a person is told when the chat host that is running is older than the app and has no projects requests: the app replaces an older host when
/// no session is working, so the way out is to finish the work and restart the host.
public let projectsNeedNewerHost = "The chat host that is running is older than this app and cannot manage projects. Restart the chat host (when no session is working) to use it."

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
    /// The sessions as the host reports them, one update at each read and the last one at once: the active list, the archived one, and whether
    /// the host answered (`SessionsUpdate`). The reads are shared by everyone who asks and end with the task that iterates.
    func sessionUpdates() async -> AsyncStream<SessionsUpdate>
    /// Creates a session from the plan, in one request that carries the first message, and returns its id at once: the host prepares it in
    /// the background (the `step` events of its conversation say how far). Only for a host whose hello lists `plan`. The host refuses a
    /// folder inside Carrier's own folders, a provider that is not logged in, and a message over its limit.
    func open(plan: SessionPlan) async throws -> String
    /// Repeats the steps of a failed preparation that did not finish (what was made is reused); refused in words for a session that is not in
    /// a failed preparation. Only for a host whose hello lists `plan`.
    func retryPreparation(_ id: String) async throws
    /// Stops the running step and deletes the session with its worktree; answers the plan it was opened with, for the draft to take back.
    /// Refused in words for a session that is not being prepared. Nil when the session stays (a worktree coming back: only its running action stops).
    /// Only for a host whose hello lists `plan`.
    func cancelPreparation(_ id: String) async throws -> SessionPlan?
    /// What an agent offers (its options with the values it would start with, and the commands to invoke) before a session exists; the host
    /// starts the agent to know, and keeps the answer.
    func agentOptions(_ agent: String) async throws -> AgentOffer
    /// What a folder is as a git repository (`WorkspaceInfo.git` is false for a plain folder); refused for a folder the host will not open.
    func workspace(_ folder: String) async throws -> WorkspaceInfo
    /// Fetches the folder's `origin` and answers what the folder is after it; a fetch that fails or takes too long is refused in words.
    /// With `ifStale` a host that lists `fetchIfStale` skips the git call when the last fetch is within its window and answers all the same;
    /// a host that does not is never sent it.
    func fetch(_ folder: String, ifStale: Bool) async throws -> WorkspaceInfo
    /// A free generated name for a worktree of the folder: the part after `carrier/`.
    func suggestName(_ folder: String) async throws -> String
    /// Whether a typed name (the part after `carrier/`) is valid and free, and why not.
    func checkName(_ folder: String, _ name: String) async throws -> NameCheck
    /// The optional requests this host answers, from its hello.
    func capabilities() async throws -> Set<ControlClient.Capability>
    /// One page (1 to 100) of the repositories the person's `gh` login can read, thirty at a time, newest push first. Refused in words
    /// (`gh` missing or signed out, no network, too slow). Gh can take seconds.
    func githubRepos(page: Int) async throws -> GithubReposPage
    /// The default branch and the branches of `owner/repo`, read from GitHub with the person's `gh` login: the repository need not be on this
    /// Mac. Refused in words (`gh` missing or signed out, no network, not found or not visible, too slow). Only for a host whose hello lists `repoBranches`.
    func repoBranches(_ repo: String) async throws -> RepoBranches
    /// Starts cloning `repo` (`owner/name`) into `parent/<owner>/<name>`, or into the projects folder when `parent` is nil, and answers at once with the clone
    /// (`cloning`): the host registers the folder as a project, with origin `cloned`, when git ends, and never makes Carrier watch it. One running for the same
    /// repository is shared, not started twice. Refused in words for a folder that is already a project or a parent inside Carrier's own folders. Only for a host
    /// whose hello lists `projects`; an older one is told to restart.
    func cloneProject(_ repo: String, into parent: String?) async throws -> ProjectClone
    /// The clones started from Settings that are running or failed. Only for a host whose hello lists `projects`.
    func projectClones() async throws -> [ProjectClone]
    /// The worktrees of the project at `folder`: its main clone and each worktree git lists for it under Carrier's worktrees folder that is still on disk, with
    /// branch, session, age and state. Refused in words for a folder that is gone or not a repository. Only for a host whose hello lists `projects`.
    func projectWorktrees(_ folder: String) async throws -> ProjectWorktrees
    /// What each project folder takes on disk as the host last measured it (nil bytes: never), and which of them it has queued or is measuring; `refresh` says what it
    /// measures meanwhile. A folder that is gone or not allowed is left out of the answer. Only for a host whose hello lists `projects`.
    func projectDisk(_ folders: [String], refresh: ProjectDiskRefresh) async throws -> ProjectDiskReply
    /// Removes only the folder of one worktree of the project at `folder`, keeping its branch and its session; refused in words while its session is open or it has
    /// uncommitted changes. Only for a host whose hello lists `projects`.
    func removeProjectWorktree(_ folder: String, path: String) async throws
    /// What Clean up would remove from the project at `folder` (its merged worktrees nothing blocks, with the bytes each folder holds) and skip (with the reason);
    /// with `run` it removes them and answers what it removed and skipped. Only for a host whose hello lists `projects`.
    func cleanProjectWorktrees(_ folder: String, run: Bool) async throws -> ProjectCleanup
    /// Forgets a failed clone (one that is running stays) and answers the clones that are left. Only for a host whose hello lists `projects`.
    func dismissClone(_ repo: String) async throws -> [ProjectClone]
    /// Makes `<parent>/local/<name>` (the projects folder when `parent` is nil) with `git init` and registers it in `projects.json` with origin `created`; answers its
    /// folder. Refused in words for a name that is not a plain folder name, a folder that is already there or a parent inside Carrier's own folders, and nothing is
    /// written then. Only for a host whose hello lists `projects`; an older one is told to restart.
    func newProject(_ name: String, into parent: String?) async throws -> String
    /// The state of `git`, `gh` and each chat agent on the host's machine; `refresh` skips the answer the host kept for thirty seconds.
    /// Only for a host whose hello lists `health`.
    func health(refresh: Bool) async throws -> HostHealth
    /// The accounts of `providers.json` with their state, the harnesses found with no account and the local servers with their models; a file
    /// that does not match answers `problem`. Only for a host whose hello lists `providers`.
    func providers() async throws -> HostProviders
    /// Live quotas per account and what was used, filtered as asked. Only for a host whose hello lists `usage`; the host reads the machine's
    /// CLIs and logs, so it can take seconds.
    func usage(_ query: UsageQuery) async throws -> UsageSnapshot
    /// Sets or clears the price of a model for the cost in `usage`; refused in words for a rate the host cannot use. Only for a host whose
    /// hello lists `usageOverride`.
    func usageOverride(_ override: UsageOverride) async throws
    /// The events of a session after the cursor, at most `limit` (the host takes 1 to 200).
    func events(_ id: String, after: Int, limit: Int) async throws -> ChatEvents
    /// Opens a closed session's agent again; the host refuses a `send` to one that is not live.
    func resume(_ id: String) async throws
    /// Switches an idle session to another configured agent: it keeps its transcript and folder, and its new agent goes on with a handoff of what was said.
    /// Refused in words, with the session as it was, for a session that is working, waiting for an approval, preparing, archived or a child, for the agent it
    /// already has, an agent that is not configured, not found or signed out, a model the harness does not list, and a conversation that cannot open.
    /// Only for a host whose hello lists `switchAgent`; the message box's panel asks for it (`ConversationModel.switchAgent`).
    func switchAgent(_ id: String, to agent: String) async throws -> AgentSwitch
    /// The host refuses it while the agent is answering ("The agent is still answering") and when it is over its character limit.
    func send(_ id: String, _ text: String) async throws
    /// `send` that invokes a command the session listed: `text` is what follows its name (nothing is allowed), and the host shows it as the
    /// slash and the name and tells the provider in the provider's own way.
    func send(_ id: String, _ text: String, command: String?) async throws
    /// Ends the turn that is in progress; with none running, it stops what the agent waits for in the background.
    func interrupt(_ id: String) async throws
    /// Stops one running subagent, by the `taskId` of its `task` events, or one of the tasks the agent waits for in the background (`BackgroundTask.id`), and not the turn;
    /// the subagent ends when its `stopped` event arrives, not when this returns. The host refuses a task that is not running in that session.
    /// Only for a host whose hello lists `stopTask`: `capabilities()` says it.
    func stopTask(_ id: String, task: String) async throws
    /// Passes the person's choice for a pending approval to the agent; the host refuses one that is not pending and a choice the provider did not list.
    func answer(_ id: String, approval: String, choice: String, answers: [String: String]?) async throws

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
    /// Starts writing titles in the background for earlier sessions whose title is still their first line and answers how many it started. Only for a host whose hello lists `regenerateTitles`.
    func regenerateTitles() async throws -> Int
    /// What deleting these sessions would discard, one entry per id in the order asked; the host refuses the whole request when an id is unknown.
    func deletePreview(_ ids: [String]) async throws -> [SessionDeletePreview]
}

extension ChatHost {
    /// A host that is not the socket's reads `list` by itself, at the pace of `PollPace`, by the same rules as the link's.
    public func sessionUpdates() async -> AsyncStream<SessionsUpdate> {
        let reader = SessionsReader()
        let (stream, continuation) = AsyncStream.makeStream(of: SessionsUpdate.self, bufferingPolicy: .bufferingNewest(1))
        let task = Task {
            var failures = 0
            while Task.isCancelled == false {
                let (update, _) = await reader.read { try await self.list(archived: $0) }
                continuation.yield(update)
                failures = update.stale ? failures + 1 : 0
                try? await Task.sleep(for: .seconds(sessionsPollWait(pace: PollPace.shared.seconds, failures: failures, looking: PollPace.shared.looking)))
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    /// An answer that is only a choice, the one every approval but a question has.
    public func answer(_ id: String, approval: String, choice: String) async throws {
        try await answer(id, approval: approval, choice: choice, answers: nil)
    }

    /// A host that cannot stop a subagent refuses; the app only asks one that lists `stopTask`.
    public func stopTask(_ id: String, task: String) async throws { throw ControlError.remote("the chat host does not support stopTask") }

    /// A host that cannot prepare a session from a plan has nothing to try again.
    public func retryPreparation(_ id: String) async throws { throw ControlError.remote("the chat host does not support retryPreparation") }

    /// A host that cannot prepare a session from a plan has nothing to cancel.
    public func cancelPreparation(_ id: String) async throws -> SessionPlan? { throw ControlError.remote("the chat host does not support cancelPreparation") }

    /// A host that cannot list an agent's options before a session says it lists none.
    public func agentOptions(_ agent: String) async throws -> AgentOffer { AgentOffer() }

    /// A host that cannot list the branches of a repository refuses; the app only asks one that lists `repoBranches`.
    public func repoBranches(_ repo: String) async throws -> RepoBranches { throw ControlError.remote("the chat host does not support repoBranches") }

    /// A host that has no projects requests says it is older and to restart it.
    public func cloneProject(_ repo: String, into parent: String?) async throws -> ProjectClone { throw ControlError.remote(projectsNeedNewerHost) }
    public func projectClones() async throws -> [ProjectClone] { throw ControlError.remote(projectsNeedNewerHost) }
    public func projectWorktrees(_ folder: String) async throws -> ProjectWorktrees { throw ControlError.remote(projectsNeedNewerHost) }
    public func projectDisk(_ folders: [String], refresh: ProjectDiskRefresh) async throws -> ProjectDiskReply { throw ControlError.remote(projectsNeedNewerHost) }
    public func removeProjectWorktree(_ folder: String, path: String) async throws { throw ControlError.remote(projectsNeedNewerHost) }
    public func cleanProjectWorktrees(_ folder: String, run: Bool) async throws -> ProjectCleanup { throw ControlError.remote(projectsNeedNewerHost) }
    public func dismissClone(_ repo: String) async throws -> [ProjectClone] { throw ControlError.remote(projectsNeedNewerHost) }
    public func newProject(_ name: String, into parent: String?) async throws -> String { throw ControlError.remote(projectsNeedNewerHost) }

    /// A host that cannot say how the machine is refuses; the app only asks one that lists `health`.
    public func health(refresh: Bool) async throws -> HostHealth { throw ControlError.remote("the chat host does not support health") }

    /// A host that cannot list the AI tools refuses; the app only asks one that lists `providers`.
    public func providers() async throws -> HostProviders { throw ControlError.remote("the chat host does not support providers") }

    /// A host that cannot say what was used refuses; the app only asks one that lists `usage`.
    public func usage(_ query: UsageQuery) async throws -> UsageSnapshot { throw ControlError.remote(usageNeedsNewerHost) }

    /// A host that cannot price refuses; the app only asks one that lists `usageOverride`.
    public func usageOverride(_ override: UsageOverride) async throws { throw ControlError.remote(usageNeedsNewerHost) }

    /// A host that cannot switch agents refuses; the app only asks one that lists `switchAgent`.
    public func switchAgent(_ id: String, to agent: String) async throws -> AgentSwitch { throw ControlError.remote("the chat host does not support switchAgent") }

    /// A host that cannot rename refuses; the app only asks one that lists `rename`.
    public func rename(_ id: String, _ title: String) async throws { throw ControlError.remote("the chat host does not support rename") }

    /// A host that cannot write titles refuses; the app only asks one that lists `regenerateTitle`.
    public func regenerateTitle(_ id: String) async throws -> String { throw ControlError.remote("the chat host does not support regenerateTitle") }

    /// A host that cannot write earlier titles refuses; the app only asks one that lists `regenerateTitles`.
    public func regenerateTitles() async throws -> Int { throw ControlError.remote("the chat host does not support regenerateTitles") }

    /// A host that knows no commands sends the text as it is.
    public func send(_ id: String, _ text: String, command: String?) async throws { try await send(id, text) }
}

/// The chat host over its socket, with the blocking socket work off the caller's thread. What the app reads over and over (`list`, `events`, the
/// hello's capabilities and the updates of the sessions) goes through the one connection `ChatLink` keeps for the socket; everything else is an
/// action, one connection per call. A host that is not there, or goes away mid-call, is `ControlError.closed`; an error reply is `.remote`.
public struct SocketChatHost: ChatHost {
    private let socketPath: () -> String
    /// What each session's options and commands were when the host last sent them, so the host can leave them out of the next answers.
    private let lists = ListsMemory()

    public init(socketPath: @escaping () -> String = { chatSocketPath() }) { self.socketPath = socketPath }

    public func agents() async throws -> [ChatAgent] {
        let path = socketPath()
        let agents: [ChatAgent] = try await Task.detached { try chatRequest(path, "agents", requires: .agents) }.value
        AgentAccounts.remember(agents)
        return agents
    }

    public func list(archived: Bool) async throws -> [ChatSession] { try await link.list(archived: archived) }

    public func sessionUpdates() async -> AsyncStream<SessionsUpdate> { await link.sessions() }

    /// Reads the list now and not at the end of the wait; with `archived`, the archived list too (after an archive, a restore or a delete).
    public func refreshSessions(archived: Bool) { link.refresh(archived: archived) }

    private var link: ChatLink { ChatLink.link(for: socketPath()) }

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
    public func cancelPreparation(_ id: String) async throws -> SessionPlan? {
        let fields = ",\"sessionId\":\"\(try wireId(id))\""
        let path = socketPath()
        let reply: CancelledReply = try await Task.detached { try chatRequest(path, "cancelPreparation", requires: .plan, fields: fields, timeout: 30) }.value
        return try reply.plan?.plan
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

    public func fetch(_ folder: String, ifStale: Bool) async throws -> WorkspaceInfo {
        let fields = ",\"folder\":\(jsonString(folder))"
        let path = socketPath()
        // the host gives a fetch 60 seconds, so the wait is longer than that
        return try await Task.detached {
            try chatRequest(path, "fetch", requires: .fetch, fields: fields, also: ifStale ? [(.fetchIfStale, ",\"ifStale\":true")] : [], timeout: 70)
        }.value
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

    /// From the hello of the connection the link keeps, which was read once.
    public func capabilities() async throws -> Set<ControlClient.Capability> { try await link.capabilities() }

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

    public func cloneProject(_ repo: String, into parent: String?) async throws -> ProjectClone {
        // the host's own limits (src/chat/server.ts): a repository as owner/name, and a parent that is not empty or over 4096 characters
        guard isRepoName(repo) else { throw ControlError.remote("\"\(repo)\" is not a repository; write it as owner/name") }
        if let parent, parent.isEmpty || parent.count > 4096 { throw ControlError.remote("That folder cannot be used") }
        let fields = ",\"repo\":\(jsonString(repo))" + (parent.map { ",\"parent\":\(jsonString($0))" } ?? "")
        let path = socketPath()
        return try await Task.detached { try projectsRequest(path, "cloneProject", fields: fields) }.value
    }

    public func projectClones() async throws -> [ProjectClone] {
        let path = socketPath()
        return try await Task.detached { (try projectsRequest(path, "projectClones") as ProjectClonesReply).clones }.value
    }

    public func projectWorktrees(_ folder: String) async throws -> ProjectWorktrees {
        // the host's own limit (src/chat/server.ts): a folder that is not empty or over 4096 characters
        if folder.isEmpty || folder.count > 4096 { throw ControlError.remote("That folder cannot be used") }
        let fields = ",\"folder\":\(jsonString(folder))"
        let path = socketPath()
        return try await Task.detached { try projectsRequest(path, "projectWorktrees", fields: fields) }.value
    }

    public func projectDisk(_ folders: [String], refresh: ProjectDiskRefresh) async throws -> ProjectDiskReply {
        // the host's own limits (src/chat/server.ts): 1 to 500 folders, none empty or over 4096 characters; what it would refuse never goes out
        let asked = folders.filter { $0.isEmpty == false && $0.count <= 4096 }.prefix(500)
        if asked.isEmpty { return ProjectDiskReply(projects: []) }
        let fields = ",\"folders\":[" + asked.map(jsonString).joined(separator: ",") + "]" + (refresh == .read ? "" : ",\"refresh\":\"\(refresh.rawValue)\"")
        let path = socketPath()
        return try await Task.detached { try projectsRequest(path, "projectDisk", fields: fields) }.value
    }

    public func removeProjectWorktree(_ folder: String, path worktree: String) async throws {
        // the host's own limits (src/chat/server.ts): neither empty nor over 4096 characters
        if folder.isEmpty || folder.count > 4096 || worktree.isEmpty || worktree.count > 4096 { throw ControlError.remote("That folder cannot be used") }
        let fields = ",\"folder\":\(jsonString(folder)),\"path\":\(jsonString(worktree))"
        let path = socketPath()
        // git removes the folder with what it ignores (dependencies, builds), which can take a while
        let _: AnyReply = try await Task.detached { try projectsRequest(path, "removeProjectWorktree", fields: fields, timeout: 120) }.value
    }

    public func cleanProjectWorktrees(_ folder: String, run: Bool) async throws -> ProjectCleanup {
        if folder.isEmpty || folder.count > 4096 { throw ControlError.remote("That folder cannot be used") }
        let fields = ",\"folder\":\(jsonString(folder))" + (run ? ",\"run\":true" : "")
        let path = socketPath()
        // the host measures each folder before it answers, and removing them one by one takes as long as each takes
        return try await Task.detached { try projectsRequest(path, "cleanProjectWorktrees", fields: fields, timeout: run ? 600 : 120) }.value
    }

    public func dismissClone(_ repo: String) async throws -> [ProjectClone] {
        let fields = ",\"repo\":\(jsonString(repo))"
        let path = socketPath()
        return try await Task.detached { (try projectsRequest(path, "dismissClone", fields: fields) as ProjectClonesReply).clones }.value
    }

    public func newProject(_ name: String, into parent: String?) async throws -> String {
        // the host's own limits (src/chat/server.ts): a plain folder name, and a parent that is not empty or over 4096 characters
        if let refusal = projectNameProblem(name) { throw ControlError.remote(refusal) }
        if let parent, parent.isEmpty || parent.count > 4096 { throw ControlError.remote("That folder cannot be used") }
        let fields = ",\"name\":\(jsonString(name))" + (parent.map { ",\"parent\":\(jsonString($0))" } ?? "")
        let path = socketPath()
        return try await Task.detached { (try projectsRequest(path, "newProject", fields: fields) as NewProjectReply).folder }.value
    }

    /// The probes of a request run in parallel with five seconds each, so the wait is longer than the 5 seconds of the other requests.
    public func health(refresh: Bool) async throws -> HostHealth {
        let fields = refresh ? ",\"refresh\":true" : ""
        let path = socketPath()
        return try await Task.detached { try chatRequest(path, "health", requires: .health, fields: fields, timeout: 15) }.value
    }

    /// Each account's probe has its own seconds (Claude's takes about five), run in parallel, and the logs are read after them.
    public func usage(_ query: UsageQuery) async throws -> UsageSnapshot {
        let fields = query.wire
        let path = socketPath()
        return try await Task.detached { try usageRequest(path, "usage", requires: .usage, fields: fields, timeout: 45) }.value
    }

    public func usageOverride(_ override: UsageOverride) async throws {
        let fields = override.wire
        let path = socketPath()
        let _: AnyReply = try await Task.detached { try usageRequest(path, "usageOverride", requires: .usageOverride, fields: fields) }.value
    }

    /// Every probe of the host has its five seconds, in parallel, and a version is read after them, so the wait is longer than the 5 of the other requests.
    public func providers() async throws -> HostProviders {
        let path = socketPath()
        return try await Task.detached { try chatRequest(path, "providers", requires: .providers, timeout: 20) }.value
    }

    public func events(_ id: String, after: Int, limit: Int) async throws -> ChatEvents {
        let fields = ",\"sessionId\":\"\(try wireId(id))\",\"after\":\(after),\"limit\":\(limit)"
        let kept = lists.kept(id)
        let known = kept.map { ",\"lists\":\"\($0.rev)\"" } ?? ""
        let reply: ChatEvents = try await link.read("events", requires: .events, fields: fields, also: [(.reasoning, ",\"reasoning\":true"), (.listsRev, known)])
        return lists.filled(reply, for: id, kept: kept)
    }

    public func resume(_ id: String) async throws {
        let fields = ",\"sessionId\":\"\(try wireId(id))\""
        let path = socketPath()
        // resuming starts the agent again and reads its whole history: a long session takes far more than the 5 seconds of a request that only asks
        let _: AnyReply = try await Task.detached { try chatRequest(path, "resume", requires: .resume, fields: fields, timeout: 60) }.value
    }

    public func switchAgent(_ id: String, to agent: String) async throws -> AgentSwitch {
        let fields = ",\"sessionId\":\"\(try wireId(id))\",\"agent\":" + jsonString(agent)
        let path = socketPath()
        // the host checks the agent's sign-in and models and opens its conversation before it closes the old one: far more than the 5 seconds of a request that only asks
        return try await Task.detached { try chatRequest(path, "switchAgent", requires: .switchAgent, fields: fields, timeout: 60) }.value
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

    public func stopTask(_ id: String, task: String) async throws {
        let fields = ",\"sessionId\":\"\(try wireId(id))\",\"taskId\":" + jsonString(task)
        let path = socketPath()
        let _: AnyReply = try await Task.detached { try chatRequest(path, "stopTask", requires: .stopTask, fields: fields) }.value
    }

    /// Both ids go on the wire JSON-encoded, as they come from the provider.
    public func answer(_ id: String, approval: String, choice: String, answers: [String: String]?) async throws {
        let encoder = JSONEncoder()
        var fields = ",\"sessionId\":\"\(try wireId(id))\",\"approvalId\":" + String(decoding: try encoder.encode(approval), as: UTF8.self)
            + ",\"choiceId\":" + String(decoding: try encoder.encode(choice), as: UTF8.self)
        if let answers { fields += ",\"answers\":" + String(decoding: try encoder.encode(answers), as: UTF8.self) }
        let path = socketPath()
        let wire = fields
        let _: AnyReply = try await Task.detached { try chatRequest(path, "answer", requires: .answer, fields: wire) }.value
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
    private struct TitlesReply: Decodable { let started: Int }

    /// The host's one generator call has 30 seconds and the call waits behind the one in progress, so the wait for the reply is longer than the 5 seconds of the other requests.
    public func regenerateTitle(_ id: String) async throws -> String {
        let fields = ",\"sessionId\":\"\(try wireId(id))\""
        let path = socketPath()
        let reply: TitleReply = try await Task.detached { try chatRequest(path, "regenerateTitle", requires: .regenerateTitle, fields: fields, timeout: 70) }.value
        return reply.title
    }

    public func regenerateTitles() async throws -> Int {
        let path = socketPath()
        let reply: TitlesReply = try await Task.detached { try chatRequest(path, "regenerateTitles", requires: .regenerateTitles) }.value
        return reply.started
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
func jsonString(_ text: String) -> String { String(decoding: (try? JSONEncoder().encode(text)) ?? Data("\"\"".utf8), as: UTF8.self) }

/// The reply of `open`: only the new session's id is read.
/// Where a plan works: a folder that exists, a repository `owner/name` (the host clones it into its projects folder when the message is sent, or
/// fetches it when it is there already), or a new project of this name (the host makes `<projects folder>/local/<name>` when the message is sent). A new
/// project keeps `project` as its `kind` on the wire, since an older host refuses another value.
public enum PlanWorkspace: Equatable {
    case folder(String)
    case repo(String)
    case newProject(String)
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
        case .newProject(let name): "{\"kind\":\"project\",\"name\":\(jsonString(name))}"
        }
        var fields = [
            "\"workspace\":\(place)", "\"agent\":\(jsonString(agent))", "\"text\":\(jsonString(text))",
        ]
        if options.isEmpty == false { fields.append("\"options\":{" + options.sorted { $0.key < $1.key }.map { "\(jsonString($0.key)):\(jsonString($0.value))" }.joined(separator: ",") + "}") }
        // a worktree is cut from the branch, so the one field serves both
        if let branch = worktree?.from ?? branch { fields.append("\"branch\":\(jsonString(branch))") }
        if let worktree {
            let inside = [worktree.name.map { "\"name\":\(jsonString($0))" }, worktree.startFrom.map { "\"startFrom\":\"\($0.rawValue)\"" }].compactMap { $0 }
            fields.append("\"worktree\":{" + inside.joined(separator: ",") + "}")
        }
        return "{" + fields.joined(separator: ",") + "}"
    }
}

/// What an agent offers before a session exists.
public struct AgentOffer: Codable, Equatable {
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

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(options, forKey: .options)
        try values.encode(commands, forKey: .commands)
    }
}

/// The reply of `switchAgent`: the session as it is now (it has no `live` or the activity of a listed one, so it is not a `ChatSession`) and the new agent's options.
public struct AgentSwitch: Decodable, Equatable {
    public struct Session: Decodable, Equatable {
        public let id: String
        public let agent: String
        public let harness: String
        public let state: ChatSession.State
    }

    public let session: Session
    public let options: [ChatOption]
}

/// The reply of `open`: only the new session's id is read.
private struct OpenedReply: Decodable {
    struct Session: Decodable { let id: String }
    let session: Session
}

/// The reply of `cancelPreparation`: the plan as the host stored it, or null when the session stays (a restore of a worktree).
private struct CancelledReply: Decodable {
    struct Stored: Decodable {
        struct Workspace: Decodable {
            let kind: String
            let folder: String?
            let repo: String?
            let name: String?
        }
        struct Worktree: Decodable { let name: String?; let startFrom: String? }
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
                case ("project", _, _, let name?): place = .newProject(name)
                default: throw ControlError.badLine
                }
                let cut = worktree.flatMap { wanted in branch.map { WorktreeRequest(from: $0, name: wanted.name, startFrom: wanted.startFrom.flatMap(WorktreeStart.init(rawValue:))) } }
                return SessionPlan(agent: agent, workspace: place, branch: worktree == nil ? branch : nil, worktree: cut, options: options ?? [:], text: text)
            }
        }
    }
    let plan: Stored?
}

private struct SuggestedName: Decodable { let name: String }

/// A reply whose content the app does not read: any JSON will do.
private struct AnyReply: Decodable { init(from decoder: Decoder) throws {} }

private struct DeletePreviewReply: Decodable { let sessions: [SessionDeletePreview] }

struct ChatSessionsReply: Decodable { let sessions: [ChatSession] }

/// The options and the commands of each session as the host last sent them, with its name for that version (`listsRev`): the one thing of a
/// reply that is most of its bytes and almost never changes. A reference, so every copy of the host that holds it shares what was kept.
private final class ListsMemory: @unchecked Sendable {
    struct Kept { let rev: String; let options: [ChatOption]; let commands: [ChatCommand] }

    private let lock = NSLock()
    private var kept: [String: Kept] = [:]

    func kept(_ session: String) -> Kept? { lock.withLock { kept[session] } }

    /// The reply with its lists: the ones that came, kept for the next ask, or the ones kept when the host said they had not changed.
    /// A name that is not plain hex is not kept (it goes into the next request as it is), and a host that gives none is asked in full.
    func filled(_ reply: ChatEvents, for session: String, kept before: Kept?) -> ChatEvents {
        if reply.listsUnchanged {
            // nothing was kept to send back, so the host had no reason to say it: what it left out is not an empty list to keep
            guard let before else { return reply }
            return reply.with(options: before.options, commands: before.commands)
        }
        lock.withLock {
            if let rev = reply.listsRev, rev.isEmpty == false, rev.count <= 64, rev.allSatisfy(\.isHexDigit) {
                kept[session] = Kept(rev: rev, options: reply.options, commands: reply.commands)
            } else {
                kept[session] = nil
            }
        }
        return reply
    }
}

/// Makes one request the host said it can answer, on a connection whose hello was read, and decodes its reply.
func chatExchange<Reply: Decodable>(
    _ client: ControlClient, _ command: String, requires capability: ControlClient.Capability, fields: String = "",
    also: [(capability: ControlClient.Capability, fields: String)] = []
) throws -> Reply {
    // fields only a host that lists their capability understands: an older one is not sent them
    let sent = fields + also.filter { client.capabilities.contains($0.capability) }.map(\.fields).joined()
    guard let reply = try client.request(command, requires: capability, fields: sent, as: Reply.self) else {
        throw ControlError.remote("the chat host does not support \(command)")
    }
    return reply
}

/// Connects, reads the hello, makes one request the host said it can answer and decodes its reply.
fileprivate func chatRequest<Reply: Decodable>(
    _ path: String, _ command: String, requires capability: ControlClient.Capability, fields: String = "", also: [(capability: ControlClient.Capability, fields: String)] = [],
    timeout: TimeInterval = 5
) throws -> Reply {
    let signpost = Signposts.poll.beginInterval("chat request", id: Signposts.poll.makeSignpostID(), "\(command, privacy: .public)")
    defer { Signposts.poll.endInterval("chat request", signpost) }
    guard let client = ControlClient.connect(path: path, timeout: timeout) else { throw ControlError.closed }
    defer { client.close() }
    _ = try client.supportedHello()
    return try chatExchange(client, command, requires: capability, fields: fields, also: also)
}

/// `chatRequest`, but a host that does not list the request is told in the words of what to do about it.
fileprivate func usageRequest<Reply: Decodable>(_ path: String, _ command: String, requires capability: ControlClient.Capability, fields: String, timeout: TimeInterval = 5) throws -> Reply {
    do { return try chatRequest(path, command, requires: capability, fields: fields, timeout: timeout) } catch ControlError.remote(let reason) where reason == "the chat host does not support \(command)" {
        throw ControlError.remote(usageNeedsNewerHost)
    }
}

/// `chatRequest` for the `projects` capability, but a host that does not list it is told in the words of what to do about it.
fileprivate func projectsRequest<Reply: Decodable>(_ path: String, _ command: String, fields: String = "", timeout: TimeInterval = 5) throws -> Reply {
    do { return try chatRequest(path, command, requires: .projects, fields: fields, timeout: timeout) } catch ControlError.remote(let reason) where reason == "the chat host does not support \(command)" {
        throw ControlError.remote(projectsNeedNewerHost)
    }
}

public let hostNotRunning = "The chat host is not running"
