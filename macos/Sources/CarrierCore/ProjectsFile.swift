import Foundation

// `projects.json` in the Carrier folder (docs/adr/0038): the person's projects, read by the app and the chat host and written by both.
// The rules below are `src/config/projects.ts`'s, field by field; `ContractTests` runs the fixture its test writes through both. A file that
// does not match is reported with the field named and is never written over. An edit keeps every entry, and every key of the entry, it does not touch.

/// A field that is wrong and why. `path` is the key's place in the file (`projects.1.name`), `(root)` for the file itself.
public struct ProjectsProblem: Equatable, Sendable {
    public let path: String
    public let message: String
}

public enum ProjectsFileError: Error, Equatable {
    /// The file is there and does not match its schema, or cannot be read, or an edit would make it not match: nothing was written.
    case invalid([ProjectsProblem])
    /// No project has that path.
    case missing(String)
}

/// One project as the file has it: `json` is the whole entry, so a key the app has no property for is still there to be written back.
public struct ProjectEntry: Equatable {
    public let json: [String: Any]

    public static func == (a: ProjectEntry, b: ProjectEntry) -> Bool { NSDictionary(dictionary: a.json).isEqual(to: b.json) }

    /// The identity: absolute or `~`.
    public var path: String { json["path"] as? String ?? "" }
    public var name: String? { json["name"] as? String }
    /// `cloned`, `created` or `added`.
    public var origin: String { json["origin"] as? String ?? "" }
    public var pinned: Bool { json["pinned"] as? Bool ?? false }
    public var hidden: Bool { json["hidden"] as? Bool ?? false }
    public var tags: [String] { json["tags"] as? [String] ?? [] }
    public var actions: [ProjectAction] { projectActions(from: json["actions"]) }
}

private struct Field {
    let required: Bool
    let kind: Kind
    init(_ kind: Kind, required: Bool = false) { self.kind = kind; self.required = required }
}

private indirect enum Kind {
    case path, text, nonEmpty, bool, tags
    case choice([String])
    case object([String: Field])
    case list(Kind)
}

private let action: Kind = .object([
    "name": Field(.text, required: true), "command": Field(.text, required: true),
    "when": Field(.choice(["newWorktree", "afterClone"]), required: true), "on": Field(.bool), "onFail": Field(.choice(["warn", "stop"])),
])
private let entry: Kind = .object([
    "path": Field(.path, required: true), "name": Field(.text), "origin": Field(.choice(["cloned", "created", "added"]), required: true),
    "pinned": Field(.bool), "hidden": Field(.bool), "tags": Field(.tags),
    "icon": Field(.object(["color": Field(.nonEmpty), "mark": Field(.nonEmpty), "image": Field(.nonEmpty)])),
    "defaults": Field(.object(["agent": Field(.nonEmpty), "workIn": Field(.choice(["baseFolder", "worktree"])), "baseBranch": Field(.nonEmpty)])),
    "actions": Field(.list(action)),
])
private let file: Kind = .object(["projects": Field(.list(entry))])

private func isBool(_ value: Any) -> Bool { CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() }

private func problems(_ value: Any, _ kind: Kind, at path: String) -> [ProjectsProblem] {
    func problem(_ message: String, _ at: String = path) -> [ProjectsProblem] { [ProjectsProblem(path: at, message: message)] }
    func child(_ key: String) -> String { path.isEmpty ? key : path + "." + key }
    func blank(_ text: String) -> Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    switch kind {
    case .path:
        guard let text = value as? String else { return problem("must be a string") }
        return text.hasPrefix("/") || text == "~" || text.hasPrefix("~/") ? [] : problem("must be an absolute path or start with ~/")
    case .text:
        guard let text = value as? String else { return problem("must be a string") }
        return blank(text) ? problem("must not be blank") : []
    case .nonEmpty:
        guard let text = value as? String else { return problem("must be a string") }
        return text.isEmpty ? problem("must not be empty") : []
    case .bool:
        return isBool(value) ? [] : problem("must be true or false")
    case .choice(let allowed):
        guard let text = value as? String, allowed.contains(text) else { return problem("must be one of \(allowed.joined(separator: ", "))") }
        return []
    case .tags:
        guard let tags = value as? [Any] else { return problem("must be a list") }
        var found: [ProjectsProblem] = []
        for (index, tag) in tags.enumerated() {
            guard let text = tag as? String else { found += problem("must be a string", child(String(index))); continue }
            if blank(text) { found += problem("must not be blank", child(String(index))) }
            else if text != text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() { found += problem("must be trimmed and lower case", child(String(index))) }
        }
        let names = tags.compactMap { $0 as? String }
        return found.isEmpty && Set(names).count != names.count ? problem("must not repeat a tag") : found
    case .object(let fields):
        guard let object = value as? [String: Any] else { return problem("must be an object") }
        var found = object.keys.sorted().filter { fields[$0] == nil }.map { ProjectsProblem(path: child($0), message: "is not a key of projects.json") }
        for key in fields.keys.sorted() {
            guard let field = fields[key] else { continue }
            if let present = object[key] { found += problems(present, field.kind, at: child(key)) }
            else if field.required { found += problem("is required", child(key)) }
        }
        return found
    case .list(let item):
        guard let items = value as? [Any] else { return problem("must be a list") }
        return items.enumerated().flatMap { problems($1, item, at: child(String($0))) }
    }
}

