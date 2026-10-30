import Foundation
import Observation

// The draft of a new session (docs/specs/sessions-in-the-app.md, "New session"): the recent folders and the agents it offers, the
// sentence that says where the session works, and the model that opens the session and sends the first message. Nothing exists
// until that message is sent. What the sentence says about the branch, uncommitted changes, non-git folders and the new worktree
// is in WorktreeChoice.swift; the model asks the host what the folder is and drives the worktree's name and branch.

/// A folder the workspace picker offers: its last component and its full path.
public struct RecentFolder: Equatable {
    public let name: String
    public let path: String
}

/// The distinct base folders of the sessions the host lists (`workspace.base` for a session in a worktree, its folder otherwise),
/// the most recently active first, at most `limit`. `sessions` are the active and the archived ones together.
public func recentFolders(_ sessions: [ChatSession], limit: Int = 8) -> [RecentFolder] {
    var seen: Set<String> = []
    var folders: [RecentFolder] = []
    for session in sessions.sorted(by: { $0.lastActiveAt > $1.lastActiveAt }) {
        let path = session.workspace?.base ?? session.folder
        guard seen.insert(path).inserted else { continue }
        folders.append(RecentFolder(name: URL(fileURLWithPath: path).lastPathComponent, path: path))
        if folders.count == limit { break }
    }
    return folders
}

/// An entry of the agent chip's menu: one that is missing or signed out is listed, disabled, with why ("not installed", "signed out").
public struct AgentChoice: Equatable {
    public let name: String
    public let state: ToolState
    public var available: Bool { state.blocks == false }
    public var note: String? {
        switch state {
        case .missing: "not installed"
        case .signedOut: "signed out"
        case .ready, .unknown: nil
        }
    }
}

/// The host's agents with the state each is in: the health's when the host said one, else as before this check existed (the binary found
/// is `ready`, not found is `missing`).
public func agentChoices(_ agents: [ChatAgent], health: HostHealth? = nil) -> [AgentChoice] {
    agents.map { agent in
        let state = health?.agents.first { $0.name == agent.name }?.state ?? (agent.found ? .ready : .missing)
        return AgentChoice(name: agent.name, state: state)
    }
}

/// A first message whose send failed after `open` made the session.
public struct FailedFirstSend: Equatable {
    public let text: String
    public let reason: String
}

/// A way into the workspace popover besides the folders it lists. One that is not built, or that the host cannot do, is not in `sources`.
public enum WorkspaceSource: String {
    case localFolder = "Open local folder…"
    case githubURL = "From a GitHub URL…"
    case githubRepos = "My GitHub repositories…"
    case newProject = "New project…"
}

/// The step of the workspace popover that is showing.
public enum WorkspaceStep: Equatable {
    case menu, url, repos, project
}

/// The draft: loads what it offers, and `send()` opens the session and then sends the message, in two steps.
@MainActor @Observable public final class NewSessionModel {
    public private(set) var recent: [RecentFolder] = []
    /// The host's agents, with the health the app last had for them.
    public var agents: [AgentChoice] { agentChoices(listed, health: health?.latest) }
    private var listed: [ChatAgent] = []
    /// The chosen workspace's path, nil until one is chosen.
    public private(set) var folder: String?
    public var agent: String?
    /// What the chosen agent offers (models, reasoning, access), as the host listed it before any session; empty while it is being asked,
    /// when the host cannot say, or when it failed: the selects then say what they will hold.
    public private(set) var agentOptions: [ChatOption] = []
    /// What the chosen agent lets the person invoke (skills and its own commands), listed with the options; empty when the host cannot say.
    public private(set) var agentCommands: [ChatCommand] = []
    public private(set) var loadingOptions = false
    /// What the person changed from the agent's own values: an option and a value each, sent when the session opens.
    public private(set) var chosenOptions: [String: String] = [:]
    @ObservationIgnored private var optionsAgent: String?
    public var text = ""
    public private(set) var sending = false
    /// Why `open` was refused (or the host would not start), said in words in the draft; nil when it worked.
    public private(set) var refusal: String?
    /// What the host says the chosen folder is; nil until it answers (and when it refuses, see `workspaceProblem`).
    public private(set) var workspace: WorkspaceInfo?
    /// Why the host would not say what the folder is, in words.
    public private(set) var workspaceProblem: String?
    /// "in a new worktree" instead of "on the base folder"; only a git repository with a working folder offers it.
    public private(set) var worktree = false
    /// The part of the worktree's branch after `carrier/`: the host's suggestion, or what the person typed.
    public var worktreeName = ""
    public private(set) var nameState = NameState.suggesting
    /// The branch the worktree starts from; the person's pick, else `defaultStartBranch`.
    public private(set) var picked: String?
    public private(set) var fetching = false
    /// Why the last Fetch now failed, in the host's words; cleared by the next one.
    public private(set) var fetchProblem: String?

