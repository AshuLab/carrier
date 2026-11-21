import Foundation

// The pieces of the workspace popover that need no model (docs/specs/workspace-sources.md): what the URL step accepts, where the
// projects folder is and what is in it. `NewSessionModel` drives the popover with them.

/// Why `source` is off, in words; nil when it is on. Only the sources that list and clone with the person's `gh` login (a GitHub URL and
/// My GitHub repositories, ADR 0015) are off, and only for a `gh` that is `missing` or `signedOut`: `ready`, `unknown` and a host that did
/// not report the health (`gh` nil) leave the sheet as it was. A local folder, the recent folders and a new project never depend on `gh`.
public func workspaceSourceReason(_ source: WorkspaceSource, gh: ToolState?) -> String? {
    guard source == .githubURL || source == .githubRepos else { return nil }
    switch gh {
    case .missing: return "gh is not installed. See Health in Settings."
    case .signedOut: return "gh is signed out. See Health in Settings."
    case .ready, .unknown, nil: return nil
    }
}

/// `owner/repo` for what the URL step was given, nil when it is not exactly one GitHub repository: the form itself, with or without
/// `.git`, a trailing slash, `github.com/` or `https://github.com/` in front. The host takes only the `owner/repo` form, and only
/// with the characters and parts its own pattern takes (no empty, `.` or `..` part).
public func repoReference(_ text: String) -> String? {
    var rest = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
    if let prefix = ["https://github.com/", "github.com/"].first(where: { rest.hasPrefix($0) }) { rest = rest.dropFirst(prefix.count) }
    if rest.hasSuffix("/") { rest = rest.dropLast() }
    if rest.hasSuffix(".git") { rest = rest.dropLast(4) }
    let parts = rest.split(separator: "/", omittingEmptySubsequences: false)
    func plain(_ part: Substring) -> Bool {
        part.isEmpty == false && part != "." && part != ".." && part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "_.-".contains($0)) }
    }
    guard parts.count == 2, parts.allSatisfy(plain) else { return nil }
    return rest.description
}

/// Why `name` is not a name the host takes for a new project, in words; nil when it is one plain folder name: letters, digits, `_`, `.`
/// and `-`, at most a hundred, not starting with a dot or a dash (the host's own pattern, so a name it would refuse never goes out).
public func projectNameProblem(_ name: String) -> String? {
    func word(_ c: Character) -> Bool { c.isASCII && (c.isLetter || c.isNumber || c == "_") }
    guard let first = name.first else { return "Write a name" }
    if name.count > 100 { return "A name has at most 100 characters" }
    if word(first) == false { return "A name starts with a letter, a digit or _" }
    if name.allSatisfy({ word($0) || $0 == "." || $0 == "-" }) == false { return "Use only letters, digits, _, . and -" }
    return nil
}

/// The chat host's projects folder: `projectsFolder` of `chat.json` (`~/` expanded), else `<folder>/chat/projects`; `carrierFolder` is the
/// Carrier folder. The file is the host's own level of configuration (ADR 0034), never the engine's config.
public func projectsFolder(chatJSON: Data?, carrierFolder: String, home: String) -> String {
    let object = chatJSON.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
    guard let chosen = (object?["projectsFolder"] as? String).flatMap({ $0.isEmpty ? nil : $0 }) else { return CarrierPlaces(folder: carrierFolder).chatProjects }
    if chosen == "~" { return home }
    return chosen.hasPrefix("~/") ? home + chosen.dropFirst() : chosen
}

private func realOfNearest(_ path: String) -> String {
    let clean = (path as NSString).standardizingPath
    if let resolved = realpath(clean, nil) {
        let real = String(cString: resolved)
        free(resolved)
        return real
    }
    let ns = clean as NSString
    let parent = ns.deletingLastPathComponent
    if parent == clean || parent.isEmpty { return clean }
    return (realOfNearest(parent) as NSString).appendingPathComponent(ns.lastPathComponent)
}

