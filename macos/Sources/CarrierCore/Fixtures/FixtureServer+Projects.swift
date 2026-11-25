import Foundation

// What the fixture host does for the nine project requests of the `config` capability: it changes the `projects.json` and `chat.json` of the scratch Carrier folder, answering as the real
// host does (docs/specs/macos-app-as-the-base-for-a-web-front-end.md, section 6). This is the only Swift code that writes them.

extension ProjectsChange {
    /// The change a request names, read from its decoded JSON; nil when it is not one of the nine or lacks a field.
    init?(cmd: String, request: [String: Any]) {
        let path = request["path"] as? String
        let folder = request["folder"] as? String
        func values(_ key: String) -> [String: ConfigValue]? {
            (request[key] as? [String: Any])?.mapValues { value in
                if let text = value as? String { return .text(text) }
                if let map = value as? [String: String] { return .map(map) }
                return .remove
            }
        }
        switch cmd {
        case "addProject": guard let folder else { return nil }; self = .add(folder: folder)
        case "removeProject": guard let path else { return nil }; self = .remove(path: path)
        case "editProject":
            guard let path, let key = request["key"] as? String, let value = request["value"] else { return nil }
            if let text = value as? String { self = .edit(path: path, key: key, value: .text(text)) } else if let flag = value as? Bool { self = .edit(path: path, key: key, value: .flag(flag)) } else { self = .edit(path: path, key: key, value: .remove) }
        case "moveProject": guard let path, let folder else { return nil }; self = .move(path: path, folder: folder)
        case "editProjectIcon": guard let path, let changes = values("changes") else { return nil }; self = .editIcon(path: path, changes: changes)
        case "editProjectDefaults": guard let path, let changes = values("changes") else { return nil }; self = .editDefaults(path: path, changes: changes)
        case "editProjectTags":
            guard let path, let add = request["add"] as? [String], let remove = request["remove"] as? [String] else { return nil }
            self = .editTags(path: path, add: add, remove: remove)
        case "setProjectActions":
            guard let path, let items = request["actions"] as? [[String: Any]] else { return nil }
            self = .setActions(path: path, actions: projectActions(from: items))
        case "setProjectsFolder": guard let folder else { return nil }; self = .setFolder(folder)
        default: return nil
        }
    }
}

/// Reads `projects.json` of `home` again, lets `edit` change its entries and writes the whole file atomically, after `readProjects` checked it before and after as the host's schema does.
/// Throws `ProjectsFileError.invalid` for a file or a result that does not match, and what `edit` throws.
func fixtureEditProjects(home: String, _ edit: (inout [[String: Any]]) throws -> Void) throws {
    let url = URL(fileURLWithPath: CarrierPlaces(folder: home).projects)
    let current = FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
    _ = try readProjects(current)
    var object = current.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] } ?? [:]
    var projects = object["projects"] as? [[String: Any]] ?? []
    try edit(&projects)
    object["projects"] = projects
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    _ = try readProjects(data)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
}