    /// Whether the host can clone (its hello lists `cloneRepo`); an older one is not offered From a GitHub URL…
    public private(set) var hostClones = false
    /// Whether the host can list the person's GitHub repositories (its hello lists `githubRepos`).
    public private(set) var hostLists = false
    /// Whether the host can make a new project (its hello lists `createProject`).
    public private(set) var hostCreates = false
    /// The `<owner>/<repo>` folders of the projects folder, read from disk each time the popover opens.
    public private(set) var projects: [ProjectFolder] = []
    public private(set) var step = WorkspaceStep.menu
    /// What the URL step was given.
    public var urlText = ""
    /// The repository being cloned, nil when none is.
    public private(set) var cloning: String?
    /// Why the last clone was refused, in the host's words; cleared when the next one starts.
    public private(set) var cloneProblem: String?
    /// The pages of the person's repositories loaded so far (My GitHub repositories), the login they were read with (page 1 only),
    /// and why the latest read failed, in the host's words; the list keeps what was loaded when a later page fails.
    public private(set) var repoList = AvailableReposList()
    public private(set) var login: String?
    public private(set) var reposReason: String?
    public private(set) var loadingRepos = false
    /// The search over the loaded repositories.
    public var reposQuery = ""
    /// What the New project step was given: the part after `local/`.
    public var projectName = ""
    public private(set) var creating = false
    /// Why the host refused the last project, in its words; cleared when the next one starts.
    public private(set) var createProblem: String?
    /// "Let Carrier watch this repo": the person's choice, on by default; `watching` is what it comes to for the repository typed.
    public var watch = true
    /// The `repos` of the config file as of the last time the popover opened or showed a step; nil when the file cannot be read.
    public private(set) var watched: [String]?
    /// What the draft says about Carrier's list after a clone that was to add the repository, in words; `watchFailed` when it did not.
    public private(set) var watchNote: String?
    public private(set) var watchFailed = false
    /// Where the footer says the projects folder is.
    public private(set) var projectsPath: String
    /// Why the last Change… was refused, in words; the old folder stands. Cleared when the popover opens.
    public private(set) var projectsFolderProblem: String?

    @ObservationIgnored private let host: ChatHost
    @ObservationIgnored private let health: HealthStore?
    @ObservationIgnored private let projectsFolder: () -> String
    @ObservationIgnored private let readConfig: () -> Data?
    @ObservationIgnored private let writeConfig: (Data) throws -> Void
    @ObservationIgnored private let readChatConfig: () throws -> Data?
    @ObservationIgnored private let writeChatConfig: (Data) throws -> Void
    @ObservationIgnored private let carrierFolder: String
    /// Counts the times the list was started over, so a page that was asked for before is dropped when it comes back.
    @ObservationIgnored private var reposRead = 0
    @ObservationIgnored private var cloneTask: Task<ClonedRepo, Error>?
    @ObservationIgnored private let ensureHost: @MainActor () async -> Bool
    @ObservationIgnored private let log: (String) -> Void
    @ObservationIgnored private let sleep: (Duration) async throws -> Void
    /// The name the host last vouched for (suggested or checked), so a name it already vouched for is not asked about again.
    @ObservationIgnored private var verifiedName: String?
    /// What a conversation shows when its first message failed to send, by session id, until it takes it.
    @ObservationIgnored private var failedFirstSends: [String: FailedFirstSend] = [:]

