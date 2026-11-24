import Foundation

// The pieces of the shared sheet that need no model: what a pasted address is, where the projects folder is and the checks on a folder.

/// `owner/repo` for what the sheet field was given, nil when it is not exactly one GitHub repository: the form itself, with or without
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
public func projectNameProblem(_ name: String) -> Refusal? {
    func word(_ c: Character) -> Bool { c.isASCII && (c.isLetter || c.isNumber || c == "_") }
    guard let first = name.first else { return .projectNameEmpty }
    if name.count > 100 { return .projectNameTooLong }
    if word(first) == false { return .projectNameBadStart }
    if name.allSatisfy({ word($0) || $0 == "." || $0 == "-" }) == false { return .projectNameBadCharacters }
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
public func projectsFolderRefusal(_ folder: String, carrierFolder: String) -> Refusal? {
    guard folder.hasPrefix("/") else { return Refusal(code: "folder.projectsNotAbsolute", text: "The projects folder must be an absolute path") }
    let real = realOfNearest(folder)
    for (name, own) in ownCarrierFolders(carrierFolder: carrierFolder) {
        if real == own || real.hasPrefix(own + "/") {
            return Refusal(code: "folder.insideCarrier", params: ["folder": .string(name)], text: "That folder is inside Carrier's own \(name) folder; the chat never works there")
        }
    }
    return nil
}

/// `path` made absolute against `base` and tidied of `.` and `..`. Not `URL(relativeTo:).path`: on some Foundation versions that drops the base.
private func absolutePath(_ path: String, from base: String) -> String {
    URL(fileURLWithPath: path.hasPrefix("/") ? path : base + "/" + path).standardized.path
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
            let gitDir = absolutePath(target, from: dir)
            let commondir = (gitDir as NSString).appendingPathComponent("commondir")
            guard let common = try? String(contentsOfFile: commondir, encoding: .utf8) else { return false }
            let resolved = absolutePath(common.trimmingCharacters(in: .whitespacesAndNewlines), from: gitDir)
            return resolved != gitDir
        }
        let parent = (dir as NSString).deletingLastPathComponent
        if parent == dir || parent.isEmpty { return false }
        dir = parent
    }
}

/// Why `folder` cannot be added as a project, in words; nil when it can. The host's `checkProjectFolder` rule (src/chat/folder.ts):
/// an existing, readable folder that is not inside Carrier's own folders (symlinks resolved) and not a worktree linked to another project.
public func projectFolderRefusal(_ folder: String, carrierFolder: String = currentCarrierFolder()) -> Refusal? {
    func refusal(_ code: String, _ text: String) -> Refusal { Refusal(code: code, text: text) }
    guard folder.hasPrefix("/") else { return refusal("folder.notAbsolute", "The folder must be an absolute path") }
    guard let resolved = realpath(folder, nil) else {
        return errno == EACCES || errno == EPERM ? refusal("folder.unreadable", "That folder cannot be read") : refusal("folder.missing", "That folder does not exist")
    }
    let real = String(cString: resolved)
    free(resolved)
    var info = stat()
    guard stat(real, &info) == 0 else {
        return errno == EACCES || errno == EPERM ? refusal("folder.unreadable", "That folder cannot be read") : refusal("folder.missing", "That folder does not exist")
    }
    guard (info.st_mode & S_IFMT) == S_IFDIR else { return refusal("folder.notDirectory", "That path is not a folder") }
    guard access(real, R_OK | X_OK) == 0 else { return refusal("folder.unreadable", "That folder cannot be read") }
    for (name, own) in ownCarrierFolders(carrierFolder: carrierFolder) {
        if real == own || real.hasPrefix(own + "/") {
            return Refusal(code: "folder.projectInsideCarrier", params: ["folder": .string(name)], text: "That folder is inside Carrier's own \(name) folder; a project cannot live there")
        }
    }
    if isLinkedWorktree(real) { return refusal("folder.linkedWorktree", "That folder is a worktree linked to another project") }
    return nil
}

/// The folder of `worktrees/` a repository's worktrees live in: `<owner>/<repo>`, or `local/<folder name>` without a GitHub origin. The rule of
/// `worktreeDirectory` in src/chat/names.ts, which `worktreePath` makes worktrees by; `worktree-clash.json` is the table both tests read.
public func worktreeDirectory(folder: String, repo: String?) -> String {
    repo ?? "local/" + (normalizedFolder(folder) as NSString).lastPathComponent
}

/// Why adding `folder` (whose GitHub `owner/name` is `repo`, if any) would clash with one of `projects`, in words naming it; nil when it would not. A clash is
/// another project whose worktree directory is the same, compared without regard to case; the same folder is already a project, not a clash.
/// The twin of `checkWorktreeClash` in src/chat/names.ts (ADR 0041).
public func worktreeClashRefusal(folder: String, repo: String?, among projects: [ProjectRow]) -> Refusal? {
    let mine = worktreeDirectory(folder: folder, repo: repo)
    for project in projects where isSameFolder(project.path, folder) == false {
        let theirs = worktreeDirectory(folder: project.path, repo: project.repo)
        if theirs.lowercased() == mine.lowercased() {
            return Refusal(
                code: "worktree.folderShared", params: ["project": .string(project.name), "directory": .string(theirs)],
                text: "The worktrees of \(project.name) already use the folder \(theirs); two projects cannot share it")
        }
    }
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

private func currentConfigURL() -> URL { URL(fileURLWithPath: configFilePath()) }

/// The config file's bytes, read each time so a change in the file is followed; nil when it cannot be read.
public func currentConfig() -> Data? { try? Data(contentsOf: currentConfigURL()) }

/// Writes the config file in place; the caller read it just before, as the Watching tab does.
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

/// Writes `folder` as `projectsFolder` in `chat.json` after checking `projectsFolderRefusal`; returns nil on success, or a refusal message.
public func saveProjectsFolder(
    _ folder: String,
    currentPath: String,
    carrierFolder: String,
    readChatConfig: () throws -> Data?,
    writeChatConfig: (Data) throws -> Void,
    log: (String) -> Void = { _ in }
) -> String? {
    func refused(_ reason: String) -> String {
        "\(reason). The projects folder stays \(currentPath)."
    }
    if let problem = projectsFolderRefusal(folder, carrierFolder: carrierFolder) { return refused(problem.text) }
    let json: Data?
    do { json = try readChatConfig() } catch {
        log("could not read chat.json: \(error)")
        return refused("chat.json could not be read")
    }
    guard let updated = applyingProjectsFolder(folder, to: json) else { return refused("chat.json is not a JSON object") }
    do { try writeChatConfig(updated) } catch {
        log("could not write chat.json: \(error)")
        return refused("chat.json is not writable")
    }
    return nil
}

/// `projectsFolder` of the chat's `chat.json`.
public func currentProjectsFolder() -> String { projectsFolder(chatJSON: try? currentChatConfig(), carrierFolder: currentCarrierFolder(), home: NSHomeDirectory()) }

