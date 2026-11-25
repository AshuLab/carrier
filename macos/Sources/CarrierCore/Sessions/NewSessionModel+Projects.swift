import Foundation
import Observation

extension NewSessionModel {
    func refreshWatched() {
        projectsPath = projectsFolder()
        watched = readConfig().flatMap { configRepoNames(json: $0) }
    }

    /// Chooses what the sheet's `result` stands for: only the plan is filled, nothing is cloned, made or written until the first message is sent.
    /// A project or a folder is a folder of the plan, a repository to clone is a repository, and a project listed by its repository is its folder.
    public func choose(_ result: ProjectSheetResult) async {
        switch result.kind {
        case .addPath(let path): await choose(folder: path)
        case .suggestedFolder(let folder): await choose(folder: folder.path)
        case .existingProject(let project): await choose(folder: project.path)
        case .cloneRepo(let repo, _): await choose(repo: repo)
        }
    }

    /// Why the box cannot be on for `repo` (already watched, or a folder name another watched repo has); nil when it can.
    public func watchProblem(for repo: String) -> String? { watched.flatMap { repoProblem(repo, joining: $0) } }

    /// Whether the repository chosen will be watched: the person's box, unless it cannot be on for it.
    public var watching: Bool { repo.map { watch && watchProblem(for: $0) == nil } ?? false }

    /// Chooses `owner/name` as the workspace. One already in the projects folder is read locally, as a folder; one that is not on this Mac has its branches
    /// read from GitHub with the person's login, no uncommitted changes and a worktree whose name is generated at once, the host checking it when the message is sent.
    public func choose(repo name: String) async {
        guard isRepoName(name) else { return }
        refreshWatched()
        let path = "\(projectsPath)/\(name)"
        let there = FileManager.default.fileExists(atPath: path)
        reset(folder: path)
        repo = name
        if there { return await read(path) }
        toClone = true
        loadingBranches = true
        defer { if folder == path { loadingBranches = false } }
        do {
            let listed = try await host.repoBranches(name)
            guard folder == path else { return }
            let names = listed.branches.contains(listed.defaultBranch) ? listed.branches : [listed.defaultBranch] + listed.branches
            workspace = WorkspaceInfo(folder: path, branch: listed.defaultBranch, defaultBranch: listed.defaultBranch, branches: names.map { .init(name: $0, remote: false) })
            branchesPartial = listed.hasMore
            await openWhereSettingsSays()
        } catch {
            guard folder == path else { return }
            // the draft still works: the repository is cloned on its default branch, with no worktree to offer
            workspaceProblem = report(error, "list the branches of \(name)").shown(bundle: bundle, locale: locale)
        }
    }

    /// Chooses a new project as the workspace: only the plan is filled, the host makes the folder and runs `git init` when the message is
    /// sent. A project has no commits, so the draft offers neither a branch nor a worktree.
    public func choose(newProject name: String) {
        let path = "\(projectsPath)/local/\(name)"
        reset(folder: path)
        newProject = name
        workspace = WorkspaceInfo(folder: path)
    }

    /// Whether the draft offers Add as project: the workspace is a folder the host read (not a repository, nor a new project, which the host registers
    /// itself) that is not one of the person's projects. It goes once the folder is.
    public var offersAddAsProject: Bool {
        guard let projects, let folder, workspace != nil, repo == nil, newProject == nil else { return false }
        return projects.rows.contains { isSameFolder($0.path, folder) } == false
    }

    /// Adds the folder as a project of origin `added`, with the request the Projects page sends; `addProjectProblem` says why when it could not.
    public func addAsProject() async {
        guard offersAddAsProject, let folder, let projects else { return }
        addProjectProblem = await projects.add(folder: folder) == nil ? projects.failure ?? projects.problems.first?.text(bundle: bundle, locale: locale) ?? Copy.projectsDropCannotAdd(bundle: bundle, locale: locale) : nil
    }

    /// The line that says beforehand what sending will make, nil unless the workspace is a new project.
    public var projectNote: String? {
        guard newProject != nil, let folder else { return nil }
        return Copy.newSessionProjectNote(folder: folder, bundle: bundle, locale: locale)
    }

