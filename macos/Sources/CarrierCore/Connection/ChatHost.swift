import Foundation

// The app's side of the chat host's socket (docs/specs/chat-host.md, sessions-in-the-app.md): the requests it needs so far,
// a monitor that says whether the host answers, and the rule for the Sessions + flag. The slices that use more requests add them to `ChatHost`.
// Here is the protocol and what a host that lacks a request answers; `SocketChatHost.swift` is the host over its socket, and the types of its replies are
// `ChatAgent.swift`, `ChatSession.swift`, `ChatHostModels.swift`, `SessionPlan.swift` and `ChatHostReplies.swift`.

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
    /// Changes keys of `chat.json` and answers the keys as the file now has them; refused with a code and the key path and kind for a value the file's schema
    /// refuses, the file left as it was. Over the socket when the hello lists `config`, through `carrier config` otherwise.
    func editChatSettings(_ changes: ChatSettingChanges) async throws -> ChatSettingsSaved
    /// Changes `providers.json` and answers what the running engine did with the file; refused with a code for a value the file's schema refuses, the file left as it was.
    /// Over the socket when the hello lists `config`, through `carrier config` otherwise.
    func changeProviders(_ request: ProvidersRequest) async throws -> ProvidersSaved
    /// Changes `projects.json` or `projectsFolder` of `chat.json` (ProjectsRequests.swift); refused with a code, the file left as it was. Over the socket when the hello lists `config`, through `carrier config` otherwise.
    func changeProjects(_ change: ProjectsChange) async throws -> ProjectsChanged
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
    public func stopTask(_ id: String, task: String) async throws { throw ControlError.remote(.hostLacks("stopTask")) }

    /// A host that cannot prepare a session from a plan has nothing to try again.
    public func retryPreparation(_ id: String) async throws { throw ControlError.remote(.hostLacks("retryPreparation")) }

    /// A host that cannot prepare a session from a plan has nothing to cancel.
    public func cancelPreparation(_ id: String) async throws -> SessionPlan? { throw ControlError.remote(.hostLacks("cancelPreparation")) }

    /// A host that cannot list an agent's options before a session says it lists none.
    public func agentOptions(_ agent: String) async throws -> AgentOffer { AgentOffer() }

    /// A host that cannot list the branches of a repository refuses; the app only asks one that lists `repoBranches`.
    public func repoBranches(_ repo: String) async throws -> RepoBranches { throw ControlError.remote(.hostLacks("repoBranches")) }

    /// A host that has no projects requests says it is older and to restart it.
    public func cloneProject(_ repo: String, into parent: String?) async throws -> ProjectClone { throw ControlError.remote(.projectsNeedNewerHost) }
    public func projectClones() async throws -> [ProjectClone] { throw ControlError.remote(.projectsNeedNewerHost) }
    public func projectWorktrees(_ folder: String) async throws -> ProjectWorktrees { throw ControlError.remote(.projectsNeedNewerHost) }
    public func projectDisk(_ folders: [String], refresh: ProjectDiskRefresh) async throws -> ProjectDiskReply { throw ControlError.remote(.projectsNeedNewerHost) }
    public func removeProjectWorktree(_ folder: String, path: String) async throws { throw ControlError.remote(.projectsNeedNewerHost) }
    public func cleanProjectWorktrees(_ folder: String, run: Bool) async throws -> ProjectCleanup { throw ControlError.remote(.projectsNeedNewerHost) }
    public func dismissClone(_ repo: String) async throws -> [ProjectClone] { throw ControlError.remote(.projectsNeedNewerHost) }
    public func newProject(_ name: String, into parent: String?) async throws -> String { throw ControlError.remote(.projectsNeedNewerHost) }

    /// A host that cannot say how the machine is refuses; the app only asks one that lists `health`.
    public func health(refresh: Bool) async throws -> HostHealth { throw ControlError.remote(.hostLacks("health")) }

    /// A host that does not write config refuses; the real one always has a way.
    public func editChatSettings(_ changes: ChatSettingChanges) async throws -> ChatSettingsSaved { throw ControlError.remote(.hostLacks("editChatSettings")) }
    public func changeProjects(_ change: ProjectsChange) async throws -> ProjectsChanged { throw ControlError.remote(.hostLacks(change.cmd)) }

    public func changeProviders(_ request: ProvidersRequest) async throws -> ProvidersSaved { throw ControlError.remote(.hostLacks(request.command)) }

    /// A host that cannot list the AI tools refuses; the app only asks one that lists `providers`.
    public func providers() async throws -> HostProviders { throw ControlError.remote(.hostLacks("providers")) }

    /// A host that cannot say what was used refuses; the app only asks one that lists `usage`.
    public func usage(_ query: UsageQuery) async throws -> UsageSnapshot { throw ControlError.remote(.usageNeedsNewerHost) }

    /// A host that cannot price refuses; the app only asks one that lists `usageOverride`.
    public func usageOverride(_ override: UsageOverride) async throws { throw ControlError.remote(.usageNeedsNewerHost) }

    /// A host that cannot switch agents refuses; the app only asks one that lists `switchAgent`.
    public func switchAgent(_ id: String, to agent: String) async throws -> AgentSwitch { throw ControlError.remote(.hostLacks("switchAgent")) }

    /// A host that cannot rename refuses; the app only asks one that lists `rename`.
    public func rename(_ id: String, _ title: String) async throws { throw ControlError.remote(.hostLacks("rename")) }

    /// A host that cannot write titles refuses; the app only asks one that lists `regenerateTitle`.
    public func regenerateTitle(_ id: String) async throws -> String { throw ControlError.remote(.hostLacks("regenerateTitle")) }

    /// A host that cannot write earlier titles refuses; the app only asks one that lists `regenerateTitles`.
    public func regenerateTitles() async throws -> Int { throw ControlError.remote(.hostLacks("regenerateTitles")) }

    /// A host that knows no commands sends the text as it is.
    public func send(_ id: String, _ text: String, command: String?) async throws { try await send(id, text) }
}
