import CoreGraphics
import Foundation
import Observation

// The Projects page's list (docs/specs/projects.md): one row for each entry of `projects.json`: the rules over the rows.
// The model that keeps the rows in step with the file is `ProjectsModel.swift`, a row `ProjectRow.swift`, the names and tags `ProjectNaming.swift`.
// The remote is read from the repository each time and is never stored (docs/adr/0041).

/// A row for each entry, in the file's order; `remote` says the GitHub `owner/name` of a folder, if any, `exists` whether the folder is there and `git` whether it is a repository.
public func projectRows(
    _ entries: [ProjectEntry], remote: (String) -> String? = originRepo(ofFolder:), exists: (String) -> Bool = projectFolderExists,
    git: (String) -> Bool = isGitRepository
) -> [ProjectRow] {
    entries.map {
        ProjectRow(
            path: $0.path,
            name: $0.name ?? projectFolderName($0.path),
            customName: $0.name,
            repo: remote($0.path),
            pinned: $0.pinned,
            hidden: $0.hidden,
            status: exists($0.path) ? .ready : .notFound,
            origin: $0.origin,
            tags: $0.tags,
            iconColor: $0.iconColor.flatMap(ProjectColor.init(rawValue:)),
            iconMark: $0.iconMark.flatMap(AppIcon.init(rawValue:)),
            iconImage: $0.iconImage,
            actions: $0.actions,
            isGit: git($0.path),
            defaults: $0.defaults
        )
    }
}

/// `rows` with `lastActive` set to the latest `updatedAt` among the `sessions` whose base folder is the project's folder, written any way (`~`, a trailing slash,
/// a symlink); nil for a project no session worked in. Derived each time and never written to `projects.json`.
public func projectsWithLastActive(_ rows: [ProjectRow], sessions: [SessionRow]) -> [ProjectRow] {
    var latest: [String: Date] = [:]
    for session in sessions {
        let key = normalizedFolder(session.base)
        if let known = latest[key], known >= session.updatedAt { continue }
        latest[key] = session.updatedAt
    }
    return rows.map { row in
        var row = row
        row.lastActive = latest[normalizedFolder(row.path)]
        return row
    }
}

/// `rows` with `watched` set for those whose repository is in `repos` (the engine config's list, as it is read), compared as GitHub does, ignoring case.
/// An unreadable config (`repos` nil) watches nothing.
public func projectsWithWatched(_ rows: [ProjectRow], repos: [String]?) -> [ProjectRow] {
    rows.map { row in
        var row = row
        row.watched = row.repo.map { isWatched($0, in: repos ?? []) } ?? false
        return row
    }
}

/// What the Projects list is ordered by: the name, when a session last worked in the project, or what it takes on disk.
public enum ProjectSortKey: Equatable, Hashable, Sendable {
    case name
    case lastActive
    case disk
}

/// The order of the Projects list; the pinned come first whatever it is. Name goes A to Z, Last active most recent first and Disk biggest first until the same title is clicked again.
public struct ProjectOrder: Equatable, Sendable {
    public var key: ProjectSortKey
    public var ascending: Bool

    public init(key: ProjectSortKey = .name, ascending: Bool = true) {
        self.key = key
        self.ascending = ascending
    }

    /// The order after a click on the title of `key`: the same key reverses, another starts in its natural direction.
    public func clicked(_ key: ProjectSortKey) -> ProjectOrder {
        self.key == key ? ProjectOrder(key: key, ascending: ascending == false) : ProjectOrder(key: key, ascending: key == .name)
    }
}

/// What narrows the Projects list: everything, one tag in use, projects with no GitHub remote, or the hidden ones.
public enum ProjectFilter: Equatable, Hashable, Sendable {
    case all
    case tag(String)
    case localOnly
    /// Only the projects Carrier watches.
    case watched
    /// Only the projects left out of the sheet New session opens.
    case hidden
}

/// How the Projects list groups its rows.
public enum ProjectGrouping: String, CaseIterable, Equatable, Hashable, Sendable {
    case none
    case tag
    /// Under Watching and Not watched, the words of the Carrier column.
    case carrier

    public var title: String {
        switch self {
        case .none: "None"
        case .tag: "Tag"
        case .carrier: "Carrier"
        }
    }
}

/// Which of the Projects list's secondary columns fit: the Project column keeps `project` points and the others give way, Tags first and then Carrier, so a
/// project's name is never squeezed out by columns of fixed width. Last active and Disk (the sortable ones) always stay. `contentWidth` is the width inside the card.
public struct ProjectColumns: Equatable, Sendable {
    public static let project: CGFloat = 150
    public static let tags: CGFloat = 120
    public static let lastActive: CGFloat = 90
    public static let disk: CGFloat = 64
    public static let carrier: CGFloat = 90
    public static let trailing: CGFloat = 34
    public static let gap: CGFloat = 12

