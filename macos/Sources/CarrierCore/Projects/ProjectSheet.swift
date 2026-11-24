import Foundation

// The shared Add project / workspace sheet's pure model (docs/specs/projects.md, "Add project"):
// one function of the mode, the query, the recent folders and the projects.

/// How the shared sheet acts: in Settings a choice acts at once; in New session it only fills the plan, and nothing is cloned or written until the
/// first message is sent (docs/adr/0018).
public enum ProjectSheetMode: Equatable, Sendable {
    case settings
    case newSession

    public var title: String {
        switch self {
        case .settings: "Add project"
        case .newSession: "Choose where to work"
        }
    }

    public var subtitle: String {
        switch self {
        case .settings: "Paste a GitHub address, search your repositories, or choose a folder on this Mac."
        case .newSession: "Pick a project, paste a GitHub address, or choose a folder. Nothing is cloned or made until you send the first message."
        }
    }

    public var fieldPlaceholder: String { "Paste a GitHub address, search, or type a path…" }

    /// Whether a choice acts at once (Settings) or only fills the plan (New session).
    public var actsAtOnce: Bool { self == .settings }

    public var folderActionTitle: String { actsAtOnce ? "Add" : "Use" }

    public var addFolderTitle: String { actsAtOnce ? "Add folder" : "Use folder" }

    public var existingDetail: String { "Already a project · Open" }

    public var existingActionTitle: String { actsAtOnce ? "Open" : "Use" }

    public var repoActionTitle: String { actsAtOnce ? "Clone" : "Use" }

    /// Settings suggests only folders that are not projects; New session lists the projects that are not hidden first.
    public var includesExistingProjects: Bool { actsAtOnce == false }

    public var openPanelPrompt: String { actsAtOnce ? "Add" : "Use" }

    public var openPanelMessage: String { actsAtOnce ? "Choose the folder of a project" : "Choose the folder to work in" }
}

/// One row of the shared sheet.
public struct ProjectSheetResult: Equatable, Identifiable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// A typed path (`~` or `/`) that is not yet a project.
        case addPath(path: String)
        /// A typed path (or listed project) that is already a project.
        case existingProject(ProjectRow)
        /// A recent folder that is not yet a project.
        case suggestedFolder(RecentFolder)
        /// A GitHub repository to clone: `owner/name`, and the parent folder chosen for this clone only (nil: the projects folder, which the host knows).
        case cloneRepo(repo: String, parent: String?)

        /// Whether the result is a GitHub repository (its detail is a description, not a path).
        public var isRepository: Bool {
            if case .cloneRepo = self { return true }
            return false
        }
    }

    public let id: String
    public let kind: Kind
    public let title: String
    public let detail: String
    public let actionTitle: String
    public let tile: ProjectTile
    /// "Private", on a repository that is.
    public var chip: String?
    /// When the repository was last pushed ("pushed 3 d ago"); empty when GitHub gave none.
    public var pushed: String = ""
    /// What is wrong with the result, in the words to show in orange; the result then cannot be acted on.
    public var problem: String?
    /// Where a clone goes, for a repository to clone.
    public var destination: ProjectSheetDestination?
    /// "Let Carrier watch this repo", on a repository to clone in New session only (a choice of the plan, acted on once the first message was prepared).
    public var watch: ProjectSheetWatch?

    public var isEnabled: Bool { problem == nil }

    public var path: String {
        switch kind {
        case .addPath(let path): path
        case .existingProject(let row): row.path
        case .suggestedFolder(let folder): folder.path
        case .cloneRepo(let repo, _): repo
        }
    }
}

/// The watch choice of a repository to clone in New session: nil `problem` means it can be on.
public struct ProjectSheetWatch: Equatable, Sendable {
    /// Why Carrier cannot watch it (already watched, or a folder name another watched repo has), in words.
    public let problem: String?
}

/// Where a repository to clone will be made: the line under it, and whether the person chose a folder for this clone.
public struct ProjectSheetDestination: Equatable, Sendable {
    /// "Clones into ~/Carrier/projects/owner/name" in Settings; "Cloned into ~/Carrier/projects/owner/name when you send the first message" in New session.
    public let line: String
    /// The folder the clone goes in, before `<owner>/<name>`.
    public let parent: String
    /// True when the person chose `parent` for this clone with Choose…; false when it is the default.
    public let isChosen: Bool
    /// Whether Choose… is offered: not in New session, where the host clones into the projects folder when the message is sent.
    public var canChoose = true
}

/// How far the check that the person's login can see a pasted repository got.
public enum RepoCheck: Equatable, Sendable {
    case checking
    case visible
    /// GitHub has no such repository for this login.
    case notVisible
    /// The check could not be made (`gh` missing or signed out, no network); the host's own words.
    case problem(String)
}

/// What the sheet says in orange for a repository the login cannot see.
public let repoNotVisibleLine = "Your GitHub login can't see this repository. Check the name, or sign in with another account."