    /// What sending will do, in order, for the block under the box: download or update the repository, switch the folder's branch, and cut the worktree's branch. Empty
    /// when sending only starts the agent in the folder.
    public var sendSteps: [SendStep] {
        var steps: [SendStep] = []
        if let repo, let folder {
            if toClone {
                let projects = (projectsPath as NSString).abbreviatingWithTildeInPath
                let parts = sendParts([repo, projects]) { Copy.newSessionStepDownloadText(repo: $0[0], folder: $0[1], bundle: bundle, locale: locale) }
                steps.append(SendStep(icon: .download, title: Copy.newSessionStepDownload(bundle: bundle, locale: locale), parts: parts, help: folder))
            } else {
                let parts = sendParts([repo]) { Copy.newSessionStepUpdateText(repo: $0[0], bundle: bundle, locale: locale) }
                steps.append(SendStep(icon: .refresh, title: Copy.newSessionStepUpdate(bundle: bundle, locale: locale), parts: parts, help: folder))
            }
        }
        // a fresh clone follows the pick, so only a folder that is already there is switched
        if toClone == false, let change = branchChange {
            let parts = sendParts([change.from, change.to]) { Copy.newSessionStepBranchChangeText(from: $0[0], to: $0[1], bundle: bundle, locale: locale) }
            steps.append(SendStep(icon: .exchange, title: Copy.newSessionStepBranchChange(bundle: bundle, locale: locale), parts: parts, help: folder))
        }
        if worktree, let point = startPoint {
            // a repository from GitHub already has its own step that fetches; an older host does not fetch for a folder
            if point.side == .remote, hostStarts, repo == nil {
                let parts = sendParts(["origin"]) { Copy.newSessionStepFetchText(remote: $0[0], bundle: bundle, locale: locale) }
                steps.append(SendStep(icon: .download, title: Copy.newSessionStepFetch(ref: point.ref, bundle: bundle, locale: locale), parts: parts, help: folder))
            }
            let name = worktreeBranchPrefix + (worktreeName.isEmpty ? "<name>" : worktreeName)
            let parts = sendParts([name, point.ref]) {
                toClone
                    ? Copy.newSessionStepCreateTextClone(name: $0[0], ref: $0[1], bundle: bundle, locale: locale)
                    : Copy.newSessionStepCreateText(name: $0[0], ref: $0[1], bundle: bundle, locale: locale)
            }
            steps.append(SendStep(icon: .gitBranch, title: Copy.newSessionStepCreate(bundle: bundle, locale: locale), parts: parts, help: nil))
        }
        return steps
    }

    /// Asks the engine to add `repo` to the config's `repos` (the list read just now, so a change of another page is not lost); the engine runs on it at once, so nothing is restarted. What it
    /// came to is the session's `watchNotes`.
    private func addToWatched(_ repo: String, session id: String) async {
        func failed(_ reason: String) { watchNotes[id] = WatchNote(text: Copy.newSessionWatchFailed(repo: repo, reason: reason, bundle: bundle, locale: locale), failed: true) }
        guard let json = readConfig(), let names = configRepoNames(json: json) else {
            return failed(Copy.newSessionWatchConfigUnreadable(bundle: bundle, locale: locale))
        }
        if names.contains(where: { $0.lowercased() == repo.lowercased() }) { return }  // another session of it got there first
        if let problem = reposProblem(names + [repo]) { return failed(problem) }
        do {
            // the engine may take seconds: the page does not wait for it
            let reply = try await send(.watchedRepos(names + [repo]))
            watched = names + [repo]
            status.record(reply.outcome)
            let note = addedRepoNote(repo, outcome: reply.outcome)
            watchNotes[id] = WatchNote(text: note.text, failed: note.failed)
        } catch ControlError.remote(let refusal) {
            failed(refusal.shown(bundle: bundle, locale: locale))
        } catch {
            log("new session: could not change the config: \(error)")
            failed(Copy.newSessionWatchConfigNotSaved(bundle: bundle, locale: locale))
        }
    }

    /// One look at the sessions whose repository waits to be watched: one whose preparation is over (the `message` step is done) adds its
    /// repository, once; one the host no longer lists (cancelled, deleted) or that is still preparing or failed does not, a failed one
    /// waiting for Try again.
    public func settleWatches() async {
        guard pendingWatches.isEmpty == false, let listed = try? await host.list(archived: false) else { return }
        await settle(listed)
    }

    private func settle(_ listed: [ChatSession]) async {
        for (id, repo) in pendingWatches {
            guard let found = listed.first(where: { $0.id == id }) else {
                pendingWatches[id] = nil
                continue
            }
            if found.state != .preparing, found.preparation == nil {
                pendingWatches[id] = nil
                await addToWatched(repo, session: id)
            }
        }
    }

    /// Looks at each list the host's updates bring for as long as a session of a repository to watch is preparing or failed; the host could push the step.
    /// A list read before the session was opened (the one in flight, or the last one given at once) cannot say it is gone, so it is not looked at.
    func keepWatching() {
        guard watchTask == nil else { return }
        let host = host
        watchTask = Task { [weak self] in
            for await update in await host.sessionUpdates() {
                guard let self, self.pendingWatches.isEmpty == false else { break }
                guard update.stale == false, update.readAt >= self.watchSince else { continue }
                await self.settle(update.active)
                if self.pendingWatches.isEmpty { break }
            }
            self?.watchTask = nil
        }
    }
}
