import CoreGraphics
import Foundation
import Observation

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

/// Whether the project's folder is there to open.
public enum ProjectStatus: Equatable, Sendable {
    case ready
    /// The folder no longer exists (moved or deleted): the list says so and the page offers Locate….
    case notFound

    /// What the list and the page say for it; nil when there is nothing to say.
    public func text(bundle: Bundle? = nil, locale: Locale = .current) -> String? { self == .notFound ? Copy.projectsFolderNotFound(bundle: bundle, locale: locale) : nil }
}

/// Whether `path` (written with `~` or not) is a folder that exists.
public func projectFolderExists(_ path: String) -> Bool {
    var isFolder: ObjCBool = false
    return FileManager.default.fileExists(atPath: (path as NSString).expandingTildeInPath, isDirectory: &isFolder) && isFolder.boolValue
}

/// Whether `folder` (written with `~` or not) is a git repository: it has a `.git`, a folder or the file of a linked worktree.
public func isGitRepository(_ folder: String) -> Bool {
    FileManager.default.fileExists(atPath: (folder as NSString).expandingTildeInPath + "/.git")
}
