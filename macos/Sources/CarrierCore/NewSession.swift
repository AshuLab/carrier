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

/// An entry of the agent chip's menu: one whose binary was not found is listed, disabled, with "not installed".
public struct AgentChoice: Equatable {
    public let name: String
    public let available: Bool
    public var note: String? { available ? nil : "not installed" }
}

public func agentChoices(_ agents: [ChatAgent]) -> [AgentChoice] { agents.map { AgentChoice(name: $0.name, available: $0.found) } }

/// A first message whose send failed after `open` made the session.
public struct FailedFirstSend: Equatable {
    public let text: String
    public let reason: String
}

/// A way into the workspace popover besides the folders it lists. One that is not built, or that the host cannot do, is not in `sources`.
public enum WorkspaceSource: String {
    case localFolder = "Open local folder…"
    case githubURL = "From a GitHub URL…"
}

/// The step of the workspace popover that is showing.
public enum WorkspaceStep: Equatable {
    case menu, url
}

/// The draft: loads what it offers, and `send()` opens the session and then sends the message, in two steps.
@MainActor @Observable public final class NewSessionModel {
    public private(set) var recent: [RecentFolder] = []
    public private(set) var agents: [AgentChoice] = []
    /// The chosen workspace's path, nil until one is chosen.
    public private(set) var folder: String?
    public var agent: String?
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
    /// The `<owner>/<repo>` folders of the projects folder, read from disk each time the popover opens.
    public private(set) var projects: [ProjectFolder] = []
    public private(set) var step = WorkspaceStep.menu
    /// What the URL step was given.
    public var urlText = ""
    /// The repository being cloned, nil when none is.
    public private(set) var cloning: String?
    /// Why the last clone was refused, in the host's words; cleared when the next one starts.
    public private(set) var cloneProblem: String?

    @ObservationIgnored private let host: ChatHost
    @ObservationIgnored private let projectsFolder: () -> String
    @ObservationIgnored private var cloneTask: Task<ClonedRepo, Error>?
    @ObservationIgnored private let ensureHost: @MainActor () async -> Bool
    @ObservationIgnored private let log: (String) -> Void
    @ObservationIgnored private let sleep: (Duration) async throws -> Void
    /// The name the host last vouched for (suggested or checked), so a name it already vouched for is not asked about again.
    @ObservationIgnored private var verifiedName: String?
    /// What a conversation shows when its first message failed to send, by session id, until it takes it.
    @ObservationIgnored private var failedFirstSends: [String: FailedFirstSend] = [:]

    /// `ensureHost` starts the chat host when it is not running (#503) and says whether it answers now.
    /// `sleep` is the wait before a typed name is checked. `projectsFolder` is where the config says the projects folder is.
    public init(
        host: ChatHost, ensureHost: @escaping @MainActor () async -> Bool = { true },
        log: @escaping (String) -> Void = { FileHandle.standardError.write(Data("carrier: \($0)\n".utf8)) },
        sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        projectsFolder: @escaping () -> String = currentProjectsFolder
    ) {
        self.host = host
        self.projectsFolder = projectsFolder
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
        if agents.contains(where: { $0.name == agent && $0.available }) == false { agent = agents.first(where: \.available)?.name }
    }

    private func read() async throws {
        agents = agentChoices(try await host.agents())
        recent = recentFolders(try await host.list(archived: false) + (try await host.list(archived: true)))
        hostClones = try await host.capabilities().contains(.cloneRepo)
    }

    /// The sources the popover lists under the folders.
    public var sources: [WorkspaceSource] { hostClones ? [.localFolder, .githubURL] : [.localFolder] }

    /// Where the footer says the projects folder is.
    public var projectsPath: String { projectsFolder() }

    /// The popover opens on the menu with the projects folder read again; one that is cloning stays on the step that shows it.
    public func openPicker() {
        projects = projectFolders(in: projectsFolder())
        guard cloning == nil else { return }
        step = .menu
        cloneProblem = nil
    }

    public func show(_ next: WorkspaceStep) {
        guard cloning == nil else { return }
        step = next
        cloneProblem = nil
    }

    /// The repository being cloned without its owner: what the chip says while it runs.
    public var cloningName: String? { cloning.flatMap { $0.split(separator: "/").last.map(String.init) } }

    /// The repository the URL step's text names.
    public var reference: String? { repoReference(urlText) }

    /// A repository already among the projects folder's folders is fetched, not cloned again.
    public var alreadyThere: Bool { reference.map { name in projects.contains { $0.name.lowercased() == name.lowercased() } } ?? false }

    public var cloneButton: String { cloneProblem != nil ? "Try again" : alreadyThere ? "Update and use" : "Clone and use" }

    /// "Clone and use" stays off until the text is one repository, and while a clone runs.
    public var canCloneNow: Bool { reference != nil && cloning == nil }

    /// Clones (or fetches) the repository of the URL step and chooses its folder as the workspace; true when it did. The draft has no
    /// workspace while it runs and when it fails, so the chip stays orange; the refusal is in `cloneProblem`.
    public func cloneAndUse() async -> Bool {
        guard let repo = reference, cloning == nil else { return false }
        reset(folder: nil)
        cloning = repo
        cloneProblem = nil
        step = .url
        let task = Task { [host] in try await host.cloneRepo(repo) }
        cloneTask = task
        do {
            let cloned = try await task.value
            guard cloneTask == task else { return false }
            cloning = nil
            cloneTask = nil
            urlText = ""
            await choose(folder: cloned.folder)
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
        if let cloning, let name = cloningName { return "Work in \(name) Cloning \(cloning)…" }
        return workSentence(folder: folder, workspace: workspace, worktree: worktree ? (worktreeName, startBranch) : nil)
    }

    /// The line under the sentence: the uncommitted files of the base folder, which a worktree would keep out of the agent's way.
    public var warning: String? { worktree ? nil : workspace.flatMap(uncommittedWarning) }

    public var offersWorktree: Bool { workspace?.offersWorktree == true }

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
        guard folder != nil, agent != nil, sending == false, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return false }
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
            id = try await host.open(agent: agent, folder: folder, worktree: worktreeRequest)
        } catch {
            refusal = report(error, "open the session")
            return nil
        }
        do {
            try await host.send(id, message)
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
