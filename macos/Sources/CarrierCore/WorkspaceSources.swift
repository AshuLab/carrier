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

/// The chat host's projects folder: the config's `chat.projectsFolder` (`~/` expanded), else `<root>/chat/projects`.
public func projectsFolder(configJSON: Data?, home: String) -> String {
    let object = configJSON.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
    let chosen = ((object?["chat"] as? [String: Any])?["projectsFolder"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    guard let chosen else { return sharedRoot(configJSON: configJSON, home: home) + "/chat/projects" }
    if chosen == "~" { return home }
    return chosen.hasPrefix("~/") ? home + chosen.dropFirst() : chosen
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

/// `projectsFolder` of the config file the app works with, read each time so a change in the file is followed.
public func currentProjectsFolder() -> String {
    let path = activeConfigPath(saved: SetupStore().load(), environment: ProcessInfo.processInfo.environment, home: NSHomeDirectory())
    return projectsFolder(configJSON: try? Data(contentsOf: URL(fileURLWithPath: path)), home: NSHomeDirectory())
}
