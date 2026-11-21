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

/// One project of the list.
public struct ProjectRow: Equatable, Identifiable, Sendable {
    /// The project's identity, as the file has it.
    public let path: String
    /// The name set on it, else the folder's.
    public let name: String
    /// `owner/name` of its GitHub `origin`, when it has one.
    public let repo: String?
    /// Actions run in a new worktree or after a clone, from `projects.json`.
    public let actions: [ProjectAction]

    public var id: String { path }
    /// What the row says under the name: the repository, else where the folder is.
    public var line: String { repo ?? path }
    /// What its tile's colour is made from, so it matches the project's sessions.
    public var colorKey: String { projectColorKey(path) }
}

/// A row for each entry, in the file's order; `remote` says the GitHub `owner/name` of a folder, if any.
public func projectRows(_ entries: [ProjectEntry], remote: (String) -> String? = originRepo(ofFolder:)) -> [ProjectRow] {
    entries.map { ProjectRow(path: $0.path, name: $0.name ?? ($0.path as NSString).lastPathComponent, repo: remote($0.path), actions: $0.actions) }
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
    @ObservationIgnored private let file: ProjectsFile
    @ObservationIgnored private let remote: (String) -> String?

    public init(file: ProjectsFile = .current(), remote: @escaping (String) -> String? = originRepo(ofFolder:)) {
        self.file = file
        self.remote = remote
    }

    /// Reads the file again; the rows and problems change only when they differ, so the page is not drawn again for nothing.
    public func reload() {
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
    /// match its schema, `failure` when the disk refused.
    @discardableResult public func add(folder: String) -> ProjectAdd? {
        do {
            let added = try file.add(folder: folder)
            failure = nil
            reload()
            return added
        } catch ProjectsFileError.invalid(let found) {
            problems = found
        } catch {
            failure = "projects.json cannot be written: \(error.localizedDescription)"
        }
        return nil
    }

    /// Writes `actions` on the project at `path` and reloads the list; returns false without writing when any action is invalid or the file failed.
    @discardableResult public func saveActions(path: String, actions: [ProjectAction]) -> Bool {
        do {
            guard try file.updateActions(path: path, actions: actions) else { return false }
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
