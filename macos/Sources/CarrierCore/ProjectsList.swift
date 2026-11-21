import CoreGraphics
import Foundation
import Observation

// The Projects page's list (docs/specs/projects.md): one row for each entry of `projects.json`, and a model that keeps the rows in step with the file.
// The remote is read from the repository each time and is never stored (docs/adr/0038).

/// `owner/name` of a GitHub remote URL (`git@github.com:o/n.git`, `https://github.com/o/n`, `ssh://git@github.com/o/n.git`); nil for any other host or shape.
public func gitHubRepo(fromRemote remote: String) -> String? {
    let text = remote.trimmingCharacters(in: .whitespaces)
    var path: Substring
    if text.hasPrefix("git@github.com:") {
        path = text.dropFirst("git@github.com:".count)
    } else if let url = URL(string: text), url.host?.lowercased() == "github.com", ["https", "http", "ssh", "git"].contains(url.scheme ?? "") {
        path = url.path.dropFirst()
    } else {
        return nil
    }
    if path.hasSuffix("/") { path = path.dropLast() }
    if path.hasSuffix(".git") { path = path.dropLast(4) }
    let parts = path.split(separator: "/", omittingEmptySubsequences: false)
    return parts.count == 2 && parts.allSatisfy({ $0.isEmpty == false }) ? parts.joined(separator: "/") : nil
}

/// The GitHub `owner/name` of the `origin` remote of the repository at `folder`, read from its `.git/config`; nil when it is not a repository, has no
/// `origin`, or `origin` is not GitHub's. ponytail: a worktree's `.git` is a file, not read; the remote of a linked worktree shows as its path.
public func originRepo(ofFolder folder: String) -> String? {
    let config = (folder as NSString).expandingTildeInPath + "/.git/config"
    guard let text = try? String(contentsOfFile: config, encoding: .utf8) else { return nil }
    var inOrigin = false
    for raw in text.split(whereSeparator: \.isNewline) {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("[") { inOrigin = line.replacingOccurrences(of: " ", with: "") == "[remote\"origin\"]"; continue }
        guard inOrigin, line.hasPrefix("url") else { continue }
        let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count == 2, parts[0] == "url" { return gitHubRepo(fromRemote: parts[1]) }
    }
    return nil
}

/// The folder's own name from a project path (the last path component).
public func projectFolderName(_ path: String) -> String {
    (path as NSString).lastPathComponent
}

