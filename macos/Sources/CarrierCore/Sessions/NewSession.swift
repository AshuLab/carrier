import Foundation
import Observation

// The draft of a new session (docs/specs/sessions-in-the-app.md, "New session"): the recent folders and the agents it offers, the
// sentence that says where the session works, and the model that opens the session and sends the first message. Nothing exists
// until that message is sent. What the sentence says about the branch, uncommitted changes, non-git folders and the new worktree
// is in WorktreeChoice.swift; the model asks the host what the folder is and drives the worktree's name and branch.

/// A folder the workspace picker offers: its last component and its full path.
public struct RecentFolder: Equatable, Sendable {
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
    public func note(bundle: Bundle? = nil, locale: Locale = .current) -> String? {
        switch state {
        case .missing: Copy.newSessionAgentMissing(bundle: bundle, locale: locale)
        case .signedOut: Copy.newSessionAgentSignedOut(bundle: bundle, locale: locale)
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

/// What the draft says about Carrier's list once a session's message step is done and the repository it was to watch was added (or could not be).
public struct WatchNote: Equatable {
    public let text: String
    public let failed: Bool
}

/// The draft: loads what it offers, and `send()` opens the session with one request that carries the plan and the first message.
@MainActor @Observable public final class NewSessionModel {
    public internal(set) var recent: [RecentFolder] = []
    /// The host's agents, with the health the app last had for them.
    public var agents: [AgentChoice] { agentChoices(listed, health: health?.latest) }
    /// The language the draft says its sentences in: the app's, unless a test says another.
    @ObservationIgnored let bundle: Bundle?
    @ObservationIgnored let locale: Locale
    var listed: [ChatAgent] = []
    /// The chosen workspace's path, nil until one is chosen.
    public internal(set) var folder: String?
    public var agent: String?
    /// What the chosen agent offers (models, reasoning, access), as the host listed it before any session; empty while it is being asked,
    /// when the host cannot say, or when it failed: the selects then say what they will hold.
    public internal(set) var agentOptions: [ChatOption] = []
    /// What the chosen agent lets the person invoke (skills and its own commands), listed with the options; empty when the host cannot say.
    public internal(set) var agentCommands: [ChatCommand] = []
    public internal(set) var loadingOptions = false
    /// What the person changed from the agent's own values: an option and a value each, sent when the session opens.
    public internal(set) var chosenOptions: [String: String] = [:]
    @ObservationIgnored var optionsAgent: String?
    /// What each agent offered when last asked, kept between drafts and launches.
    @ObservationIgnored let offers: AgentOfferStore
    /// What Settings > Sessions says a new session opens with, read each time it is needed so a change shows in the next draft.
    @ObservationIgnored let start: () -> NewSessionStart
    /// What Settings > Sessions says a new session opens in, read when the workspace answers.
    @ObservationIgnored let workIn: () -> WorkIn
    public var text = ""
    /// The long texts pasted into the box and the files dropped on it: kept, with the text, until the message is sent (see `reopen`).
    public var pastes: [PastedEntry] = []
    public var files: [AttachedFile] = []
    public internal(set) var sending = false
    /// Why `open` was refused (or the host would not start), said in words in the draft; nil when it worked.
    public internal(set) var refusal: Refusal?
    /// What the host says the chosen folder is; nil until it answers (and when it refuses, see `workspaceProblem`).
    public internal(set) var workspace: WorkspaceInfo?
    /// Why the host would not say what the folder is, in words.
    public internal(set) var workspaceProblem: String?
    /// "in a new worktree" instead of "on the base folder"; only a git repository with a working folder offers it.
    public internal(set) var worktree = false
    /// The part of the worktree's branch after `carrier/`: the host's suggestion, or what the person typed.
    public var worktreeName = ""
    public internal(set) var nameState = NameState.suggesting
    /// The branch the worktree starts from; the person's pick, else `defaultStartBranch`.
    public internal(set) var picked: String?
    /// The side of the branch the person left the picker's tab on: the session's own choice, which is sent as `startFrom` and never written
    /// to the setting. Nil until a tab or a row of it is chosen; then the setting decides.
    public internal(set) var chosenStart: WorktreeStart?
    /// `worktreeStart` of `chat.json`, read when the workspace is chosen.
    @ObservationIgnored var settingStart = defaultWorktreeStart
    /// Whether the host's hello lists `worktreeStart`: only then is `startFrom` sent; an older host is told `origin/<name>` for a remote start.
    public internal(set) var hostStarts = false
    /// Whether the host's hello lists `fetchIfStale`: only then does choosing a project fetch it.
    public internal(set) var hostFetchesIfStale = false
    /// Whether a fetch of `origin` is running: Fetch now, or the one that choosing a project starts in the background.
    public internal(set) var fetching = false
    /// Whether the fetch that choosing a project started could not reach `origin`: the picker's footer says so, with when the branches were
    /// last fetched, and nothing else is shown or asked. Cleared by the next fetch that works and when another workspace is chosen.
    public internal(set) var unreachable = false
    /// Why the last Fetch now failed, in the host's words; cleared by the next one.
    public internal(set) var fetchProblem: String?

    /// Whether a host answered and its hello does not list `plan`: it cannot take the first message as a plan, so the draft sends nothing.
    public internal(set) var hostOlder = false
    /// What the draft says then, and why nothing is sent.
    public var olderHostNotice: String { Copy.newSessionOlderHost(bundle: bundle, locale: locale) }
    /// Whether the host can make a new project (its hello lists `createProject`): the sheet offers New project… only then.
    public internal(set) var hostCreates = false
    /// The repository `owner/name` the plan is for, nil when it is for a folder or a new project. Nothing is cloned and nothing is written
    /// when it is chosen: the host clones it (or fetches it when it is in the projects folder) when the message is sent.
    public internal(set) var repo: String?
    /// Whether the repository is not on this Mac: its branches come from GitHub, it has no uncommitted changes and its worktree has no name yet.
    public internal(set) var toClone = false
    /// Whether GitHub's branches are being read, and whether there are more than the ones listed.
    public internal(set) var loadingBranches = false
    public internal(set) var branchesPartial = false
    /// The name of the new project the draft is planned for, nil when the workspace is a folder that exists. Nothing is made until the
    /// message is sent: `folder` is the path the host will make.
    public internal(set) var newProject: String?
    /// "Let Carrier watch this repo": the person's choice, on by default; `watching` is what it comes to for the repository chosen. It is acted on
    /// when the `message` step of the session is done, never before.
    public var watch = true
    /// The `repos` of the config file as of the last time the sheet opened or a repository was chosen; nil when the file cannot be read.
    public internal(set) var watched: [String]?
    /// What was said of Carrier's list for each session whose repository was to be added, in words, for its conversation to show.
    public internal(set) var watchNotes: [String: WatchNote] = [:]
    /// The projects folder, where the host clones a repository and makes a new project when the first message is sent.
    public internal(set) var projectsPath: String

    /// Why Add as project could not write the entry, in words; nil when it worked or was not tried.
    public internal(set) var addProjectProblem: String?

    @ObservationIgnored let host: ChatHost
    /// The projects the app keeps, which Add as project writes to; nil in a draft that cannot add one.
    @ObservationIgnored let projects: ProjectsModel?
    @ObservationIgnored let health: HealthStore?
    @ObservationIgnored let projectsFolder: () -> String
    @ObservationIgnored let readConfig: () -> Data?
    @ObservationIgnored let send: SendEngineConfig
    @ObservationIgnored let status: ReloadStatus
    @ObservationIgnored let readChatConfig: () throws -> Data?
    /// Counts the fetches (and the times the workspace was chosen), so the answer of one that was left behind is dropped.
    @ObservationIgnored var fetchRuns = 0
    /// The fetch that choosing a project runs behind the branches, for `refreshed()`.
    @ObservationIgnored var refresh: Task<Void, Never>?
    /// The repositories to add to the engine's `repos`, by the session that was opened for them, until its `message` step is done.
    @ObservationIgnored var pendingWatches: [String: String] = [:]
    @ObservationIgnored var watchTask: Task<Void, Never>?
    /// When the last session whose repository is to be watched was opened.
    @ObservationIgnored var watchSince = Date.distantPast
    @ObservationIgnored let ensureHost: @MainActor () async -> Bool
    @ObservationIgnored let log: (String) -> Void
    @ObservationIgnored let sleep: (Duration) async throws -> Void
    /// The name the host last vouched for (suggested or checked), so a name it already vouched for is not asked about again.
    @ObservationIgnored var verifiedName: String?
    /// The first message of each session the draft opened, by session id, until its conversation takes it.
    @ObservationIgnored var firstMessages: [String: String] = [:]
    /// The plan of a cancelled preparation, put back in the draft the next time it loads, and the options of it that wait for the agent's list.
    @ObservationIgnored var restoring: SessionPlan?
    @ObservationIgnored var restoredOptions: [String: String]?
    /// The folder a workspace header's + asked for, chosen when the draft loads next, and the branch a session's menu asked to cut the worktree from.
    @ObservationIgnored var startFolder: String?
    @ObservationIgnored var startBranchName: String?
    /// What the chosen project sets for a new session here: its agent, where to work and its base branch. Over Settings > Sessions, and the draft shows each
    /// and lets the person change it. Empty for a folder that is not a project.
    public internal(set) var projectDefaults = ProjectDefaults()
    /// Counts the asks for a folder, so the open draft loads again for the new one.
    public internal(set) var starts = 0

    /// `ensureHost` starts the chat host when it is not running (#503) and says whether it answers now.
    /// `bundle` and `locale` say the language of the draft's sentences. `sleep` is the wait before a typed name is checked. `projectsFolder` is where `chat.json` says the projects folder is, and
    /// `readChatConfig` is that file; `readConfig` is the engine's config file, which holds the watched repositories, and `send` asks the engine, or `carrier config`, to change it.
    public init(
        host: ChatHost, health: HealthStore? = nil, offers: AgentOfferStore? = nil, ensureHost: @escaping @MainActor () async -> Bool = { true },
        log: @escaping (String) -> Void = { FileHandle.standardError.write(Data("carrier: \($0)\n".utf8)) },
        sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        projectsFolder: @escaping () -> String = currentProjectsFolder,
        readConfig: @escaping () -> Data? = currentConfig, send: @escaping SendEngineConfig = { try await EngineConfigSender().send($0) },
        status: ReloadStatus? = nil,
        readChatConfig: @escaping () throws -> Data? = currentChatConfig,
        start: @escaping () -> NewSessionStart = { AppPreferences().newSessionStart },
        workIn: @escaping () -> WorkIn = { AppPreferences().workIn },
        projects: ProjectsModel? = nil,
        bundle: Bundle? = nil,
        locale: Locale = .current
    ) {
        self.bundle = bundle
        self.locale = locale
        self.start = start
        self.workIn = workIn
        self.host = host
        self.projects = projects
        self.health = health
        self.offers = offers ?? AgentOfferStore()
        self.projectsFolder = projectsFolder
        projectsPath = projectsFolder()
        self.readConfig = readConfig
        self.send = send
        self.status = status ?? .shared
        self.readChatConfig = readChatConfig
        self.ensureHost = ensureHost
        self.log = log
        self.sleep = sleep
    }
}

/// One thing sending will do, as a line of text with the names set apart; `help` is the detail for a tooltip.
public struct SendStep: Equatable {
    public enum Part: Hashable { case text(String), code(String) }
    public let icon: AppIcon
    /// What the step does in a few words, over the sentence that tells it.
    public let title: String
    public let parts: [Part]
    public let help: String?
}

/// The parts of a step's sentence: `build` says the sentence with a marker where each of `codes` goes, and the parts are the words between the markers and the
/// names in them, which the view sets apart. A sentence is one copy key, so the names stay arguments of it and the order they come in is the language's.
func sendParts(_ codes: [String], _ build: ([String]) -> String) -> [SendStep.Part] {
    let open: Character = "\u{1}", close: Character = "\u{2}"
    let sentence = build(codes.indices.map { "\(open)\($0)\(close)" })
    var parts: [SendStep.Part] = []
    var words = ""
    var index = sentence.startIndex
    while index < sentence.endIndex {
        let char = sentence[index]
        if char == open, let end = sentence[index...].firstIndex(of: close), let number = Int(sentence[sentence.index(after: index)..<end]), codes.indices.contains(number) {
            if words.isEmpty == false { parts.append(.text(words)) }
            words = ""
            parts.append(.code(codes[number]))
            index = sentence.index(after: end)
        } else {
            words.append(char)
            index = sentence.index(after: index)
        }
    }
    if words.isEmpty == false { parts.append(.text(words)) }
    return parts
}