    public let showsTags: Bool
    public let showsCarrier: Bool

    public init(contentWidth: CGFloat) {
        func needed(_ widths: [CGFloat]) -> CGFloat { widths.reduce(0, +) + Self.gap * CGFloat(widths.count - 1) }
        let base = [Self.project, Self.lastActive, Self.disk, Self.trailing]
        showsCarrier = contentWidth >= needed(base + [Self.carrier])
        showsTags = contentWidth >= needed(base + [Self.carrier, Self.tags])
    }
}

/// One group of the Projects list (`title` is nil when ungrouped).
public struct ProjectGroup: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String?
    public let rows: [ProjectRow]

    public init(id: String, title: String?, rows: [ProjectRow]) {
        self.id = id
        self.title = title
        self.rows = rows
    }
}

/// All distinct tags across `rows`, sorted by name ignoring case.
public func projectTagsInUse(_ rows: [ProjectRow]) -> [String] {
    Array(Set(rows.flatMap(\.tags))).sorted { a, b in
        let cmp = a.localizedCaseInsensitiveCompare(b)
        return cmp == .orderedSame ? a < b : cmp == .orderedAscending
    }
}

/// Filters `rows` by `query` (name, remote or tag) and `filter`, orders pinned first then by `order` (a project no session worked in, or never measured, goes last by
/// last activity or disk, either way), and groups by `groupBy` (`none`; `tag` under each project's first tag and `"untagged"` when it has none; or `carrier` under
/// "Watching" then "Not watched", leaving out the one with no rows). Returns empty when nothing matches.
public func projectList(
    _ rows: [ProjectRow],
    query: String = "",
    filter: ProjectFilter = .all,
    groupBy: ProjectGrouping = .none,
    order: ProjectOrder = ProjectOrder()
) -> [ProjectGroup] {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let matched = rows.filter { row in
        if needle.isEmpty == false {
            let hits = row.name.localizedCaseInsensitiveContains(needle)
                || (row.repo?.localizedCaseInsensitiveContains(needle) == true)
                || row.tags.contains { $0.localizedCaseInsensitiveContains(needle) }
            if hits == false { return false }
        }
        switch filter {
        case .all: return true
        case .tag(let tag): return row.tags.contains(tag)
        case .localOnly: return row.repo == nil
        case .watched: return row.watched
        case .hidden: return row.hidden
        }
    }
    guard matched.isEmpty == false else { return [] }
    func ordered(_ items: [ProjectRow]) -> [ProjectRow] {
        items.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            if order.key != .name {
                let metric: (ProjectRow) -> Double? = { order.key == .disk ? $0.diskBytes.map(Double.init) : $0.lastActive?.timeIntervalSince1970 }
                switch (metric(a), metric(b)) {
                case (nil, nil): break
                case (nil, _): return false
                case (_, nil): return true
                case (let x?, let y?): if x != y { return order.ascending ? x < y : x > y }
                }
            }
            let cmp = a.name.localizedCaseInsensitiveCompare(b.name)
            if cmp != .orderedSame { return (cmp == .orderedAscending) == (order.key != .name || order.ascending) }
            return a.path < b.path
        }
    }
    switch groupBy {
    case .none:
        return [ProjectGroup(id: "all", title: nil, rows: ordered(matched))]
    case .tag:
        var byTag: [String: [ProjectRow]] = [:]
        var untagged: [ProjectRow] = []
        for row in matched {
            if let first = row.tags.first {
                byTag[first, default: []].append(row)
            } else {
                untagged.append(row)
            }
        }
        let sortedTags = byTag.keys.sorted { a, b in
            let cmp = a.localizedCaseInsensitiveCompare(b)
            return cmp == .orderedSame ? a < b : cmp == .orderedAscending
        }
        var groups = sortedTags.map { tag in
            ProjectGroup(id: "tag:\(tag)", title: tag, rows: ordered(byTag[tag]!))
        }
        if untagged.isEmpty == false {
            groups.append(ProjectGroup(id: "untagged", title: "untagged", rows: ordered(untagged)))
        }
        return groups
    case .carrier:
        return [(true, "Watching"), (false, "Not watched")].compactMap { watched, title in
            let rows = matched.filter { $0.watched == watched }
            return rows.isEmpty ? nil : ProjectGroup(id: "carrier:\(watched)", title: title, rows: ordered(rows))
        }
    }
}

extension ProjectsProblem {
    /// The problem as the page says it: the file, the field and what is wrong with it.
    public var text: String { path == "(file)" || path == "(root)" ? "projects.json \(message)" : "projects.json: \(path) \(message)" }
}

/// What the Remove question says: only the entry goes, and everything else stays where it is.
public let projectRemovalWords = "Its folder and its worktrees stay where they are, and so do its sessions. If Carrier watches it, that stays as it is."