/// What the Name field writes to `projects.json`: trimmed, or nil when empty or blank so the entry goes back to the folder's name and a
/// blank name is never written.
public func normalizedProjectName(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

/// One tag normalized for `projects.json`: trimmed and lower case, or nil when empty or blank.
public func normalizedProjectTag(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return trimmed.isEmpty ? nil : trimmed
}

/// Tags normalized for `projects.json`: trimmed, lower case, blanks dropped, and duplicates removed while keeping order.
public func normalizedProjectTags(_ raw: [String]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for item in raw {
        guard let tag = normalizedProjectTag(item), seen.insert(tag).inserted else { continue }
        result.append(tag)
    }
    return result
}

/// Adds `raw` to `tags` following the tag rules (trimmed, lower case, no repeats, blank ignored).
public func addingProjectTag(_ raw: String, to tags: [String]) -> [String] {
    normalizedProjectTags(tags + [raw])
}

/// Removes `tag` from `tags`.
public func removingProjectTag(_ tag: String, from tags: [String]) -> [String] {
    tags.filter { $0 != tag }
}

/// One project of the list.
public struct ProjectRow: Equatable, Identifiable, Sendable {
    /// The project's identity, as the file has it.
    public let path: String
    /// The name set on it, else the folder's.
    public let name: String
    /// The custom name stored in `projects.json`, nil when absent.
    public let customName: String?
    /// `owner/name` of its GitHub `origin`, when it has one.
    public let repo: String?
    public let pinned: Bool
    public let tags: [String]
    public let iconColor: ProjectColor?
    public let iconMark: AppIcon?
    public let iconImage: String?
    /// Actions run in a new worktree or after a clone, from `projects.json`.
    public let actions: [ProjectAction]
    /// When a session last worked in it, from `projectsWithLastActive`; derived from the sessions, never stored in the file. nil when none did.
    public var lastActive: Date?

    public init(
        path: String,
        name: String,
        customName: String? = nil,
        repo: String?,
        pinned: Bool = false,
        tags: [String] = [],
        iconColor: ProjectColor? = nil,
        iconMark: AppIcon? = nil,
        iconImage: String? = nil,
        actions: [ProjectAction] = [],
        lastActive: Date? = nil
    ) {
        self.path = path
        self.name = name
        self.customName = customName
        self.repo = repo
        self.pinned = pinned
        self.tags = tags
        self.iconColor = iconColor
        self.iconMark = iconMark
        self.iconImage = iconImage
        self.actions = actions
        self.lastActive = lastActive
    }

    public var id: String { path }
    /// The folder's own name (what the Name field falls back to when emptied).
    public var folderName: String { projectFolderName(path) }
    /// What the row says under the name: the repository, else where the folder is.
    public var line: String { repo ?? path }
    /// What its tile's colour is made from, so it matches the project's sessions.
    public var colorKey: String { projectColorKey(path) }
    /// What the project's tile draws: its chosen colour and mark, else initials on a colour made from the name.
    public var tile: ProjectTile { projectTile(name: name, colorKey: colorKey, color: iconColor, mark: iconMark, image: iconImage) }
}

/// A row for each entry, in the file's order; `remote` says the GitHub `owner/name` of a folder, if any.
public func projectRows(_ entries: [ProjectEntry], remote: (String) -> String? = originRepo(ofFolder:)) -> [ProjectRow] {
    entries.map {
        ProjectRow(
            path: $0.path,
            name: $0.name ?? projectFolderName($0.path),
            customName: $0.name,
            repo: remote($0.path),
            pinned: $0.pinned,
            tags: $0.tags,
            iconColor: $0.iconColor.flatMap(ProjectColor.init(rawValue:)),
            iconMark: $0.iconMark.flatMap(AppIcon.init(rawValue:)),
            iconImage: $0.iconImage,
            actions: $0.actions
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

/// What the Projects list is ordered by: the name, or when a session last worked in the project.
public enum ProjectSortKey: Equatable, Hashable, Sendable {
    case name
    case lastActive
}

/// The order of the Projects list; the pinned come first whatever it is. Name goes A to Z and Last active most recent first until the same title is clicked again.
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

/// What narrows the Projects list: everything, one tag in use, or projects with no GitHub remote.
public enum ProjectFilter: Equatable, Hashable, Sendable {
    case all
    case tag(String)
    case localOnly
}

/// How the Projects list groups its rows.
public enum ProjectGrouping: String, CaseIterable, Equatable, Hashable, Sendable {
    case none
    case tag

    public var title: String {
        switch self {
        case .none: "None"
        case .tag: "Tag"
        }
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

/// Filters `rows` by `query` (name, remote or tag) and `filter`, orders pinned first then by `order` (a project no session worked in goes last by last activity,
/// either way), and groups by `groupBy` (`none`, or `tag` under
/// each project's first tag and `"untagged"` when it has none). Returns empty when nothing matches.
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
        }
    }
    guard matched.isEmpty == false else { return [] }
    func ordered(_ items: [ProjectRow]) -> [ProjectRow] {
        items.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            if order.key == .lastActive {
                switch (a.lastActive, b.lastActive) {
                case (nil, nil): break
                case (nil, _): return false
                case (_, nil): return true
                case (let x?, let y?): if x != y { return order.ascending ? x < y : x > y }
                }
            }
            let cmp = a.name.localizedCaseInsensitiveCompare(b.name)
            if cmp != .orderedSame { return (cmp == .orderedAscending) == (order.key == .lastActive || order.ascending) }
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
    }
}

extension ProjectsProblem {
    /// The problem as the page says it: the file, the field and what is wrong with it.
    public var text: String { path == "(file)" || path == "(root)" ? "projects.json \(message)" : "projects.json: \(path) \(message)" }
}

/// The rows of `projects.json`, kept in step with the file: it follows what another process writes. A file that does not match its schema (or cannot be
/// read) gives no rows and its problems, and `add` writes nothing over it.
@MainActor @Observable public final class ProjectsModel {
    public private(set) var rows: [ProjectRow] = []
    public private(set) var problems: [ProjectsProblem] = []
    /// Why the last add could not be written, when it could not.
    public private(set) var failure: String?
    /// Where new clones and new projects go by default (`projectsFolder` of `chat.json`).
    public private(set) var projectsPath: String
    /// Why the last Change… of the default folder was refused, in words; the old folder stands.
    public private(set) var projectsFolderProblem: String?
    @ObservationIgnored private let file: ProjectsFile
    @ObservationIgnored private let imageStore: ProjectIconStore
    @ObservationIgnored private let remote: (String) -> String?
    @ObservationIgnored private let readChatConfig: () throws -> Data?
    @ObservationIgnored private let writeChatConfig: (Data) throws -> Void
    @ObservationIgnored private let home: String

    public var carrierFolder: String { file.folder }

    public init(
        file: ProjectsFile = .current(),
        remote: @escaping (String) -> String? = originRepo(ofFolder:),
        readChatConfig: @escaping () throws -> Data? = currentChatConfig,
        writeChatConfig: @escaping (Data) throws -> Void = writeCurrentChatConfig,
        home: String = NSHomeDirectory()
    ) {
        self.file = file
        self.imageStore = ProjectIconStore(folder: file.folder)
        self.remote = remote
        self.readChatConfig = readChatConfig
        self.writeChatConfig = writeChatConfig
        self.home = home
        self.projectsPath = projectsFolder(chatJSON: (try? readChatConfig()) ?? nil, carrierFolder: file.folder, home: home)
    }

    /// Reads the file again; the rows and problems change only when they differ, so the page is not drawn again for nothing.
    public func reload() {
        let nextProjectsPath = projectsFolder(chatJSON: (try? readChatConfig()) ?? nil, carrierFolder: file.folder, home: home)
        if projectsPath != nextProjectsPath { projectsPath = nextProjectsPath }
        var newRows: [ProjectRow] = []
        var newProblems: [ProjectsProblem] = []
        do {
            newRows = projectRows(try file.read(), remote: remote)
        } catch ProjectsFileError.invalid(let found) {
            newProblems = found
        } catch {
            newProblems = [ProjectsProblem(path: "(file)", message: "cannot be read: \(error.localizedDescription)")]
        }
        if rows != newRows { rows = newRows }
        if problems != newProblems { problems = newProblems }
    }

    /// Reloads now and then again each `interval`, until the task is cancelled. ponytail: a poll of a small file, which also sees an edit made in place; a file watcher if it ever costs.
    public func follow(every interval: Duration = .seconds(1)) async {
        while Task.isCancelled == false {
            reload()
            try? await Task.sleep(for: interval)
        }
    }

    /// Adds `folder` as a project, or says it already is one and writes nothing. nil when it could not be written: `problems` says why when the file does not
    /// match its schema, `failure` when the folder is refused or the disk refused.
    @discardableResult public func add(folder: String) -> ProjectAdd? {
        if let refusal = projectFolderRefusal(folder, carrierFolder: file.folder) {
            failure = refusal
            return nil
        }
        var added: ProjectAdd?
        _ = write { added = try file.add(folder: folder) }
        return added
    }

    /// Clears the last add failure (for example when a sheet is dismissed).
    public func clearFailure() { failure = nil }

    /// Writes `folder` as `projectsFolder` in `chat.json`, keeping every other key; refuses a folder inside Carrier's own folders and leaves the old path.
    public func changeProjectsFolder(to folder: String) {
        projectsFolderProblem = saveProjectsFolder(
            folder,
            currentPath: projectsPath,
            carrierFolder: file.folder,
            readChatConfig: readChatConfig,
            writeChatConfig: writeChatConfig
        )
        if projectsFolderProblem == nil {
            projectsPath = projectsFolder(chatJSON: (try? readChatConfig()) ?? nil, carrierFolder: file.folder, home: home)
        }
    }

    /// Sets the project's name, or removes `name` when `raw` is empty or blank so it goes back to the folder's name.
    @discardableResult public func setName(_ raw: String, path: String) -> Bool {
        write { try file.update(path: path, key: "name", value: normalizedProjectName(raw)) }
    }

    /// Pins or unpins the project; unpinned leaves `pinned` out of the entry.
    @discardableResult public func setPinned(_ pinned: Bool, path: String) -> Bool {
        write { try file.update(path: path, key: "pinned", value: pinned ? true : nil) }
    }

    /// Adds a tag (trimmed, lower case, no repeats, blank ignored) to the project's entry.
    @discardableResult public func addTag(_ raw: String, path: String) -> Bool {
        write { try file.updateTags(path: path) { addingProjectTag(raw, to: $0) } }
    }

    /// Removes `tag` from the project's entry.
    @discardableResult public func removeTag(_ tag: String, path: String) -> Bool {
        write { try file.updateTags(path: path) { removingProjectTag(tag, from: $0) } }
    }

    /// Sets or clears the project's icon colour, clearing any image and deleting its copy while keeping every other key.
    @discardableResult public func setIconColor(_ color: ProjectColor?, path: String) -> Bool {
        editIconClearingImage(path: path, changes: ["color": color?.rawValue])
    }

    /// Sets or clears the project's icon mark, clearing any image and deleting its copy while keeping every other key.
    @discardableResult public func setIconMark(_ mark: AppIcon?, path: String) -> Bool {
        editIconClearingImage(path: path, changes: ["mark": mark?.rawValue])
    }

    /// Clears the project's icon colour, mark and image, deleting any copied image file while keeping every other key of the entry.
    @discardableResult public func resetIcon(path: String) -> Bool {
        editIconClearingImage(path: path, changes: ["color": nil, "mark": nil])
    }

    /// Copies and reduces the image at `sourceURL` into `project-icons`, points `icon.image` at it, and deletes any previous copy.
    @discardableResult public func setIconImage(from sourceURL: URL, path: String) -> Bool {
        saveIconImage(path: path) { try $0.save(from: sourceURL) }
    }

    /// Scales and saves `image` into `project-icons`, points `icon.image` at it, and deletes any previous copy.
    @discardableResult public func setIconImage(cgImage image: CGImage, path: String) -> Bool {
        saveIconImage(path: path) { try $0.save(cgImage: image) }
    }

    private func editIconClearingImage(path: String, changes: [String: String?]) -> Bool {
        var entries: [ProjectEntry] = []
        var previousImage: String?
        var merged = changes
        merged["image"] = .some(nil)
        let wrote = write {
            entries = try file.read()
            previousImage = entries.first { $0.path == path }?.iconImage
            try file.updateIcon(path: path, changes: merged)
            return true
        }
        if wrote, let previousImage, entries.contains(where: { $0.path != path && $0.iconImage == previousImage }) == false {
            imageStore.delete(previousImage)
        }
        return wrote
    }

    private func saveIconImage(path: String, save: (ProjectIconStore) throws -> String) -> Bool {
        var savedName: String?
        do {
            let entries = try file.read()
            guard let entry = entries.first(where: { $0.path == path }) else {
                throw ProjectsFileError.missing(path)
            }
            let previous = entry.iconImage
            let name = try save(imageStore)
            savedName = name
            try file.updateIcon(path: path, changes: ["image": name])
            if let previous, previous != name, entries.contains(where: { $0.path != path && $0.iconImage == previous }) == false {
                imageStore.delete(previous)
            }
            failure = nil
            reload()
            return true
        } catch ProjectsFileError.invalid(let found) {
            if let savedName { imageStore.delete(savedName) }
            problems = found
        } catch let error as ProjectIconStoreError {
            if let savedName { imageStore.delete(savedName) }
            failure = error.localizedDescription
        } catch {
            if let savedName { imageStore.delete(savedName) }
            failure = "projects.json cannot be written: \(error.localizedDescription)"
        }
        return false
    }

    /// Writes `actions` on the project at `path` and reloads the list; returns false without writing when any action is invalid or the file failed.
    @discardableResult public func saveActions(path: String, actions: [ProjectAction]) -> Bool {
        write { try file.updateActions(path: path, actions: actions) }
    }

    private func write(_ operation: () throws -> Void) -> Bool {
        write { try operation(); return true }
    }

    private func write(_ operation: () throws -> Bool) -> Bool {
        do {
            guard try operation() else { return false }
            failure = nil
            reload()
            return true
        } catch ProjectsFileError.invalid(let found) {
            problems = found
        } catch {
            failure = "projects.json cannot be written: \(error.localizedDescription)"
        }
        return false
    }
}
