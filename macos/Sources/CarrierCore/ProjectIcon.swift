import Foundation

/// The letters of a project's icon, always capitals: the first letters of its first three words (`fury-invest-returns` is FIR), or the
/// first two letters of a one-word name (`carrier` is CA). Three letters tell apart projects that share their first two words. A name
/// with a parent folder in front (`dev/carrier`) is the last part.
public func projectInitials(_ name: String) -> String {
    let last = name.split(separator: "/").last.map(String.init) ?? name
    let words = last.split(whereSeparator: { "-_ .".contains($0) })
    guard let first = words.first else { return "?" }
    let letters = words.count > 1 ? words.prefix(3).compactMap { $0.first }.map(String.init).joined() : String(first.prefix(2))
    return letters.uppercased()
}

/// What a project's colour is made from: the last part of its folder or of `owner/name`, in lower case, so the folder of a session and
/// the repository of an epic that are the same project have the same colour.
public func projectColorKey(_ pathOrRepo: String) -> String {
    (pathOrRepo.split(separator: "/").last.map(String.init) ?? pathOrRepo).lowercased()
}

/// The eight colours a project's icon can wear in `projects.json` (`icon.color`), kept by name so the app draws them for light and dark.
public enum ProjectColor: String, CaseIterable, Sendable {
    case red, orange, yellow, green, teal, blue, purple, pink
}

/// The eight marks a project's icon can wear in `projects.json` (`icon.mark`): existing icons of the app, stored by `AppIcon.rawValue`.
public let projectIconMarks: [AppIcon] = [.code, .terminal, .cube, .book, .home, .bolt, .brain, .star]

/// What gives a project's tile its colour: a chosen colour from `projects.json`, else an index into the app's hashed palette.
public enum ProjectTileColor: Equatable, Sendable {
    case named(ProjectColor)
    case hashed(Int)
}

/// What sits inside a project's tile: a chosen mark (`AppIcon`) or the project's initials.
public enum ProjectTileContent: Equatable, Sendable {
    case initials(String)
    case mark(AppIcon)
}

/// What a project's tile draws: its colour, its mark or initials, and any stored image name.
public struct ProjectTile: Equatable, Sendable {
    public let name: String
    public let color: ProjectTileColor
    public let content: ProjectTileContent
    public let image: String?

    public init(name: String, color: ProjectTileColor, content: ProjectTileContent, image: String? = nil) {
        self.name = name
        self.color = color
        self.content = content
        self.image = image
    }
}

/// The tile for a project given its display name, its hashed colour key, and whatever `icon` fields were set.
public func projectTile(
    name: String,
    colorKey: String,
    color: ProjectColor? = nil,
    mark: AppIcon? = nil,
    image: String? = nil,
    paletteCount: Int = 24
) -> ProjectTile {
    ProjectTile(
        name: name,
        color: color.map(ProjectTileColor.named) ?? .hashed(projectColorIndex(colorKey, count: paletteCount)),
        content: mark.map(ProjectTileContent.mark) ?? .initials(projectInitials(name)),
        image: image
    )
}

/// What a project looks like wherever it shows: its tile and the title of its group.
public struct ProjectIdentity: Equatable, Sendable {
    public let tile: ProjectTile
    public let title: String
}

/// The identity of the folder `path` among `projects`: the project's name and its chosen colour, mark or image when it is one, else the folder's own
/// name and a colour made from it, which is what a folder that is not a project, and a project with nothing set, have always had.
public func projectIdentity(path: String, in projects: [ProjectRow]) -> ProjectIdentity {
    if let project = projects.first(where: { isSameFolder($0.path, path) }) { return ProjectIdentity(tile: project.tile, title: project.name) }
    let name = projectFolderName(path)
    return ProjectIdentity(tile: projectTile(name: name, colorKey: projectColorKey(path)), title: name)
}

/// The identity of the project whose `origin` is the GitHub repository `repo` (`owner/name`, case aside); nil when no project is, and the epic draws as before.
public func projectIdentity(repo: String, in projects: [ProjectRow]) -> ProjectIdentity? {
    projects.first { $0.repo?.caseInsensitiveCompare(repo) == .orderedSame }.map { ProjectIdentity(tile: $0.tile, title: $0.name) }
}

/// Which of `count` colours a project has: the same one in every launch and for every session of it (`hashValue` is not, it changes
/// at each launch). FNV-1a over the project's folder.
public func projectColorIndex(_ folder: String, count: Int) -> Int {
    guard count > 0 else { return 0 }
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in folder.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
    return Int(hash % UInt64(count))
}
