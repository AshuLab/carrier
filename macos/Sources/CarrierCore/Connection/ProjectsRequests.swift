import Foundation

// The requests of the `config` capability that change `projects.json` and `projectsFolder` of `chat.json` (docs/specs/macos-app-as-the-base-for-a-web-front-end.md,
// section 6; ADR 0053): the app asks, Node's code writes. Each takes what the Swift function it replaced took. Sent like `editChatSettings` (ConfigRequests.swift).

/// What a request sets a key to: text, a flag or a map of text, or `remove` (`null`, which takes the key out).
public enum ConfigValue: Equatable, Sendable {
    case text(String), flag(Bool), map([String: String]), remove

    var json: Any {
        switch self {
        case .text(let text): text
        case .flag(let flag): flag
        case .map(let map): map
        case .remove: NSNull()
        }
    }

    init(_ text: String?) { self = text.map(ConfigValue.text) ?? .remove }
}

/// One change to the person's projects, as the request that asks for it.
public enum ProjectsChange: Equatable {
    case add(folder: String)
    case remove(path: String)
    /// `key` is `name`, `pinned` or `hidden`.
    case edit(path: String, key: String, value: ConfigValue)
    case move(path: String, folder: String)
    case editIcon(path: String, changes: [String: ConfigValue])
    case editDefaults(path: String, changes: [String: ConfigValue])
    case editTags(path: String, add: [String], remove: [String])
    case setActions(path: String, actions: [ProjectAction])
    case setFolder(String)

    /// The request's name on the socket.
    public var cmd: String {
        switch self {
        case .add: "addProject"
        case .remove: "removeProject"
        case .edit: "editProject"
        case .move: "moveProject"
        case .editIcon: "editProjectIcon"
        case .editDefaults: "editProjectDefaults"
        case .editTags: "editProjectTags"
        case .setActions: "setProjectActions"
        case .setFolder: "setProjectsFolder"
        }
    }

    /// The request's fields (everything but `cmd` and `id`).
    var body: [String: Any] {
        switch self {
        case .add(let folder), .setFolder(let folder): ["folder": folder]
        case .remove(let path): ["path": path]
        case .edit(let path, let key, let value): ["path": path, "key": key, "value": value.json]
        case .move(let path, let folder): ["path": path, "folder": folder]
        case .editIcon(let path, let changes), .editDefaults(let path, let changes): ["path": path, "changes": changes.mapValues(\.json)]
        case .editTags(let path, let add, let remove): ["path": path, "add": add, "remove": remove]
        case .setActions(let path, let actions): ["path": path, "actions": actions.map { encodedProjectAction($0) ?? [:] }]
        }
    }

    private func data(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
    }

    /// The fields as `chatRequest` appends them to the request: the members of the object, after a comma.
    var fields: String { "," + String(decoding: data(body).dropFirst().dropLast(), as: UTF8.self) }

    /// The request as `carrier config` reads it: the socket's request without its `id`, one line.
    var request: Data { data(body.merging(["cmd": cmd]) { $1 }) + Data("\n".utf8) }
}

/// The reply of a project request: `added` and the entry as the file has it (`addProject`), the path that went (`removeProject`), or the entry (the others);
/// `setProjectsFolder` answers its `projectsFolder`.
public struct ProjectsChanged: Decodable, Equatable {
    public struct Saved: Decodable, Equatable {
        public let path: String?
        public let projectsFolder: String?
    }

    public let added: Bool?
    public let removed: String?
    public let saved: Saved?
}