private func ownCarrierFolders(carrierFolder: String) -> [(name: String, path: String)] {
    let places = CarrierPlaces(folder: realOfNearest(carrierFolder))
    return [places.engine, places.chatState, places.chatLogs, places.chatWorktrees, places.chatPending, places.chatSessions].map { own in
        (name: String(own.dropFirst(places.folder.count + 1)), path: own)
    }
}

/// Why `folder` cannot be the projects folder, in words; nil when it can. The host's own rule (src/chat/folder.ts): an absolute path
/// that is not the Carrier folder's `engine` or the chat's own `state`, `logs`, `worktrees`, `pending` or `sessions`, or inside one, symlinks resolved.
public func projectsFolderRefusal(_ folder: String, carrierFolder: String) -> String? {
    guard folder.hasPrefix("/") else { return "The projects folder must be an absolute path" }
    let real = realOfNearest(folder)
    for (name, own) in ownCarrierFolders(carrierFolder: carrierFolder) {
        if real == own || real.hasPrefix(own + "/") { return "That folder is inside Carrier's own \(name) folder; the chat never works there" }
    }
    return nil
}

/// Whether `folder` (an existing, readable real path) is inside a git worktree linked to another repository.
private func isLinkedWorktree(_ folder: String) -> Bool {
    var dir = folder
    while true {
        let dotGit = (dir as NSString).appendingPathComponent(".git")
        var info = stat()
        if stat(dotGit, &info) == 0 {
            if (info.st_mode & S_IFMT) == S_IFDIR { return false }
            guard (info.st_mode & S_IFMT) == S_IFREG,
                  let text = try? String(contentsOfFile: dotGit, encoding: .utf8),
                  let line = text.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("gitdir:") })
            else { return false }
            let target = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
            guard target.isEmpty == false else { return false }
            let gitDir = URL(fileURLWithPath: target, relativeTo: URL(fileURLWithPath: dir, isDirectory: true)).standardized.path
            let commondir = (gitDir as NSString).appendingPathComponent("commondir")
            guard let common = try? String(contentsOfFile: commondir, encoding: .utf8) else { return false }
            let resolved = URL(fileURLWithPath: common.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: URL(fileURLWithPath: gitDir, isDirectory: true)).standardized.path
            return resolved != gitDir
        }
        let parent = (dir as NSString).deletingLastPathComponent
        if parent == dir || parent.isEmpty { return false }
        dir = parent
    }
}

/// Why `folder` cannot be added as a project, in words; nil when it can. The host's `checkProjectFolder` rule (src/chat/folder.ts):
/// an existing, readable folder that is not inside Carrier's own folders (symlinks resolved) and not a worktree linked to another project.
public func projectFolderRefusal(_ folder: String, carrierFolder: String = currentCarrierFolder()) -> String? {
    guard folder.hasPrefix("/") else { return "The folder must be an absolute path" }
    guard let resolved = realpath(folder, nil) else {
        return errno == EACCES || errno == EPERM ? "That folder cannot be read" : "That folder does not exist"
    }
    let real = String(cString: resolved)
    free(resolved)
    var info = stat()
    guard stat(real, &info) == 0 else {
        return errno == EACCES || errno == EPERM ? "That folder cannot be read" : "That folder does not exist"
    }
    guard (info.st_mode & S_IFMT) == S_IFDIR else { return "That path is not a folder" }
    guard access(real, R_OK | X_OK) == 0 else { return "That folder cannot be read" }
    for (name, own) in ownCarrierFolders(carrierFolder: carrierFolder) {
        if real == own || real.hasPrefix(own + "/") { return "That folder is inside Carrier's own \(name) folder; a project cannot live there" }
    }
    if isLinkedWorktree(real) { return "That folder is a worktree linked to another project" }
    return nil
}