/// Whether a host refusal of `repoBranches` says the repository is not there for this login.
public func isRepoNotVisible(_ refusal: Refusal) -> Bool { refusal.has("github.repoNotFound") }

/// What the sheet knows of GitHub: the person's repositories as the host listed them, what was checked of a pasted one, and where a clone goes.
public struct ProjectSheetGithub: Equatable, Sendable {
    public var repos: [AvailableRepo] = []
    /// The host's own words when the listing could not be read (`gh` missing or signed out, no network); shown in orange.
    public var listingProblem: String?
    /// The projects folder: where a clone goes unless the person chose another for it.
    public var defaultParent: String
    /// The folder chosen with Choose… for one clone, by lower-case `owner/name`.
    public var chosenParents: [String: String] = [:]
    /// What was found out about the repositories that are not in `repos`, by lower-case `owner/name`.
    public var visibility: [String: RepoCheck] = [:]
    /// The `repos` of the engine's config, for the watch choice; nil when the file cannot be read.
    public var watched: [String]?
    /// Whether the host can clone (its hello lists `projects`); when it cannot, a repository says the host is older and to restart it.
    public var canClone = true
    public var now: Date = Date()

    public init(defaultParent: String) { self.defaultParent = defaultParent }
}

/// A named section of the sheet's list (`title` is nil for the top path result).
public struct ProjectSheetSection: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String?
    public let items: [ProjectSheetResult]
}

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

/// Expands a query starting with `~` or `/` into a standardized path; nil when the query is not a path.
public func expandedSheetPath(_ raw: String, home: String = NSHomeDirectory()) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("/") || trimmed.hasPrefix("~") else { return nil }
    let expanded: String
    if trimmed == "~" {
        expanded = home
    } else if trimmed.hasPrefix("~/") {
        expanded = home + String(trimmed.dropFirst())
    } else if trimmed.hasPrefix("~") {
        // e.g. `~otheruser/foo`: let Foundation resolve if valid, else stays relative so folder checks refuse it cleanly
        expanded = (trimmed as NSString).expandingTildeInPath
    } else {
        expanded = trimmed
    }
    guard expanded.hasPrefix("/") else { return expanded }
    return URL(fileURLWithPath: expanded).standardized.path
}

/// Abbreviates `path` with `~` when inside `home`.
public func abbreviatedSheetPath(_ path: String, home: String = NSHomeDirectory()) -> String {
    if path == home { return "~" }
    if path.hasPrefix(home + "/") { return "~" + String(path.dropFirst(home.count)) }
    return path
}

/// Whether two paths refer to the same folder, expanding `~` against `home` and resolving symlinks.
public func isSameSheetFolder(_ a: String, _ b: String, home: String = NSHomeDirectory()) -> Bool {
    func normalize(_ raw: String) -> String {
        let expanded: String
        if raw == "~" {
            expanded = home
        } else if raw.hasPrefix("~/") {
            expanded = home + String(raw.dropFirst())
        } else {
            expanded = (raw as NSString).expandingTildeInPath
        }
        return URL(fileURLWithPath: expanded).resolvingSymlinksInPath().path
    }
    return normalize(a) == normalize(b)
}

/// Distinct base folders of `sessions` (from the main window's session rows), newest first, up to `limit`.
public func recentFolders(from sessions: [SessionRow], limit: Int = 8) -> [RecentFolder] {
    var seen: Set<String> = []
    var folders: [RecentFolder] = []
    for session in sessions.sorted(by: { $0.updatedAt > $1.updatedAt }) {
        let path = session.base
        guard seen.insert(path).inserted else { continue }
        folders.append(RecentFolder(name: URL(fileURLWithPath: path).lastPathComponent, path: path))
        if folders.count == limit { break }
    }
    return folders
}

