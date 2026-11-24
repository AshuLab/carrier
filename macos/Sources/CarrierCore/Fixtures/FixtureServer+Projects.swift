import Foundation

// What the fixture host does for the nine project requests of the `config` capability: the Swift writers on the scratch Carrier folder, answering as the real host
// does (docs/specs/macos-app-as-the-base-for-a-web-front-end.md, section 6). The writers go with a later change; this is the last place that calls them.

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

/// The reply data of `change` applied to the Carrier folder `home`, or the refusal the host would answer. A file that does not match, or a change that would make it not match, is
/// refused as `config.problem` with the field and the kind `custom`, and nothing is written.
func applyProjectsChange(_ change: ProjectsChange, home: String) -> (data: [String: Any]?, refusal: Refusal?) {
    let file = ProjectsFile(folder: home)
    func entry(_ path: String) -> [String: Any] { ((try? file.read()) ?? []).first { $0.path == path }?.json ?? ["path": path] }
    func refused(_ code: String, _ words: String, _ params: [String: TextParam]) -> (data: [String: Any]?, refusal: Refusal?) { (nil, Refusal(code: code, params: params, text: words)) }
    func plain(_ values: [String: ConfigValue]) -> [String: String?] { values.mapValues { if case .text(let text) = $0 { text } else { nil } } }
    do {
        switch change {
        case .add(let folder):
            switch try file.add(folder: folder) {
            case .added(let path): return (["added": true, "saved": entry(path)], nil)
            case .existing(let path): return (["added": false, "saved": entry(path)], nil)
            }
        case .remove(let path):
            try file.remove(path: path)
            return (["removed": path], nil)
        case .edit(let path, let key, let value):
            switch value {
            case .text(let text): try file.update(path: path, key: key, value: text)
            case .flag(let flag): try file.update(path: path, key: key, value: flag)
            case .map, .remove: try file.update(path: path, key: key, value: nil)
            }
            return (["saved": entry(path)], nil)
        case .move(let path, let folder):
            try file.locate(path: path, to: folder)
            return (["saved": entry(folder)], nil)
        case .editIcon(let path, let changes):
            try file.updateIcon(path: path, changes: plain(changes))
            return (["saved": entry(path)], nil)
        case .editDefaults(let path, let changes):
            var inner: [String: Any?] = [:]
            for (key, value) in changes {
                switch value {
                case .text(let text): inner[key] = text
                case .map(let map): inner[key] = map
                case .flag(let flag): inner[key] = flag
                case .remove: inner.updateValue(nil, forKey: key)
                }
            }
            try file.updateDefaults(path: path, changes: inner)
            return (["saved": entry(path)], nil)
        case .editTags(let path, let add, let remove):
            let removed = Set(normalizedProjectTags(remove))
            try file.updateTags(path: path) { normalizedProjectTags($0.filter { removed.contains($0) == false } + add) }
            return (["saved": entry(path)], nil)
        case .setActions(let path, let actions):
            guard try file.updateActions(path: path, actions: actions) else {
                return refused("config.problem", "projects.json: projects.0.actions must not be blank", ["path": "actions", "problem": "invalid_format"])
            }
            return (["saved": entry(path)], nil)
        case .setFolder(let folder):
            if let refusal = projectsFolderRefusal(folder, carrierFolder: home) { return (nil, refusal) }
            let url = URL(fileURLWithPath: CarrierPlaces(folder: home).chatConfig)
            guard let data = applyingProjectsFolder(folder, to: try? Data(contentsOf: url)) else {
                return refused("config.problem", "chat.json is not a JSON object, so it was not changed", ["path": "(file)", "problem": "notAnObject"])
            }
            try data.write(to: url, options: .atomic)
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