/// `json` with `projectsFolder` set to `folder`; the file's other keys are left as they were. `json` nil is a `chat.json` that is not
/// there yet, which this makes. nil when `json` is not a JSON object: the app never overwrites a file it cannot read.
public func applyingProjectsFolder(_ folder: String, to json: Data?) -> Data? {
    var file: [String: Any] = [:]
    if let json {
        guard let object = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else { return nil }
        file = object
    }
    file["projectsFolder"] = folder
    return try? JSONSerialization.data(withJSONObject: file, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
}

/// A folder the projects folder holds: `name` is `<owner>/<repo>` (`local/<name>` for a new project) and `path` its full path.
public struct ProjectFolder: Equatable {
    public let name: String
    public let path: String
}

/// The `<owner>/<repo>` folders of the projects folder, read from disk, by name; none when the folder is not there.
public func projectFolders(in root: String) -> [ProjectFolder] {
    func folders(_ path: String) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        return names.filter { name in
            var isFolder: ObjCBool = false
            return name.hasPrefix(".") == false && FileManager.default.fileExists(atPath: path + "/" + name, isDirectory: &isFolder) && isFolder.boolValue
        }
    }
    return folders(root).flatMap { owner in folders(root + "/" + owner).map { ProjectFolder(name: owner + "/" + $0, path: root + "/" + owner + "/" + $0) } }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
}

private func currentConfigURL() -> URL { URL(fileURLWithPath: configFilePath()) }

/// The config file's bytes, read each time so a change in the file is followed; nil when it cannot be read.
public func currentConfig() -> Data? { try? Data(contentsOf: currentConfigURL()) }

/// Writes the config file in place; the caller read it just before, as the Repos tab does.
public func writeCurrentConfig(_ data: Data) throws { try data.write(to: currentConfigURL(), options: .atomic) }

/// The Carrier folder the app works with: `CARRIER_HOME` in its own environment, else `~/.carrier`.
public func currentCarrierFolder() -> String { carrierFolder(environment: ProcessInfo.processInfo.environment, home: NSHomeDirectory()) }

private func currentChatConfigURL() -> URL { URL(fileURLWithPath: CarrierPlaces().chatConfig) }

/// The chat's `chat.json`, read each time; nil when it is not there, an error when it is there and cannot be read.
public func currentChatConfig() throws -> Data? {
    let url = currentChatConfigURL()
    return FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
}

/// `json` (a `chat.json`; nil is one that is not there yet, which this makes) after `edit` changed its keys, the file's other keys left as they were.
/// nil when `json` is not a JSON object: the app never overwrites a file it cannot read.
func editingChatConfig(_ json: Data?, _ edit: (inout [String: Any]) -> Void) -> Data? {
    var file: [String: Any] = [:]
    if let json {
        guard let object = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else { return nil }
        file = object
    }
    edit(&file)
    return try? JSONSerialization.data(withJSONObject: file, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
}

/// Writes `chat.json` in place, making the Carrier folder when it is not there yet.
public func writeCurrentChatConfig(_ data: Data) throws {
    let url = currentChatConfigURL()
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
}

/// `projectsFolder` of the chat's `chat.json`.
public func currentProjectsFolder() -> String { projectsFolder(chatJSON: try? currentChatConfig(), carrierFolder: currentCarrierFolder(), home: NSHomeDirectory()) }

/// A row of My GitHub repositories: when it was last pushed, whether the config already watches it, and why the "watch" box would not
/// apply to it when it is not watched but cannot be (a folder name another watched repo has).
public struct GithubRepoRow: Equatable, Identifiable {
    public var name: String
    public var isPrivate: Bool
    public var pushed: String
    public var watched: Bool
    public var cannotWatch: String?
    public var id: String { name }
}

/// The loaded repositories that contain `query` (case-insensitive), in order, each with what the watch box would do for it.
public func githubRepoRows(_ repos: [AvailableRepo], watched: [String], query: String, now: Date = Date()) -> [GithubRepoRow] {
    let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
    return repos.filter { needle.isEmpty || $0.name.lowercased().contains(needle) }.map { repo in
        let isWatched = watched.contains { $0.lowercased() == repo.name.lowercased() }
        return GithubRepoRow(name: repo.name, isPrivate: repo.isPrivate, pushed: pushedLine(repo.pushedAt, now: now), watched: isWatched, cannotWatch: isWatched ? nil : repoProblem(repo.name, joining: watched))
    }
}