/// The reply data of `change` applied to the Carrier folder `home`, or the refusal the host would answer. A file that does not match, or a change that would make it not match, is
/// refused as `config.problem` with the field and the kind `custom`, and nothing is written.
func applyProjectsChange(_ change: ProjectsChange, home: String) -> (data: [String: Any]?, refusal: Refusal?) {
    func entry(_ path: String) -> [String: Any] { ((try? ProjectsFile(folder: home).read()) ?? []).first { $0.path == path }?.json ?? ["path": path] }
    func refused(_ code: String, _ words: String, _ params: [String: TextParam]) -> (data: [String: Any]?, refusal: Refusal?) { (nil, Refusal(code: code, params: params, text: words)) }
    func index(_ path: String, in projects: [[String: Any]]) throws -> Int {
        guard let found = projects.firstIndex(where: { $0["path"] as? String == path }) else { throw ProjectsFileError.missing(path) }
        return found
    }
    /// Sets or removes (`nil`) the sub-keys of the object `key` of the project at `path`; the object goes when none is left.
    func editObject(_ key: String, path: String, _ changes: [String: Any?]) throws {
        try fixtureEditProjects(home: home) { projects in
            let at = try index(path, in: projects)
            var inner = projects[at][key] as? [String: Any] ?? [:]
            for (name, value) in changes { inner[name] = value }
            projects[at][key] = inner.isEmpty ? nil : inner
        }
    }
    do {
        switch change {
        case .add(let folder):
            var known: String?
            try fixtureEditProjects(home: home) { projects in
                known = projects.first { isSameFolder($0["path"] as? String ?? "", folder) }?["path"] as? String
                if known == nil { projects.append(["path": folder, "name": (folder as NSString).lastPathComponent, "origin": "added"]) }
            }
            return (["added": known == nil, "saved": entry(known ?? folder)], nil)
        case .remove(let path):
            try fixtureEditProjects(home: home) { $0.remove(at: try index(path, in: $0)) }
            return (["removed": path], nil)
        case .edit(let path, let key, let value):
            try fixtureEditProjects(home: home) { projects in
                let at = try index(path, in: projects)
                switch value {
                case .text(let text): projects[at][key] = text
                case .flag(let flag): projects[at][key] = flag
                case .map, .remove: projects[at][key] = nil
                }
            }
            return (["saved": entry(path)], nil)
        case .move(let path, let folder):
            try fixtureEditProjects(home: home) { projects in
                let at = try index(path, in: projects)
                if let other = projects.indices.first(where: { $0 != at && isSameFolder(projects[$0]["path"] as? String ?? "", folder) }) {
                    throw ProjectsFileError.invalid([ProjectsProblem(path: "projects.\(other).path", message: "is already another project's folder")])
                }
                projects[at]["path"] = folder
            }
            return (["saved": entry(folder)], nil)
        case .editIcon(let path, let changes):
            try editObject("icon", path: path, changes.mapValues { value -> Any? in if case .text(let text) = value { return text }; return nil })
            return (["saved": entry(path)], nil)
        case .editDefaults(let path, let changes):
            try editObject("defaults", path: path, changes.mapValues { value -> Any? in
                switch value {
                case .text(let text): return text
                case .map(let map): return map
                case .flag(let flag): return flag
                case .remove: return nil
                }
            })
            return (["saved": entry(path)], nil)
        case .editTags(let path, let add, let remove):
            let removed = Set(normalizedProjectTags(remove))
            try fixtureEditProjects(home: home) { projects in
                let at = try index(path, in: projects)
                let next = normalizedProjectTags((projects[at]["tags"] as? [String] ?? []).filter { removed.contains($0) == false } + add)
                projects[at]["tags"] = next.isEmpty ? nil : next
            }
            return (["saved": entry(path)], nil)
        case .setActions(let path, let actions):
            let encoded = actions.compactMap(encodedProjectAction)
            guard encoded.count == actions.count else {
                // The first blank field the host's schema meets: `projects.<index>.actions.<n>.name` (then `command`), kind `invalid_format`.
                let index = ((try? ProjectsFile(folder: home).read()) ?? []).firstIndex { $0.path == path } ?? 0
                let blank = actions.enumerated().compactMap { n, action in
                    projectActionProblems(action)[.name] != nil ? (n, "name") : projectActionProblems(action)[.command] != nil ? (n, "command") : nil
                }.first ?? (0, "name")
                let field = "projects.\(index).actions.\(blank.0).\(blank.1)"
                return refused("config.problem", "projects.json: \(field) must not be blank", ["path": .string(field), "problem": "invalid_format"])
            }
            try fixtureEditProjects(home: home) { projects in projects[try index(path, in: projects)]["actions"] = encoded.isEmpty ? nil : encoded }
            return (["saved": entry(path)], nil)
        case .setFolder(let folder):
            if let refusal = projectsFolderRefusal(folder, carrierFolder: home) { return (nil, refusal) }
            let url = URL(fileURLWithPath: CarrierPlaces(folder: home).chatConfig)
            var chat: [String: Any] = [:]
            if let current = try? Data(contentsOf: url) {
                guard let object = (try? JSONSerialization.jsonObject(with: current)) as? [String: Any] else {
                    return refused("config.problem", "chat.json is not a JSON object, so it was not changed", ["path": "(file)", "problem": "notAnObject"])
                }
                chat = object
            }
            chat["projectsFolder"] = folder
            try JSONSerialization.data(withJSONObject: chat, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: url, options: .atomic)
            return (["saved": ["projectsFolder": folder]], nil)
        }
    } catch ProjectsFileError.invalid(let found) {
        let first = found.first ?? ProjectsProblem(path: "(file)", message: "does not match")
        return refused("config.problem", first.text, ["path": .string(first.path), "problem": "custom"])
    } catch ProjectsFileError.missing(let path) {
        return refused("project.missing", "No project has the path \(path)", ["path": .string(path)])
    } catch {
        return refused("request.internal", "internal error", [:])
    }
}
