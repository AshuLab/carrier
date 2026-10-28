import Foundation

// The pieces of the workspace popover that need no model (docs/specs/workspace-sources.md): what the URL step accepts, where the
// projects folder is and what is in it. `NewSessionModel` drives the popover with them.

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

/// The chat host's projects folder: the config's `chat.projectsFolder` (`~/` expanded), else `<root>/chat/projects`.
public func projectsFolder(configJSON: Data?, home: String) -> String {
    let object = configJSON.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
    let chosen = ((object?["chat"] as? [String: Any])?["projectsFolder"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    guard let chosen else { return sharedRoot(configJSON: configJSON, home: home) + "/chat/projects" }
    if chosen == "~" { return home }
    return chosen.hasPrefix("~/") ? home + chosen.dropFirst() : chosen
}

/// Why `folder` cannot be the projects folder, in words; nil when it can. The host's own rule (src/chat/folder.ts): an absolute path
/// that is not the shared root's `repos`, `worktrees` or `orchestrator`, or inside one, symlinks resolved.
public func projectsFolderRefusal(_ folder: String, configJSON: Data?, home: String) -> String? {
    guard folder.hasPrefix("/") else { return "The projects folder must be an absolute path" }
    let real = URL(fileURLWithPath: folder).resolvingSymlinksInPath().path
    let root = URL(fileURLWithPath: sharedRoot(configJSON: configJSON, home: home)).resolvingSymlinksInPath().path
    for name in ["repos", "worktrees", "orchestrator"] {
        let engine = root + "/" + name
        if real == engine || real.hasPrefix(engine + "/") { return "That folder is inside Carrier's own \(name) folder; the chat never works there" }
    }
    return nil
}

/// `json` with `chat.projectsFolder` set to `folder`; the rest of the file, the `chat` block's other keys and the keys the app does not
/// know are left as they were. nil when `json` is not a JSON object: the app never makes a config file.
public func applyingProjectsFolder(_ folder: String, to json: Data) -> Data? {
    guard var file = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else { return nil }
    var chat = file["chat"] as? [String: Any] ?? [:]
    chat["projectsFolder"] = folder
    file["chat"] = chat
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

/// The config file the app works with: the one the setup chose, else the default.
private func currentConfigURL() -> URL {
    URL(fileURLWithPath: activeConfigPath(saved: SetupStore().load(), environment: ProcessInfo.processInfo.environment, home: NSHomeDirectory()))
}

/// The config file's bytes, read each time so a change in the file is followed; nil when it cannot be read.
public func currentConfig() -> Data? { try? Data(contentsOf: currentConfigURL()) }

/// Writes the config file in place; the caller read it just before, as the Repos tab does.
public func writeCurrentConfig(_ data: Data) throws { try data.write(to: currentConfigURL(), options: .atomic) }

/// `projectsFolder` of the config file the app works with.
public func currentProjectsFolder() -> String { projectsFolder(configJSON: currentConfig(), home: NSHomeDirectory()) }