    /// `ensureHost` starts the chat host when it is not running (#503) and says whether it answers now.
    /// `sleep` is the wait before a typed name is checked. `projectsFolder` is where `chat.json` says the projects folder is, and
    /// `readChatConfig` and `writeChatConfig` are that file inside `carrierFolder`; `readConfig` and `writeConfig` are the engine's
    /// config file, which holds the watched repositories.
    public init(
        host: ChatHost, health: HealthStore? = nil, ensureHost: @escaping @MainActor () async -> Bool = { true },
        log: @escaping (String) -> Void = { FileHandle.standardError.write(Data("carrier: \($0)\n".utf8)) },
        sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        projectsFolder: @escaping () -> String = currentProjectsFolder,
        readConfig: @escaping () -> Data? = currentConfig, writeConfig: @escaping (Data) throws -> Void = writeCurrentConfig,
        readChatConfig: @escaping () throws -> Data? = currentChatConfig, writeChatConfig: @escaping (Data) throws -> Void = writeCurrentChatConfig,
        carrierFolder: String = currentCarrierFolder()
    ) {
        self.host = host
        self.health = health
        self.projectsFolder = projectsFolder
        projectsPath = projectsFolder()
        self.readConfig = readConfig
        self.writeConfig = writeConfig
        self.readChatConfig = readChatConfig
        self.writeChatConfig = writeChatConfig
        self.carrierFolder = carrierFolder
        self.ensureHost = ensureHost
        self.log = log
        self.sleep = sleep
    }

    /// Reads the agents and the recent folders again, each time the draft opens. A host that does not answer is started (the + is always
    /// on, so this is where it comes up) and asked once more; one that still does not answer leaves what was there.
    public func load() async {
        do {
            do { try await read() } catch {
                guard await ensureHost() else { throw error }
                try await read()
            }
        } catch {
            log("new session: \(ConversationModel.words(error))")
        }
        pickAvailableAgent()
    }

    /// Keeps the chosen provider while it can be chosen, else takes the first one that can; none when none can.
    public func pickAvailableAgent() {
        if agents.contains(where: { $0.name == agent && $0.available }) == false { agent = agents.first(where: \.available)?.name }
    }

    /// Why no provider can start a session, when the host listed some and none can; nil otherwise.
    public var noAgentReason: String? {
        guard agents.isEmpty == false, agents.contains(where: \.available) == false else { return nil }
        return "No provider can start a session: " + agents.map { "\($0.name) is \($0.note ?? "unavailable")" }.joined(separator: ", ") + "."
    }

    private func read() async throws {
        listed = try await host.agents()
        recent = recentFolders(try await host.list(archived: false) + (try await host.list(archived: true)))
        let capabilities = try await host.capabilities()
        hostClones = capabilities.contains(.cloneRepo)
        hostCreates = capabilities.contains(.createProject)
        hostLists = capabilities.contains(.githubRepos)
    }

    /// Asks the host what the chosen agent offers. A new agent starts from its own values: what was chosen for the other is dropped. A host
    /// that cannot list them, or fails, leaves the list empty and the draft goes on without options.
    public func loadOptions() async {
        guard let name = agent, optionsAgent != name else { return }
        optionsAgent = name
        agentOptions = []
        agentCommands = []
        chosenOptions = [:]
        loadingOptions = true
        do {
            let listed = try await host.agentOptions(name)
            guard optionsAgent == name else { return }
            agentOptions = listed.options
            agentCommands = listed.commands
        } catch {
            guard optionsAgent == name else { return }
            log("new session: could not list the options of \(name): \(ConversationModel.words(error))")
            optionsAgent = nil  // asked again the next time
        }
        loadingOptions = false
    }

    /// What the selects list: the agent's options with the person's choices on top.
    public var shownOptions: [ChatOption] {
        agentOptions.map { option in
            guard let chosen = chosenOptions[option.id] else { return option }
            return ChatOption(id: option.id, label: option.label, values: option.values, current: chosen)
        }
    }

    /// Chooses a value of an option the agent lists; one it does not list is not taken.
    public func choose(option: String, value: String) {
        guard agentOptions.contains(where: { $0.id == option && $0.values.contains { $0.id == value } }) else { return }
        chosenOptions[option] = value
    }

    /// The sources the popover lists under the folders.
    public var sources: [WorkspaceSource] { [.localFolder] + (hostClones ? [.githubURL] : []) + (hostLists && hostClones ? [.githubRepos] : []) + (hostCreates ? [.newProject] : []) }

    /// Why a source of `sources` is off, in words (what `gh` says, the health the app last had); nil when it is on.
    public func sourceReason(_ source: WorkspaceSource) -> String? { workspaceSourceReason(source, gh: health?.latest?.gh) }

    /// The popover opens on the menu with the projects folder read again; one that is cloning, or whose clone failed while it was closed,
    /// stays on the step that shows it until the next action starts.
    public func openPicker() {
        refreshFolders()
        projectsFolderProblem = nil
        guard cloning == nil, cloneProblem == nil else { return }
        step = .menu
        createProblem = nil
    }

    private func refreshFolders() {
        projectsPath = projectsFolder()
        projects = projectFolders(in: projectsPath)
        watched = readConfig().flatMap { configRepoNames(json: $0) }
    }

