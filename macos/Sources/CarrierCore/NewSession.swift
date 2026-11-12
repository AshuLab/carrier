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
    public let harness: String
    public let state: ToolState
    public var available: Bool { state.blocks == false }
    /// What to do about it: the fixed list's command or installation page for this provider in this state.
    public var fix: HealthFix? { healthFix(.agent(harness: harness), state) }
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
        return AgentChoice(name: agent.name, harness: agent.harness, state: state)
    }
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

/// What the draft says about Carrier's list once a session's message step is done and the repository it was to watch was added (or could not be).
public struct WatchNote: Equatable {
    public let text: String
    public let failed: Bool
}

/// The draft: loads what it offers, and `send()` opens the session with one request that carries the plan and the first message.
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
    /// What each agent offered when last asked, kept between drafts and launches.
    @ObservationIgnored private let offers: AgentOfferStore
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

    /// Whether a host answered and its hello does not list `plan`: it cannot take the first message as a plan, so the draft sends nothing.
    public private(set) var hostOlder = false
    /// What the draft says then, and why nothing is sent.
    public static let olderHostNotice = "The chat host is older than this app, so it cannot start a session. Restart it to use the installed Carrier."
    /// Whether the host can prepare a plan for a repository (its hello lists `repoBranches`, which comes with it); an older one is not offered From a GitHub URL…
    public private(set) var hostPlansRepos = false
    /// Whether the host can list the person's GitHub repositories (its hello lists `githubRepos`).
    public private(set) var hostLists = false
    /// Whether the host can make a new project (its hello lists `createProject`).
    public private(set) var hostCreates = false
    /// The `<owner>/<repo>` folders of the projects folder, read from disk each time the popover opens.
    public private(set) var projects: [ProjectFolder] = []
    public private(set) var step = WorkspaceStep.menu
    /// What the URL step was given.
    public var urlText = ""
    /// The repository `owner/name` the plan is for, nil when it is for a folder or a new project. Nothing is cloned and nothing is written
    /// when it is chosen: the host clones it (or fetches it when it is in the projects folder) when the message is sent.
    public private(set) var repo: String?
    /// Whether the repository is not on this Mac: its branches come from GitHub, it has no uncommitted changes and its worktree has no name yet.
    public private(set) var toClone = false
    /// Whether GitHub's branches are being read, and whether there are more than the ones listed.
    public private(set) var loadingBranches = false
    public private(set) var branchesPartial = false
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
    /// The name of the new project the draft is planned for, nil when the workspace is a folder that exists. Nothing is made until the
    /// message is sent: `folder` is the path the host will make.
    public private(set) var newProject: String?
    /// "Let Carrier watch this repo": the person's choice, on by default; `watching` is what it comes to for the repository typed. It is acted on
    /// when the `message` step of the session is done, never before.
    public var watch = true
    /// The `repos` of the config file as of the last time the popover opened or showed a step; nil when the file cannot be read.
    public private(set) var watched: [String]?
    /// What was said of Carrier's list for each session whose repository was to be added, in words, for its conversation to show.
    public private(set) var watchNotes: [String: WatchNote] = [:]
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
    /// The repositories to add to the engine's `repos`, by the session that was opened for them, until its `message` step is done.
    @ObservationIgnored private var pendingWatches: [String: String] = [:]
    @ObservationIgnored private var watchTask: Task<Void, Never>?
    @ObservationIgnored private let ensureHost: @MainActor () async -> Bool
    @ObservationIgnored private let log: (String) -> Void
    @ObservationIgnored private let sleep: (Duration) async throws -> Void
    @ObservationIgnored private let watchEvery: Duration
    /// The name the host last vouched for (suggested or checked), so a name it already vouched for is not asked about again.
    @ObservationIgnored private var verifiedName: String?
    /// The first message of each session the draft opened, by session id, until its conversation takes it.
    @ObservationIgnored private var firstMessages: [String: String] = [:]
    /// The plan of a cancelled preparation, put back in the draft the next time it loads, and the options of it that wait for the agent's list.
    @ObservationIgnored private var restoring: SessionPlan?
    @ObservationIgnored private var restoredOptions: [String: String]?
    /// The folder a workspace header's + asked for, chosen when the draft loads next.
    @ObservationIgnored private var startFolder: String?
    /// Counts the asks for a folder, so the open draft loads again for the new one.
    public private(set) var starts = 0

    /// `ensureHost` starts the chat host when it is not running (#503) and says whether it answers now.
    /// `sleep` is the wait before a typed name is checked, `watchEvery` how often the list is looked at for a session whose repository is to be watched. `projectsFolder` is where `chat.json` says the projects folder is, and
    /// `readChatConfig` and `writeChatConfig` are that file inside `carrierFolder`; `readConfig` and `writeConfig` are the engine's
    /// config file, which holds the watched repositories.
    public init(
        host: ChatHost, health: HealthStore? = nil, offers: AgentOfferStore? = nil, ensureHost: @escaping @MainActor () async -> Bool = { true },
        log: @escaping (String) -> Void = { FileHandle.standardError.write(Data("carrier: \($0)\n".utf8)) },
        sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }, watchEvery: Duration = .seconds(2),
        projectsFolder: @escaping () -> String = currentProjectsFolder,
        readConfig: @escaping () -> Data? = currentConfig, writeConfig: @escaping (Data) throws -> Void = writeCurrentConfig,
        readChatConfig: @escaping () throws -> Data? = currentChatConfig, writeChatConfig: @escaping (Data) throws -> Void = writeCurrentChatConfig,
        carrierFolder: String = currentCarrierFolder()
    ) {
        self.host = host
        self.health = health
        self.offers = offers ?? AgentOfferStore()
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
        self.watchEvery = watchEvery
    }

    /// Reads the agents and the recent folders again, each time the draft opens. A host that does not answer is started (the + is always
    /// on, so this is where it comes up) and asked once more; one that still does not answer leaves what was there.
    public func load() async {
        blank()
        do {
            do { try await read() } catch {
                guard await ensureHost() else { throw error }
                try await read()
            }
        } catch {
            log("new session: \(ConversationModel.words(error))")
        }
        pickAvailableAgent()
        if let plan = restoring {
            restoring = nil
            await apply(plan)
        } else if let path = startFolder {
            startFolder = nil
            await choose(folder: path)
        }
    }

    /// The + of a workspace in the sidebar: the draft opens (or starts over, if it is open) with that folder chosen.
    public func start(in path: String) {
        startFolder = path
        starts += 1
    }

    /// A cancelled preparation gives the plan back: the draft that loads next has the folder, the branch or the worktree, the agent and its
    /// options and the text it was sent with, so nothing typed is lost.
    public func restore(_ plan: SessionPlan) { restoring = plan }

    private func apply(_ plan: SessionPlan) async {
        switch plan.workspace {
        case .folder(let path): await choose(folder: path)
        case .repo(let name): await choose(repo: name)
        case .project(let name): choose(project: name)
        }
        text = plan.text
        if agents.contains(where: { $0.name == plan.agent && $0.available }) { agent = plan.agent }
        restoredOptions = plan.options
        if let wanted = plan.worktree {
            picked = wanted.from
            await useWorktree(true)
            // an empty name is the host's to generate, which the draft already did
            if let name = wanted.name, name.isEmpty == false, worktree { worktreeName = name }
        } else if let branch = plan.branch {
            picked = branch
        }
    }

    /// Every opening of New session starts here: no workspace (nor the branch and worktree that depend on it), no text, nothing the last
    /// opening left half done. The agent and its options are the person's taste, not part of where the session works, and stay.
    public func blank() {
        clearWorkspace()
        text = ""
        refusal = nil
        urlText = ""
        projectName = ""
        step = .menu
    }

    /// The workspace chip's ✕: drops the workspace and what depends on it (branch, worktree choice and name).
    public func clearWorkspace() { reset(folder: nil) }

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
        hostOlder = capabilities.contains(.plan) == false
        hostPlansRepos = capabilities.contains(.repoBranches)
        hostCreates = capabilities.contains(.createProject)
        hostLists = capabilities.contains(.githubRepos)
    }

    /// Lists what the chosen agent offers: what was kept for it shows at once and the host is asked again in the background, so the list
    /// follows any change; with nothing kept the selects say they are reading until it answers. A new agent starts from its own values: what
    /// was chosen for the other is dropped. A host that cannot list them, or fails, leaves the kept list (or none) and the draft goes on.
    public func loadOptions() async {
        defer { takeRestoredOptions() }
        guard let name = agent, optionsAgent != name else { return }
        optionsAgent = name
        chosenOptions = [:]
        let known = offers.offer(name)
        agentOptions = known?.options ?? []
        agentCommands = known?.commands ?? []
        loadingOptions = known == nil
        takeRestoredOptions()
        do {
            let listed = try await offers.refresh(name, host: host)
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

    /// The options of a restored plan, as far as the agent lists them.
    private func takeRestoredOptions() {
        guard let wanted = restoredOptions, loadingOptions == false, agent == optionsAgent else { return }
        restoredOptions = nil
        for (option, value) in wanted { choose(option: option, value: value) }
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
    public var sources: [WorkspaceSource] { [.localFolder] + (hostPlansRepos ? [.githubURL] : []) + (hostLists && hostPlansRepos ? [.githubRepos] : []) + (hostCreates ? [.newProject] : []) }

    /// Why a source of `sources` is off, in words (what `gh` says, the health the app last had); nil when it is on.
    public func sourceReason(_ source: WorkspaceSource) -> String? { workspaceSourceReason(source, gh: health?.latest?.gh) }

    /// The popover opens on the menu with the projects folder read again.
    public func openPicker() {
        refreshFolders()
        projectsFolderProblem = nil
        step = .menu
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
        if next == .url, sourceReason(.githubURL) != nil { return }
        if next == .repos, sourceReason(.githubRepos) != nil { return }
        refreshFolders()
        step = next
    }

    /// The repository the URL step's text names.
    public var reference: String? { repoReference(urlText) }

    /// A repository already among the projects folder's folders is fetched, not cloned again.
    public var alreadyThere: Bool { reference.map { name in projects.contains { $0.name.lowercased() == name.lowercased() } } ?? false }

    public var repoButton: String { alreadyThere ? "Use (updated when sent)" : "Use (cloned when sent)" }

    /// Why the box cannot be on for the repository typed (already watched, or a folder name another watched repo has); nil when it can.
    public var watchProblem: String? { reference.flatMap(watchProblem(for:)) }

    /// The same for any repository: why the box cannot apply to it.
    public func watchProblem(for repo: String) -> String? { watched.flatMap { repoProblem(repo, joining: $0) } }

    public var watching: Bool { watch && watchProblem == nil }

    /// "Use" stays off until the text is one repository.
    public var canUseRepo: Bool { reference != nil }

    /// Chooses the repository of the URL step as the workspace; true when it did. Nothing is cloned: the plan is filled, and the host clones the
    /// repository (fetches it when it is already in the projects folder) when the message is sent.
    public func useRepo() async -> Bool {
        guard let name = reference else { return false }
        urlText = ""
        await choose(repo: name)
        return true
    }

    /// Chooses `owner/name` as the workspace. One in the projects folder is read locally, as a folder; one that is not on this Mac has its branches
    /// read from GitHub with the person's login, no uncommitted changes and a worktree whose name is generated at once, the host checking it when the message is sent.
    public func choose(repo name: String) async {
        guard isRepoName(name) else { return }
        refreshFolders()
        let there = projects.first { $0.name.lowercased() == name.lowercased() }
        let path = there?.path ?? "\(projectsPath)/\(name)"
        reset(folder: path)
        repo = there?.name ?? name
        if there != nil { return await read(path) }
        toClone = true
        loadingBranches = true
        defer { if folder == path { loadingBranches = false } }
        do {
            let listed = try await host.repoBranches(name)
            guard folder == path else { return }
            let names = listed.branches.contains(listed.defaultBranch) ? listed.branches : [listed.defaultBranch] + listed.branches
            workspace = WorkspaceInfo(folder: path, branch: listed.defaultBranch, defaultBranch: listed.defaultBranch, branches: names.map { .init(name: $0, remote: false) })
            branchesPartial = listed.hasMore
        } catch {
            guard folder == path else { return }
            // the draft still works: the repository is cloned on its default branch, with no worktree to offer
            workspaceProblem = report(error, "list the branches of \(name)")
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

    /// "Use this project" stays off for a name the host would refuse.
    public var canUseNow: Bool { projectName.isEmpty == false && projectNameWarning == nil }

    /// Chooses a new project as the workspace: only the plan is filled, the host makes the folder and runs `git init` when the message is
    /// sent. A project has no commits, so the draft offers neither a branch nor a worktree.
    public func choose(project name: String) {
        let path = "\(projectsPath)/local/\(name)"
        reset(folder: path)
        newProject = name
        workspace = WorkspaceInfo(folder: path)
    }

    /// The New project step's button: uses the name typed; false when it cannot be used.
    public func useProject() -> Bool {
        guard canUseNow else { return false }
        choose(project: projectName)
        projectName = ""
        return true
    }

    /// The line that says beforehand what sending will make, nil unless the workspace is a new project.
    public var projectNote: String? {
        guard newProject != nil, let folder else { return nil }
        return "\(folder) will be created, with git ready, when the message is sent."
    }

    /// What sending will do, in order, for the block under the box: download or update the repository, and cut the worktree's branch. Empty
    /// when sending only starts the agent in the folder.
    public var sendSteps: [SendStep] {
        var steps: [SendStep] = []
        if let repo, let folder {
            if toClone {
                let projects = (projectsPath as NSString).abbreviatingWithTildeInPath
                steps.append(SendStep(icon: "arrow.down.circle", title: "Download the repository", parts: [.text("When you send, Carrier downloads "), .code(repo), .text(" from GitHub into "), .code(projects), .text(". Only this first time: later sessions reuse that copy.")], help: folder))
            } else {
                steps.append(SendStep(icon: "arrow.triangle.2.circlepath", title: "Update the repository", parts: [.text("Updates "), .code(repo), .text(" from GitHub first")], help: folder))
            }
        }
        if worktree, let branch = startBranch {
            let name = worktreeBranchPrefix + (worktreeName.isEmpty ? "<name>" : worktreeName)
            let tail = toClone ? " in a separate folder." : " in a separate folder. Your current folder is not touched."
            steps.append(SendStep(icon: "arrow.triangle.branch", title: "Create a branch of its own", parts: [.text("Creates the branch "), .code(name), .text(" from "), .code(branch), .text(tail)], help: nil))
        }
        return steps
    }

    /// Adds `repo` to the config's `repos`, the file read again just now; the engine reads it when it starts, so nothing is restarted. What it
    /// came to is the session's `watchNotes`.
    private func addToWatched(_ repo: String, session id: String) {
        func failed(_ reason: String) { watchNotes[id] = WatchNote(text: "\(repo) could not be added to Carrier's list: \(reason).", failed: true) }
        guard let json = readConfig(), let names = configRepoNames(json: json) else {
            return failed("the config file could not be read or is not a JSON object")
        }
        if names.contains(where: { $0.lowercased() == repo.lowercased() }) { return }  // another session of it got there first
        if let problem = reposProblem(names + [repo]) { return failed(problem) }
        guard let updated = applyingRepos(names + [repo], to: json) else { return failed("the config file could not be rewritten") }
        do {
            try writeConfig(updated)
            watched = names + [repo]
            watchNotes[id] = WatchNote(text: "Carrier will listen to \(repo) from its next start.", failed: false)
        } catch {
            log("new session: could not write the config: \(error)")
            failed("the config file is not writable")
        }
    }

    /// One look at the sessions whose repository waits to be watched: one whose preparation is over (the `message` step is done) adds its
    /// repository, once; one the host no longer lists (cancelled, deleted) or that is still preparing or failed does not, a failed one
    /// waiting for Try again.
    public func settleWatches() async {
        guard pendingWatches.isEmpty == false, let listed = try? await host.list(archived: false) else { return }
        for (id, repo) in pendingWatches {
            guard let found = listed.first(where: { $0.id == id }) else {
                pendingWatches[id] = nil
                continue
            }
            if found.state != .preparing, found.preparation == nil {
                pendingWatches[id] = nil
                addToWatched(repo, session: id)
            }
        }
    }

    // ponytail: polls the list every two seconds for as long as a session of a repository to watch is preparing or failed; the host could push the step.
    private func keepWatching() {
        guard watchTask == nil else { return }
        watchTask = Task { [weak self] in
            while let self, self.pendingWatches.isEmpty == false {
                await self.settleWatches()
                try? await Task.sleep(for: self.watchEvery)
            }
            self?.watchTask = nil
        }
    }

    /// Chooses the workspace and asks the host what it is; the worktree choice starts over (a new folder has other branches and names).
    public func choose(folder path: String) async {
        reset(folder: path)
        await read(path)
    }

    private func read(_ path: String) async {
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
        newProject = nil
        workspace = nil
        workspaceProblem = nil
        repo = nil
        toClone = false
        loadingBranches = false
        branchesPartial = false
        worktree = false
        picked = nil
        fetchProblem = nil
        worktreeName = ""
        verifiedName = nil
        nameState = .suggesting
    }

    /// The branch the worktree starts from, nil when none is known and the person is asked.
    public var startBranch: String? { picked ?? workspace.flatMap(defaultStartBranch) }

    public func choose(startBranch branch: String) { picked = branch }

    public var sentence: String {
        return workSentence(folder: folder, workspace: workspace, worktree: worktree ? (worktreeName, startBranch) : nil, gitMissing: gitMissing)
    }

    /// The branch the folder will be switched to when the message is sent: the person picked one other than the checked-out one and
    /// asked for no worktree (a worktree is cut from the pick and changes no folder). Nil when the folder keeps its branch.
    public var branchChange: (from: String, to: String)? {
        guard worktree == false, gitMissing == false, let workspace, workspace.git, workspace.bare == false, let to = picked, to != workspace.branch else { return nil }
        return (workspace.branch ?? "detached HEAD", to)
    }

    /// The line that says beforehand that the folder's branch will change.
    public var branchNote: String? {
        guard toClone == false else { return nil }
        return branchChange.map { "The branch of the folder will change from \($0.from) to \($0.to) when the message is sent." }
    }

    /// The line under the sentence: the uncommitted files of the base folder, which a worktree would keep out of the agent's way; when the
    /// branch is to change, that this step will fail (sending is still allowed).
    public var warning: String? {
        guard worktree == false, gitMissing == false, let workspace else { return nil }
        guard branchChange != nil else { return uncommittedWarning(workspace) }
        guard workspace.dirty > 0 else { return nil }
        return "\(workspace.dirty) uncommitted \(workspace.dirty == 1 ? "file" : "files") in the folder, so changing its branch will fail and it keeps the branch it is on. Save the work first, or use a worktree."
    }

    /// What the host last said of `gh`; nil while it has not said (an older host, or none yet).
    public var ghState: ToolState? { health?.latest?.gh }

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

    /// ↻: asks the host for another free name; a repository to clone has no folder to ask yet, so its name is made here.
    public func rollName() async {
        guard let path = folder else { return }
        if toClone {
            worktreeName = generatedWorktreeName()
            nameState = .free
            return
        }
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
        guard worktree, toClone == false, name != verifiedName, let path = folder else { return }
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
        guard let path = folder, fetching == false, toClone == false else { return }
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

    public var canSend: Bool { canSendWithText && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }

    /// Whether everything but the text is ready: a long text pasted into the box is the message when there is none typed.
    public var canSendWithText: Bool {
        guard folder != nil, hostOlder == false, agents.contains(where: { $0.name == agent && $0.available }), sending == false else { return false }
        guard worktree else { return true }
        if case .problem = nameState { return false }
        return startBranch != nil && (worktreeName.isEmpty == false || toClone)
    }

    /// What `send` asks `open` for: nil in the base folder.
    var worktreeRequest: WorktreeRequest? {
        guard worktree, let from = startBranch else { return nil }
        return WorktreeRequest(from: from, name: worktreeName.isEmpty ? nil : worktreeName)
    }

    /// Opens the session with one request that carries the plan and the first message, and returns the session's id to select, nil when
    /// `open` was refused or was not made (the draft keeps the text and says why). The host prepares the session in the background and its
    /// conversation shows the steps; the message is kept in `takeFirstMessage` for it.
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
        // a host that was not running when the draft opened has not said yet whether it takes a plan
        if let capabilities = try? await host.capabilities() { hostOlder = capabilities.contains(.plan) == false }
        guard hostOlder == false else { return nil }
        let id: String
        do {
            id = try await host.open(plan: SessionPlan(agent: agent, workspace: newProject.map(PlanWorkspace.project) ?? repo.map(PlanWorkspace.repo) ?? .folder(folder), branch: branchChange?.to, worktree: worktreeRequest, options: chosenOptions, text: message))
        } catch {
            refusal = report(error, "open the session")
            return nil
        }
        firstMessages[id] = message
        // added when the `message` step is done, never before
        if let repo, watch, watchProblem(for: repo) == nil { pendingWatches[id] = repo; keepWatching() }
        blank()
        return id
    }

    /// The first message of a session this draft opened, handed over once to the conversation that shows it.
    public func takeFirstMessage(of id: String) -> String? { firstMessages.removeValue(forKey: id) }

    private func report(_ error: Error, _ doing: String) -> String {
        let message = ConversationModel.words(error)
        // a refusal is the host answering as it should; anything else is a failure to talk to it
        if case ControlError.remote = error { return message }
        log("new session: could not \(doing): \(message)")
        return message
    }
}

/// One thing sending will do, as a line of text with the names set apart; `help` is the detail for a tooltip.
public struct SendStep: Equatable {
    public enum Part: Hashable { case text(String), code(String) }
    public let icon: String
    /// What the step does in a few words, over the sentence that tells it.
    public let title: String
    public let parts: [Part]
    public let help: String?
}
