import Foundation

// `projects.json` in the Carrier folder (docs/adr/0041): the person's projects, read by the app and written by the chat host (ADR 0053).
// The rules below are `src/config/projects.ts`'s, field by field; `ContractTests` runs the fixture its test writes through both. A file that
// does not match is reported with the field named.

/// A field that is wrong and why. `path` is the key's place in the file (`projects.1.name`), `(root)` for the file itself.
public struct ProjectsProblem: Equatable, Sendable {
    public let path: String
    public let message: String
}

public enum ProjectsFileError: Error, Equatable {
    /// The file is there and does not match its schema, or cannot be read, or an edit would make it not match: nothing was written.
    case invalid([ProjectsProblem])
    /// No project has that path (the fixture host's refusal).
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
    public var iconColor: String? { (json["icon"] as? [String: Any])?["color"] as? String }
    public var iconMark: String? { (json["icon"] as? [String: Any])?["mark"] as? String }
    public var iconImage: String? { (json["icon"] as? [String: Any])?["image"] as? String }
    public var actions: [ProjectAction] { projectActions(from: json["actions"]) }
    /// What a new session here starts with; a key that is not there, or a value the app has no name for, is unset.
    public var defaults: ProjectDefaults {
        let found = json["defaults"] as? [String: Any] ?? [:]
        return ProjectDefaults(
            agent: found["agent"] as? String,
            model: found["model"] as? String,
            effort: found["effort"] as? String,
            access: found["access"] as? [String: String] ?? [:],
            workIn: (found["workIn"] as? String).flatMap { WorkIn(projectValue: $0) },
            baseBranch: found["baseBranch"] as? String
        )
    }
}

/// The agent (with its model, reasoning and access), where to work and the base branch a new session in a project starts with (`defaults` of its
/// entry); nil is the same as everywhere. The model, reasoning and access go with the agent: they are only read when it is named.
public struct ProjectDefaults: Equatable, Sendable {
    public var agent: String?
    public var model: String?
    public var effort: String?
    /// The provider's access options by their option id (Claude's permission mode, Codex's approvals and sandbox).
    public var access: [String: String]
    public var workIn: WorkIn?
    public var baseBranch: String?

    public init(agent: String? = nil, model: String? = nil, effort: String? = nil, access: [String: String] = [:], workIn: WorkIn? = nil, baseBranch: String? = nil) {
        self.agent = agent
        self.model = model
        self.effort = effort
        self.access = access
        self.workIn = workIn
        self.baseBranch = baseBranch
    }
}

private struct Field {
    let required: Bool
    let kind: Kind
    init(_ kind: Kind, required: Bool = false) { self.kind = kind; self.required = required }
}

private indirect enum Kind {
    case path, text, nonEmpty, bool, tags
    /// an object whose every value is a non-empty string, under any key
    case stringMap
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
    "defaults": Field(.object(["agent": Field(.nonEmpty), "model": Field(.nonEmpty), "effort": Field(.nonEmpty), "access": Field(.stringMap), "workIn": Field(.choice(["baseFolder", "worktree"])), "baseBranch": Field(.nonEmpty)])),
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
    case .stringMap:
        guard let object = value as? [String: Any] else { return problem("must be an object") }
        return object.keys.sorted().flatMap { problems(object[$0] as Any, .nonEmpty, at: child($0)) }
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

/// What adding a folder did: it became an entry, or it already was one (its path as the file has it).
public enum ProjectAdd: Equatable, Sendable {
    case added(String)
    case existing(String)
}

/// The same folder written two ways: `~` expanded, symlinks resolved, no trailing slash. A project is its folder, so `~/work/a` and `/Users/me/work/a/` are one.
public func isSameFolder(_ a: String, _ b: String) -> Bool { normalizedFolder(a) == normalizedFolder(b) }

/// A folder written one way whatever it was written as: `~` expanded, symlinks resolved, no trailing slash.
public func normalizedFolder(_ path: String) -> String {
    URL(fileURLWithPath: (path as NSString).expandingTildeInPath).resolvingSymlinksInPath().path
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
}

extension WorkIn {
    /// The words `projects.json` uses for it in `defaults.workIn`.
    public var projectValue: String { self == .newWorktree ? "worktree" : "baseFolder" }

    public init?(projectValue: String) {
        guard let found = WorkIn.allCases.first(where: { $0.projectValue == projectValue }) else { return nil }
        self = found
    }
}