    /// The footer's Change…: writes `folder` as `projectsFolder` in `chat.json`, read again just now and made when it is not there. A folder
    /// the host would refuse, or a file that cannot be read or written, leaves the old one and says why in `projectsFolderProblem`.
    /// What was in the old folder is not moved.
    public func changeProjectsFolder(to folder: String) {
        projectsFolderProblem = nil
        func refused(_ reason: String) { projectsFolderProblem = "\(reason). The projects folder stays \(projectsPath)." }
        if let problem = projectsFolderRefusal(folder, carrierFolder: carrierFolder) { return refused(problem) }
        let json: Data?
        do { json = try readChatConfig() } catch {
            log("new session: could not read chat.json: \(error)")
            return refused("chat.json could not be read")
        }
        guard let updated = applyingProjectsFolder(folder, to: json) else { return refused("chat.json is not a JSON object") }
        do { try writeChatConfig(updated) } catch {
            log("new session: could not write chat.json: \(error)")
            return refused("chat.json is not writable")
        }
        refreshFolders()
    }

    public func show(_ next: WorkspaceStep) {
        guard cloning == nil, creating == false else { return }
        if next == .url, sourceReason(.githubURL) != nil { return }
        if next == .repos, sourceReason(.githubRepos) != nil { return }
        refreshFolders()
        step = next
        cloneProblem = nil
        createProblem = nil
    }

    /// The repository being cloned without its owner: what the chip says while it runs.
    public var cloningName: String? { cloning.flatMap { $0.split(separator: "/").last.map(String.init) } }

    /// The repository the URL step's text names.
    public var reference: String? { repoReference(urlText) }

    /// A repository already among the projects folder's folders is fetched, not cloned again.
    public var alreadyThere: Bool { reference.map { name in projects.contains { $0.name.lowercased() == name.lowercased() } } ?? false }

    public var cloneButton: String { cloneProblem != nil ? "Try again" : alreadyThere ? "Update and use" : "Clone and use" }

    /// Why the box cannot be on for the repository typed (already watched, or a folder name another watched repo has); nil when it can.
    public var watchProblem: String? { reference.flatMap(watchProblem(for:)) }

    /// The same for any repository: why the box cannot apply to it.
    public func watchProblem(for repo: String) -> String? { watched.flatMap { repoProblem(repo, joining: $0) } }

    public var watching: Bool { watch && watchProblem == nil }

    /// "Clone and use" stays off until the text is one repository, and while a clone runs.
    public var canCloneNow: Bool { reference != nil && cloning == nil }

    /// Clones (or fetches) the repository of the URL step and chooses its folder as the workspace; true when it did. The draft has no
    /// workspace while it runs and when it fails, so the chip stays orange; the refusal is in `cloneProblem`.
    public func cloneAndUse() async -> Bool {
        guard let repo = reference else { return false }
        return await clone(repo, showing: .url)
    }

    /// The same for a repository chosen in My GitHub repositories, where the clone shows.
    public func cloneAndUse(repo: String) async -> Bool { await clone(repo, showing: .repos) }

    private func clone(_ repo: String, showing shown: WorkspaceStep) async -> Bool {
        guard cloning == nil else { return false }
        let adding = watch && watchProblem(for: repo) == nil
        reset(folder: nil)
        cloning = repo
        cloneProblem = nil
        step = shown
        let task = Task { [host] in try await host.cloneRepo(repo) }
        cloneTask = task
        do {
            let cloned = try await task.value
            guard cloneTask == task else { return false }
            cloning = nil
            cloneTask = nil
            if shown == .url { urlText = "" }
            await choose(folder: cloned.folder)
            // the clone stands whatever happens to the list
            if adding, folder == cloned.folder { addToWatched(repo) }
            return true
        } catch {
            // a clone that was cancelled has already been dropped by `cancelClone`
            guard cloneTask == task else { return false }
            cloning = nil
            cloneTask = nil
            cloneProblem = report(error, "clone \(repo)")
            return false
        }
    }

    /// My GitHub repositories: starts the list over and reads its first page. The step does not open while a clone or a new project is running.
    public func showRepos() async {
        show(.repos)
        guard step == .repos else { return }
        reposRead += 1
        repoList = AvailableReposList()
        login = nil
        reposReason = nil
        reposQuery = ""
        loadingRepos = false
        await loadRepos()
    }

