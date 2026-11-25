import Foundation

/// Everything the sheet draws for a given mode, query, recent folders and projects.
public struct ProjectSheetState: Equatable, Sendable {
    public let mode: ProjectSheetMode
    public let query: String
    public let sections: [ProjectSheetSection]
    /// The host's words when the person's repositories could not be listed, for an orange line above the results.
    public var notice: String?

    /// All results in display order (for keyboard navigation).
    public var items: [ProjectSheetResult] { sections.flatMap(\.items) }
    /// The first result, which Return activates when no later result was moved to.
    public var firstResult: ProjectSheetResult? { items.first }
}

/// Computes the sheet's sections and rows from `mode`, `query`, `recent` and `projects`.
public func projectSheetState(
    mode: ProjectSheetMode,
    query: String,
    recent: [RecentFolder],
    projects: [ProjectRow],
    github: ProjectSheetGithub? = nil,
    home: String = NSHomeDirectory(),
    bundle: Bundle? = nil,
    locale: Locale = .current
) -> ProjectSheetState {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

    // Deduplicate recent folders by resolved path, keeping newest order.
    var uniqueRecent: [RecentFolder] = []
    for folder in recent {
        guard uniqueRecent.contains(where: { isSameSheetFolder($0.path, folder.path, home: home) }) == false else { continue }
        uniqueRecent.append(folder)
    }

    // Recent folders that are not already projects.
    let suggestions = uniqueRecent.filter { folder in
        projects.contains(where: { isSameSheetFolder($0.path, folder.path, home: home) }) == false
    }

    func suggestedResult(_ folder: RecentFolder) -> ProjectSheetResult {
        ProjectSheetResult(
            id: "suggested:\(folder.path)",
            kind: .suggestedFolder(folder),
            title: folder.name,
            detail: abbreviatedSheetPath(folder.path, home: home),
            actionTitle: mode.folderActionTitle(bundle: bundle, locale: locale),
            tile: projectTile(name: folder.name, colorKey: projectColorKey(folder.path))
        )
    }

    func existingResult(_ project: ProjectRow) -> ProjectSheetResult {
        ProjectSheetResult(
            id: "existing:\(project.path)",
            kind: .existingProject(project),
            title: project.name,
            detail: mode.includesExistingProjects ? abbreviatedSheetPath(project.path, home: home) : mode.existingDetail(bundle: bundle, locale: locale),
            actionTitle: mode.existingActionTitle(bundle: bundle, locale: locale),
            tile: project.tile
        )
    }

    func projectOfRepo(_ repo: String) -> ProjectRow? { projects.first { $0.repo?.lowercased() == repo.lowercased() } }

    /// The row of a repository to clone, or "Already a project · Open" for one that is. `listed` is what the person's listing says of it, when it does.
    func repoResult(_ repo: String, listed: AvailableRepo?) -> ProjectSheetResult? {
        guard let github else { return nil }
        if let existing = projectOfRepo(repo) { return existingResult(existing) }
        let key = repo.lowercased()
        let chosen = github.chosenParents[key]
        let parent = chosen ?? github.defaultParent
        var problem: String?
        if github.canClone == false {
            problem = Refusal.projectsNeedNewerHost.shown(bundle: bundle, locale: locale)
        } else if listed == nil {
            switch github.visibility[key] {
            case .notVisible: problem = repoNotVisibleLine(bundle: bundle, locale: locale)
            case .problem(let text): problem = text
            case .checking, .visible, nil: break
            }
        }
        return ProjectSheetResult(
            id: "repo:\(key)",
            kind: .cloneRepo(repo: repo, parent: chosen),
            title: listed == nil ? Copy.projectsSheetCloneRepo(repo: repo, bundle: bundle, locale: locale) : repo,
            detail: listed?.about ?? "",
            actionTitle: mode.repoActionTitle(bundle: bundle, locale: locale),
            tile: projectTile(name: repo.split(separator: "/").last.map(String.init) ?? repo, colorKey: repo),
            chip: listed?.isPrivate == true ? Copy.projectsSheetPrivate(bundle: bundle, locale: locale) : nil,
            pushed: pushedLine(listed?.pushedAt, now: github.now, bundle: bundle, locale: locale),
            problem: problem,
            destination: ProjectSheetDestination(
                line: mode.actsAtOnce
                    ? Copy.projectsSheetClonesInto(path: abbreviatedSheetPath(parent + "/" + repo, home: home), bundle: bundle, locale: locale)
                    : Copy.projectsSheetClonedInto(path: abbreviatedSheetPath(parent + "/" + repo, home: home), bundle: bundle, locale: locale),
                parent: parent, isChosen: chosen != nil, canChoose: mode.actsAtOnce
            ),
            watch: mode.actsAtOnce ? nil : ProjectSheetWatch(problem: github.watched.flatMap { repoProblem(repo, joining: $0) })
        )
    }

    /// The person's repositories that contain `needle` in their name or description, other than the one that was pasted (it is the first result).
    func matchingRepos(_ needle: String, except pasted: String?) -> [ProjectSheetResult] {
        (github?.repos ?? []).filter {
            $0.name.lowercased() != pasted
                && (needle.isEmpty || $0.name.localizedCaseInsensitiveContains(needle) || ($0.about?.localizedCaseInsensitiveContains(needle) ?? false))
        }.compactMap { repoResult($0.name, listed: $0) }
    }

    var sections: [ProjectSheetSection] = []
    var notice: String?

    if let typedPath = expandedSheetPath(trimmed, home: home) {
        let pathResult: ProjectSheetResult
        if let existing = projects.first(where: { isSameSheetFolder($0.path, typedPath, home: home) }) {
            pathResult = existingResult(existing)
        } else {
            let folderName = projectFolderName(typedPath)
            let displayName = folderName.isEmpty ? typedPath : folderName
            pathResult = ProjectSheetResult(
                id: "path:\(typedPath)",
                kind: .addPath(path: typedPath),
                title: mode.addFolderTitle(bundle: bundle, locale: locale),
                detail: abbreviatedSheetPath(typedPath, home: home),
                actionTitle: mode.folderActionTitle(bundle: bundle, locale: locale),
                tile: projectTile(name: displayName, colorKey: projectColorKey(typedPath))
            )
        }
        sections.append(ProjectSheetSection(id: "path", title: nil, items: [pathResult]))

        let matchingSuggested = suggestions.filter { folder in
            isSameSheetFolder(folder.path, typedPath, home: home) == false
                && (folder.name.localizedCaseInsensitiveContains(trimmed)
                    || folder.path.localizedCaseInsensitiveContains(trimmed)
                    || abbreviatedSheetPath(folder.path, home: home).localizedCaseInsensitiveContains(trimmed))
        }
        if matchingSuggested.isEmpty == false {
            sections.append(ProjectSheetSection(id: "suggested", title: Copy.projectsSheetSuggested(bundle: bundle, locale: locale), items: matchingSuggested.map(suggestedResult)))
        }
    } else {
        if mode.includesExistingProjects {
            let shown = projects.filter { $0.hidden == false }
            let matchingProjects = trimmed.isEmpty ? shown : shown.filter {
                $0.name.localizedCaseInsensitiveContains(trimmed)
                    || $0.path.localizedCaseInsensitiveContains(trimmed)
                    || ($0.repo?.localizedCaseInsensitiveContains(trimmed) ?? false)
            }
            if matchingProjects.isEmpty == false {
                sections.append(ProjectSheetSection(id: "projects", title: Copy.projectsSheetProjects(bundle: bundle, locale: locale), items: matchingProjects.map(existingResult)))
            }
        }

        // a pasted GitHub address, or `owner/name`: the repository itself first
        var reference: String?
        if let github, let repo = repoReference(trimmed) {
            let listed = github.repos.first { $0.name.lowercased() == repo.lowercased() }
            let name = listed?.name ?? repo
            if let result = repoResult(name, listed: listed) {
                sections.append(ProjectSheetSection(id: "path", title: nil, items: [result]))
                reference = name.lowercased()
            }
        }

        let matchingSuggested = trimmed.isEmpty ? suggestions : suggestions.filter { folder in
            folder.name.localizedCaseInsensitiveContains(trimmed)
                || folder.path.localizedCaseInsensitiveContains(trimmed)
                || abbreviatedSheetPath(folder.path, home: home).localizedCaseInsensitiveContains(trimmed)
        }
        if matchingSuggested.isEmpty == false {
            sections.append(ProjectSheetSection(id: "suggested", title: Copy.projectsSheetSuggested(bundle: bundle, locale: locale), items: matchingSuggested.map(suggestedResult)))
        }

        let repos = matchingRepos(trimmed, except: reference)
        if repos.isEmpty == false {
            sections.append(ProjectSheetSection(id: "repos", title: Copy.projectsSheetYourRepositories(bundle: bundle, locale: locale), items: repos))
        }
        notice = github?.listingProblem
    }

    var state = ProjectSheetState(mode: mode, query: query, sections: sections)
    state.notice = notice
    return state
}
