import Foundation

/// The chat host over its socket, with the blocking socket work off the caller's thread. What the app reads over and over (`list`, `events`, the
/// hello's capabilities and the updates of the sessions) goes through the one connection `ChatLink` keeps for the socket; everything else is an
/// action, one connection per call. A host that is not there, or goes away mid-call, is `ControlError.closed`; an error reply is `.remote`.
public struct SocketChatHost: ChatHost {
    private let socketPath: () -> String
    /// What each session's options and commands were when the host last sent them, so the host can leave them out of the next answers.
    private let lists = ListsMemory()

    /// How `carrier config` is run for a request the host cannot take; nil in a context that makes none.
    private let configLauncher: CarrierConfigLauncher?

    public init(socketPath: @escaping () -> String = { chatSocketPath() }, configLauncher: CarrierConfigLauncher? = nil) {
        self.socketPath = socketPath
        self.configLauncher = configLauncher
    }

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

    /// To the socket when the host's hello lists `config`; otherwise (an older host, or none running) `carrier config` takes it and writes the file with the same code.
    public func editChatSettings(_ changes: ChatSettingChanges) async throws -> ChatSettingsSaved {
        let fields = ",\"changes\":\(changes.json)"
        let path = socketPath()
        if (try? await capabilities())?.contains(.config) == true {
            return try await Task.detached { try chatRequest(path, "editChatSettings", requires: .config, fields: fields) }.value
        }
        guard let configLauncher else { throw ControlError.remote(.hostLacks("editChatSettings")) }
        return try await configLauncher.run(changes.request, as: ChatSettingsSaved.self)
    }

    /// As `editChatSettings`; the host asks the engine to read the file before it answers, so the request waits longer.
    public func changeProviders(_ request: ProvidersRequest) async throws -> ProvidersSaved {
        let path = socketPath()
        if (try? await capabilities())?.contains(.config) == true {
            return try await Task.detached { try chatRequest(path, request.command, requires: .config, fields: request.fields, timeout: 15) }.value
        }
        guard let configLauncher else { throw ControlError.remote(.hostLacks(request.command)) }
        return try await configLauncher.run(request.request, as: ProvidersSaved.self)
    }

    public func changeProjects(_ change: ProjectsChange) async throws -> ProjectsChanged {
        let path = socketPath()
        if (try? await capabilities())?.contains(.config) == true {
            return try await Task.detached { try chatRequest(path, change.cmd, requires: .config, fields: change.fields) }.value
        }
        guard let configLauncher else { throw ControlError.remote(.hostLacks(change.cmd)) }
        return try await configLauncher.run(change.request, as: ProjectsChanged.self)
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
        guard isRepoName(repo) else { throw ControlError.remote(.repoInvalid(repo)) }
        if let parent, parent.isEmpty || parent.count > 4096 { throw ControlError.remote(.folderUnusable) }
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
        if folder.isEmpty || folder.count > 4096 { throw ControlError.remote(.folderUnusable) }
        let fields = ",\"folder\":\(jsonString(folder))"
        let path = socketPath()
        return try await Task.detached { try projectsRequest(path, "projectWorktrees", requires: .worktreeIntegration, fields: fields) }.value
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
        if folder.isEmpty || folder.count > 4096 || worktree.isEmpty || worktree.count > 4096 { throw ControlError.remote(.folderUnusable) }
        let fields = ",\"folder\":\(jsonString(folder)),\"path\":\(jsonString(worktree))"
        let path = socketPath()
        // git removes the folder with what it ignores (dependencies, builds), which can take a while
        let _: AnyReply = try await Task.detached { try projectsRequest(path, "removeProjectWorktree", fields: fields, timeout: 120) }.value
    }

    public func cleanProjectWorktrees(_ folder: String, run: Bool) async throws -> ProjectCleanup {
        if folder.isEmpty || folder.count > 4096 { throw ControlError.remote(.folderUnusable) }
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
        if let parent, parent.isEmpty || parent.count > 4096 { throw ControlError.remote(.folderUnusable) }
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

    public func close(_ id: String) async throws {
        let fields = ",\"sessionId\":\"\(try wireId(id))\""
        let path = socketPath()
        let _: AnyReply = try await Task.detached { try chatRequest(path, "close", requires: .close, fields: fields) }.value
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