    /// Reads the next page, the first one included: what is loaded stays, and a page that fails is `reposReason` and is asked again by the next call.
    public func loadRepos() async {
        guard loadingRepos == false else { return }
        let read = reposRead
        let page = repoList.nextPage
        loadingRepos = true
        defer { if read == reposRead { loadingRepos = false } }
        do {
            let loaded = try await host.githubRepos(page: page)
            guard read == reposRead else { return }
            if page == 1 { login = loaded.login }
            repoList.apply(.repos(loaded.repos.filter { isRepoName($0.name) }, hasMore: loaded.hasMore))
            reposReason = nil
        } catch {
            guard read == reposRead else { return }
            repoList.apply(.githubError)
            reposReason = report(error, "list repositories")
        }
    }

    /// The loaded repositories that match the search, in the host's order.
    public func repoRows(now: Date = Date()) -> [GithubRepoRow] { githubRepoRows(repoList.repos, watched: watched ?? [], query: reposQuery, now: now) }

    /// The path New project will make, shown before anything is made.
    public var projectPath: String { "\(projectsPath)/local/\(projectName.isEmpty ? "<name>" : projectName)" }

    /// Why the name typed cannot be used (not a plain folder name, or a project of that name is already there); nil when it can, and while nothing is typed.
    public var projectNameWarning: String? {
        guard projectName.isEmpty == false else { return nil }
        if let problem = projectNameProblem(projectName) { return problem }
        if projects.contains(where: { $0.name.lowercased() == "local/" + projectName.lowercased() }) { return "\(projectName) is already a project; choose another name" }
        return nil
    }

    /// "Create and use" stays off for a name the host would refuse, and while a project is being made.
    public var canCreateNow: Bool { projectName.isEmpty == false && projectNameWarning == nil && creating == false }

    /// Makes the project on the host and chooses its folder as the workspace; true when it did. A refusal is in `createProblem` and the
    /// draft keeps its workspace.
    public func createAndUse() async -> Bool {
        guard canCreateNow else { return false }
        let name = projectName
        creating = true
        createProblem = nil
        defer { creating = false }
        do {
            let created = try await host.createProject(name)
            projectName = ""
            await choose(folder: created)
            return true
        } catch {
            createProblem = report(error, "create \(name)")
            return false
        }
    }

    /// Adds `repo` to the config's `repos`, the file read again just now; the engine reads it when it starts, so nothing is restarted.
    private func addToWatched(_ repo: String) {
        func failed(_ reason: String) {
            watchNote = "\(repo) could not be added to Carrier's list: \(reason)."
            watchFailed = true
        }
        guard let json = readConfig(), let names = configRepoNames(json: json) else {
            return failed("the config file could not be read or is not a JSON object")
        }
        if let problem = reposProblem(names + [repo]) { return failed(problem) }
        guard let updated = applyingRepos(names + [repo], to: json) else { return failed("the config file could not be rewritten") }
        do {
            try writeConfig(updated)
            watched = names + [repo]
            watchNote = "Carrier will listen to \(repo) from its next start."
        } catch {
            log("new session: could not write the config: \(error)")
            failed("the config file is not writable")
        }
    }

    /// Cancel: closes the request's connection, which stops the clone on the host, and the draft goes on with no workspace.
    public func cancelClone() {
        cloneTask?.cancel()
        cloneTask = nil
        cloning = nil
    }

    /// Chooses the workspace and asks the host what it is; the worktree choice starts over (a new folder has other branches and names).
    public func choose(folder path: String) async {
        reset(folder: path)
        do {
            let info = try await host.workspace(path)
            guard folder == path else { return }
            workspace = info
        } catch {
            guard folder == path else { return }
            // the draft still works in the base folder: the host refuses the same folder at `open`, in words
            workspaceProblem = report(error, "read the workspace")
        }
    }

    private func reset(folder path: String?) {
        folder = path
        workspace = nil
        workspaceProblem = nil
        cloneProblem = nil
        worktree = false
        picked = nil
        fetchProblem = nil
        worktreeName = ""
        verifiedName = nil
        nameState = .suggesting
        watchNote = nil
        watchFailed = false
    }

    /// The branch the worktree starts from, nil when none is known and the person is asked.
    public var startBranch: String? { picked ?? workspace.flatMap(defaultStartBranch) }

    public func choose(startBranch branch: String) { picked = branch }

    public var sentence: String {
        if let cloning, let name = cloningName { return "Work in \(name) Cloning \(cloning)…" }
        return workSentence(folder: folder, workspace: workspace, worktree: worktree ? (worktreeName, startBranch) : nil, gitMissing: gitMissing)
    }