private func parse(_ data: Data?) throws -> [String: Any] {
    guard let data else { return [:] }
    let json: Any
    do { json = try JSONSerialization.jsonObject(with: data) } catch {
        throw ProjectsFileError.invalid([ProjectsProblem(path: "(file)", message: "is not valid JSON")])
    }
    var found = problems(json, file, at: "")
    if found.isEmpty, let object = json as? [String: Any] {
        var seen = Set<String>()
        let projects = object["projects"] as? [[String: Any]] ?? []
        for (index, item) in projects.enumerated() where seen.insert(item["path"] as? String ?? "").inserted == false {
            found.append(ProjectsProblem(path: "projects.\(index).path", message: "repeats the path of an earlier project"))
        }
        if found.isEmpty { return object }
    }
    throw ProjectsFileError.invalid(found.map { $0.path.isEmpty ? ProjectsProblem(path: "(root)", message: $0.message) : $0 })
}

/// The entries of the file's bytes, nil being a file that is not there (no projects). Throws `invalid` naming each field that is wrong.
public func readProjects(_ data: Data?) throws -> [ProjectEntry] {
    (try parse(data)["projects"] as? [[String: Any]] ?? []).map(ProjectEntry.init(json:))
}

/// `json` with the key of the project at `path` set to `value`, or taken out when `value` is nil. Everything else in the file is left as it was.
/// The file is checked before and after: one that does not match, or an edit that would make it not match, throws `invalid` and gives nothing to write.
public func applyingProjectEdit(path: String, key: String, value: Any?, to json: Data?) throws -> Data {
    var object = try parse(json)
    var projects = object["projects"] as? [[String: Any]] ?? []
    guard let index = projects.firstIndex(where: { $0["path"] as? String == path }) else { throw ProjectsFileError.missing(path) }
    projects[index][key] = value
    object["projects"] = projects
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    _ = try parse(data)
    return data
}

/// What adding a folder did: it became an entry, or it already was one (its path as the file has it).
public enum ProjectAdd: Equatable, Sendable {
    case added(String)
    case existing(String)
}

/// The same folder written two ways: `~` expanded, symlinks resolved, no trailing slash. A project is its folder, so `~/work/a` and `/Users/me/work/a/` are one.
public func isSameFolder(_ a: String, _ b: String) -> Bool {
    func normal(_ path: String) -> String { URL(fileURLWithPath: (path as NSString).expandingTildeInPath).resolvingSymlinksInPath().path }
    return normal(a) == normal(b)
}

/// Adding the folder `folder` as a project of origin `added` named after it, in `json`: the bytes to write, nil when it already is a project (nothing
/// to write). The file is checked before and after, as an edit is, and every key it has is kept.
public func applyingProjectAdd(folder: String, to json: Data?) throws -> (outcome: ProjectAdd, write: Data?) {
    var object = try parse(json)
    var projects = object["projects"] as? [[String: Any]] ?? []
    if let known = projects.first(where: { isSameFolder($0["path"] as? String ?? "", folder) })?["path"] as? String { return (.existing(known), nil) }
    projects.append(["path": folder, "name": (folder as NSString).lastPathComponent, "origin": "added"])
    object["projects"] = projects
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    _ = try parse(data)
    return (.added(folder), data)
}

/// The file on disk.
public struct ProjectsFile {
    public let folder: String
    public let url: URL

    public init(folder: String) {
        self.folder = folder
        url = URL(fileURLWithPath: CarrierPlaces(folder: folder).projects)
    }

    /// The file of the folder the app works with (`CARRIER_HOME`, else `~/.carrier`), looked up each time.
    public static func current() -> ProjectsFile { ProjectsFile(folder: currentCarrierFolder()) }

    /// The bytes; nil when the file is not there, an error when it is there and cannot be read.
    private func bytes() throws -> Data? { FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil }

    public func read() throws -> [ProjectEntry] { try readProjects(bytes()) }

    /// Reads the file again now and adds `folder` as a project, or says it already is one and writes nothing. Makes the Carrier folder when it is not there yet.
    public func add(folder: String) throws -> ProjectAdd {
        let (outcome, data) = try applyingProjectAdd(folder: folder, to: bytes())
        if let data {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
        return outcome
    }

    /// Reads the file again now, changes one key of one project and writes the whole file through a temporary file that replaces it.
    public func update(path: String, key: String, value: Any?) throws {
        try applyingProjectEdit(path: path, key: key, value: value, to: bytes()).write(to: url, options: .atomic)
    }

    /// Reads the file again now, replaces the `actions` of `path` when all actions are valid, and writes the file atomically.
    /// Returns false without writing if any action has a blank name or command.
    @discardableResult public func updateActions(path: String, actions: [ProjectAction]) throws -> Bool {
        guard let data = try applyingProjectActions(actions, path: path, to: bytes()) else { return false }
        try data.write(to: url, options: .atomic)
        return true
    }
}
