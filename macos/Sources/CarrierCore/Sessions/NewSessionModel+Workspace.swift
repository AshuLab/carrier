import Foundation
import Observation

extension NewSessionModel {
    /// Chooses the workspace and asks the host what it is; the worktree choice starts over (a new folder has other branches and names).
    public func choose(folder path: String) async {
        projects?.reload()
        reset(folder: path)
        await read(path)
    }

    func read(_ path: String) async {
        do {
            let info = try await host.workspace(path)
            guard folder == path else { return }
            workspace = info
            await openWhereSettingsSays()
            guard folder == path else { return }
            // the branches are on screen from what is on disk; the fetch runs behind them and the picker is current when it ends
            if hostFetchesIfStale, toClone == false, info.hasOrigin { refresh = Task { if Task.isCancelled == false { await fetch(whenChosen: true) } } }
        } catch {
            guard folder == path else { return }
            // the draft still works in the base folder: the host refuses the same folder at `open`, in words
            workspaceProblem = report(error, "read the workspace").text
        }
    }

    /// What a new session starts with: the project's agent with its model, reasoning and access when it names an agent (its access over the one
    /// of Settings > Sessions, which any provider that lists those options takes), else what Settings > Sessions says.
    func startForNewSession() -> NewSessionStart {
        let global = start()
        guard let agent = projectDefaults.agent else { return global }
        return NewSessionStart(
            agent: agent, model: projectDefaults.model ?? "", effort: projectDefaults.effort ?? "",
            access: global.access.merging(projectDefaults.access) { _, project in project }
        )
    }

    /// A draft whose folder offers a worktree opens in one when the project, else Settings > Sessions, says so; one that offers none stays on the base folder.
    /// The project's agent and base branch are filled first; an agent that cannot work, or a branch the folder does not have, is left as it was.
    func openWhereSettingsSays() async {
        if let wanted = projectDefaults.agent, agents.contains(where: { $0.name == wanted && $0.available }) {
            // the project's model, reasoning and access go with its agent, also when the draft is on that agent already
            agent = wanted
            optionsAgent = nil
            await loadOptions()
        }
        if let base = projectDefaults.baseBranch, workspace?.branches.contains(where: { $0.name == base || $0.name == "origin/" + base }) == true { picked = base }
        if (projectDefaults.workIn ?? workIn()) == .newWorktree { await useWorktree(true) }
    }

    /// Waits for the fetch that choosing a project started in the background, if one is running.
    public func refreshed() async { await refresh?.value }

    func reset(folder path: String?) {
        fetchRuns += 1
        refresh?.cancel()
        refresh = nil
        fetching = false
        unreachable = false
        folder = path
        projectDefaults = path.flatMap { path in projects?.rows.first { isSameFolder($0.path, path) }?.defaults } ?? ProjectDefaults()
        addProjectProblem = nil
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
        chosenStart = nil
        settingStart = worktreeStart(chatJSON: (try? readChatConfig()) ?? nil)
    }

    /// The branch the worktree starts from, nil when none is known and the person is asked.
    public var startBranch: String? { picked ?? workspace.flatMap(defaultStartBranch) }

    public func choose(startBranch branch: String) { picked = branch }

    /// Where the worktree is cut from: the branch and the side of it, nil while no branch is known.
    public var startPoint: StartPoint? {
        workspace.flatMap { CarrierCore.startPoint(picked: picked, in: $0, choice: chosenStart, setting: settingStart, cloned: toClone) }
    }

    /// Whether the branch picker of a worktree has the Remote and Local tabs: not for a repository that is not on this Mac yet.
    public var hasStartTabs: Bool { toClone == false }

    /// The tab the picker is on: the one the person left it on, else the one `worktreeStart` says.
    public var startTab: WorktreeStart { chosenStart ?? settingStart }

    /// The tab the person moved to is the session's choice, sent as `startFrom`; the setting is not written.
    public func choose(startTab tab: WorktreeStart) { chosenStart = tab }

    /// A row of a tab: the branch by its bare name (the Remote tab lists `origin/<name>`), on the side of the tab.
    public func choose(startBranch branch: String, on tab: WorktreeStart) {
        picked = tab == .remote && branch.hasPrefix("origin/") ? String(branch.dropFirst("origin/".count)) : branch
        chosenStart = tab
    }

    public var sentence: String {
        return workSentence(folder: folder, workspace: workspace, worktree: worktree ? (worktreeName, startPoint?.ref) : nil, gitMissing: gitMissing)
    }

    /// The branch the folder will be switched to when the message is sent: the person picked one other than the checked-out one and
    /// asked for no worktree (a worktree is cut from the pick and changes no folder). Nil when the folder keeps its branch.
    public var branchChange: (from: String, to: String)? {
        guard worktree == false, gitMissing == false, let workspace, workspace.git, workspace.bare == false, let to = picked, to != workspace.branch else { return nil }
        return (workspace.branch ?? "detached HEAD", to)
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
    public func picker(query: String, now: Date = Date()) -> BranchPicker? { workspace.map { branchPicker($0, query: query, now: now, unreachable: unreachable) } }

    /// What the picker's summary warns of under the "from" chip: the branch is behind (Local) or has commits not pushed (Remote).
    public var startWarning: String? { CarrierCore.startWarning(startPoint, in: workspace) }

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
            nameState = .problem(report(error, "suggest a name").text)
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
            nameState = .problem(report(error, "check the name").text)
        }
    }

    /// Fetch now: the host fetches `origin` and answers what the folder is after it, with the remote branches and the time of the fetch.
    public func fetchNow() async { await fetch(whenChosen: false) }

    /// One fetch of the folder's `origin`. `whenChosen` is the one choosing a project starts: it asks the host to skip the git call within its
    /// freshness window, and one that cannot reach the remote is only `unreachable`, with no error. Fetch now never skips and says why it failed.
    func fetch(whenChosen: Bool) async {
        guard let path = folder, fetching == false, toClone == false else { return }
        fetchRuns += 1
        let run = fetchRuns
        fetching = true
        fetchProblem = nil
        defer { if run == fetchRuns { fetching = false } }
        do {
            let info = try await host.fetch(path, ifStale: whenChosen)
            guard run == fetchRuns else { return }
            workspace = info
            unreachable = false
        } catch {
            guard run == fetchRuns else { return }
            if whenChosen {
                unreachable = true
                _ = report(error, "fetch on choosing")
            } else {
                fetchProblem = report(error, "fetch").text
            }
        }
    }
}