    /// The line under the sentence: the uncommitted files of the base folder, which a worktree would keep out of the agent's way.
    public var warning: String? { worktree || gitMissing ? nil : workspace.flatMap(uncommittedWarning) }

    /// The health says `git` is missing (`unknown`, or no health at all, switches nothing off).
    public var gitMissing: Bool { health?.latest?.git == .missing }

    public var offersWorktree: Bool { workspace?.offersWorktree == true && gitMissing == false }

    /// The picker's lists for the chosen folder.
    public func picker(query: String, now: Date = Date()) -> BranchPicker? { workspace.map { branchPicker($0, query: query, now: now) } }

    /// "base folder" and "in a new worktree" are one control: choosing the worktree asks the host for a name the first time.
    public func useWorktree(_ on: Bool) async {
        guard on == false || offersWorktree else { return }
        worktree = on
        if on, worktreeName.isEmpty { await rollName() }
    }

    /// ↻: asks the host for another free name.
    public func rollName() async {
        guard let path = folder else { return }
        nameState = .suggesting
        do {
            let name = try await host.suggestName(path)
            guard folder == path else { return }
            worktreeName = name
            verifiedName = name
            nameState = .free
        } catch {
            guard folder == path else { return }
            nameState = .problem(report(error, "suggest a name"))
        }
    }

    /// Checks the name that was typed, after `typingPause` with no change: the view runs it again, cancelling the one before, each time the name changes.
    public func verifyName() async {
        let name = worktreeName
        guard worktree, name != verifiedName, let path = folder else { return }
        nameState = .checking
        do {
            try await sleep(.milliseconds(400))
            let check = try await host.checkName(path, name)
            guard name == worktreeName else { return }
            verifiedName = name
            nameState = stateOfName(check)
        } catch is CancellationError {
            return
        } catch {
            guard name == worktreeName else { return }
            nameState = .problem(report(error, "check the name"))
        }
    }

    /// Fetch now: the host fetches `origin` and answers what the folder is after it, with the remote branches and the time of the fetch.
    public func fetchNow() async {
        guard let path = folder, fetching == false else { return }
        fetching = true
        fetchProblem = nil
        defer { fetching = false }
        do {
            let info = try await host.fetch(path)
            guard folder == path else { return }
            workspace = info
        } catch {
            guard folder == path else { return }
            fetchProblem = report(error, "fetch")
        }
    }

    public var canSend: Bool {
        guard folder != nil, agents.contains(where: { $0.name == agent && $0.available }), sending == false, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return false }
        guard worktree else { return true }
        if case .problem = nameState { return false }
        return startBranch != nil && worktreeName.isEmpty == false
    }

    /// What `send` asks `open` for: nil in the base folder.
    var worktreeRequest: WorktreeRequest? {
        guard worktree, let from = startBranch else { return nil }
        return WorktreeRequest(from: from, name: worktreeName)
    }

    /// Opens the session and sends the message; returns the session's id to select, nil when `open` was refused (the draft keeps
    /// the text and says why). A `send` that fails after `open` still returns the id: the session exists and its conversation shows the failure.
    public func send() async -> String? {
        guard canSend, let folder, let agent else { return nil }
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        sending = true
        refusal = nil
        defer { sending = false }
        guard await ensureHost() else {
            refusal = hostNotRunning
            return nil
        }
        let id: String
        do {
            id = try await host.open(agent: agent, folder: folder, worktree: worktreeRequest, options: chosenOptions)
        } catch {
            refusal = report(error, "open the session")
            return nil
        }
        do {
            // a first message that starts with the name of a command the agent lists invokes it
            if let invoked = invokedCommand(in: message, among: agentCommands) {
                try await host.send(id, invoked.arguments, command: invoked.command.id)
            } else {
                try await host.send(id, message)
            }
        } catch {
            failedFirstSends[id] = FailedFirstSend(text: message, reason: report(error, "send the first message"))
        }
        text = ""
        return id
    }

    /// The failure of a session's first send, handed over once to the conversation that shows it.
    public func takeFailure(of id: String) -> FailedFirstSend? { failedFirstSends.removeValue(forKey: id) }

    private func report(_ error: Error, _ doing: String) -> String {
        let message = ConversationModel.words(error)
        // a refusal is the host answering as it should; anything else is a failure to talk to it
        if case ControlError.remote = error { return message }
        log("new session: could not \(doing): \(message)")
        return message
    }
}