/// Computes the sheet's sections and rows from `mode`, `query`, `recent` and `projects`.
public func projectSheetState(
    mode: ProjectSheetMode,
    query: String,
    recent: [RecentFolder],
    projects: [ProjectRow],
    github: ProjectSheetGithub? = nil,
    home: String = NSHomeDirectory()
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
            actionTitle: mode.folderActionTitle,
            tile: projectTile(name: folder.name, colorKey: projectColorKey(folder.path))
        )
    }

    func existingResult(_ project: ProjectRow) -> ProjectSheetResult {
        ProjectSheetResult(
            id: "existing:\(project.path)",
            kind: .existingProject(project),
            title: project.name,
            detail: mode.includesExistingProjects ? abbreviatedSheetPath(project.path, home: home) : mode.existingDetail,
            actionTitle: mode.existingActionTitle,
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
            problem = projectsNeedNewerHost
        } else if listed == nil {
            switch github.visibility[key] {
            case .notVisible: problem = repoNotVisibleLine
            case .problem(let text): problem = text
            case .checking, .visible, nil: break
            }
        }
        return ProjectSheetResult(
            id: "repo:\(key)",
            kind: .cloneRepo(repo: repo, parent: chosen),
            title: listed == nil ? "Clone \(repo)" : repo,
            detail: listed?.about ?? "",
            actionTitle: mode.repoActionTitle,
            tile: projectTile(name: repo.split(separator: "/").last.map(String.init) ?? repo, colorKey: repo),
            chip: listed?.isPrivate == true ? "Private" : nil,
            pushed: pushedLine(listed?.pushedAt, now: github.now),
            problem: problem,
            destination: ProjectSheetDestination(
                line: (mode.actsAtOnce ? "Clones into " : "Cloned into ") + abbreviatedSheetPath(parent + "/" + repo, home: home) + (mode.actsAtOnce ? "" : " when you send the first message"),
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
                title: mode.addFolderTitle,
                detail: abbreviatedSheetPath(typedPath, home: home),
                actionTitle: mode.folderActionTitle,
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
            sections.append(ProjectSheetSection(id: "suggested", title: "Suggested folders", items: matchingSuggested.map(suggestedResult)))
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
                sections.append(ProjectSheetSection(id: "projects", title: "Projects", items: matchingProjects.map(existingResult)))
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
            sections.append(ProjectSheetSection(id: "suggested", title: "Suggested folders", items: matchingSuggested.map(suggestedResult)))
        }

        let repos = matchingRepos(trimmed, except: reference)
        if repos.isEmpty == false {
            sections.append(ProjectSheetSection(id: "repos", title: "Your repositories", items: repos))
        }
        notice = github?.listingProblem
    }

    var state = ProjectSheetState(mode: mode, query: query, sections: sections)
    state.notice = notice
    return state
}

/// The sheet's New project… form (docs/specs/projects.md, Scope 5): a name, and where it is made: `<parent>/local/<name>`, with the projects folder as the
/// parent unless the person chose another for this one project.
public struct NewProjectForm: Equatable, Sendable {
    public var name = ""
    /// The folder chosen with Choose… for this project only; nil keeps `defaultParent`.
    public var chosenParent: String?
    /// The projects folder.
    public let defaultParent: String

    public init(defaultParent: String) { self.defaultParent = defaultParent }

    public var parent: String { chosenParent ?? defaultParent }
    /// Where the project is made; `<name>` stands for the name until one is typed.
    public var folder: String { parent + "/local/" + (name.isEmpty ? "<name>" : name) }
    public func destinationLine(home: String = NSHomeDirectory()) -> String { "Creates " + abbreviatedSheetPath(folder, home: home) }

    /// Why Create cannot go ahead, in the words to show in orange: the name is not a plain folder name (the host's pattern), or something is already at its
    /// folder (`taken` says whether a folder or a project is). nil while nothing is typed and when the name can be used; the host checks both again.
    public func problem(taken: (String) -> Bool) -> String? {
        guard name.isEmpty == false else { return nil }
        if let refusal = projectNameProblem(name) { return refusal.text }
        return taken(folder) ? "\(name) is already a project; choose another name" : nil
    }

    public func canCreate(taken: (String) -> Bool) -> Bool { name.isEmpty == false && problem(taken: taken) == nil }
}

/// What dropping one or more paths onto the sheet in Settings did.
public enum ProjectDropOutcome: Equatable, Sendable {
    /// One folder was added or already existed: close the sheet and open its page.
    case open(String)
    /// Multiple folders were added without refusal: close the sheet and show the list.
    case addedMultiple
    /// One or more items were refused (with the reason in words); keep the sheet open.
    case refused(String)
}

/// Adds each unique dropped path through `addFolder`, returning whether to open, close, or show a refusal.
@MainActor
public func applyDroppedProjectPaths(_ paths: [String], addFolder: (String) async -> (outcome: ProjectAdd?, error: String?)) async -> ProjectDropOutcome {
    var unique: [String] = []
    for path in paths {
        guard unique.contains(where: { isSameSheetFolder($0, path) }) == false else { continue }
        unique.append(path)
    }
    guard unique.isEmpty == false else { return .refused("Nothing could be read from the drop") }

    var addedPaths: [String] = []
    var refusals: [(path: String, reason: String)] = []
    for path in unique {
        let result = await addFolder(path)
        switch result.outcome {
        case .added(let p), .existing(let p):
            addedPaths.append(p)
        case nil:
            refusals.append((path, result.error ?? "That folder cannot be added"))
        }
    }

    if refusals.isEmpty == false {
        let message: String
        if unique.count == 1 {
            message = refusals[0].reason
        } else {
            message = refusals.map { "\((($0.path as NSString).lastPathComponent)): \($0.reason)" }.joined(separator: "\n")
        }
        return .refused(message)
    }

    if addedPaths.count == 1 { return .open(addedPaths[0]) }
    return .addedMultiple
}
