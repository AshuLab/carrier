import Foundation

// A project's actions (docs/specs/projects.md, Scope 16; docs/adr/0039): commands kept in `projects.json` (never in the repository) and run
// when a new worktree is made or after a clone ends.

/// When an action runs: after making a worktree (or restoring a cleaned one), or after cloning the repository.
public enum ProjectActionWhen: String, CaseIterable, Equatable, Sendable {
    case newWorktree
    case afterClone

    public var title: String {
        switch self {
        case .newWorktree: "New worktree"
        case .afterClone: "After clone"
        }
    }
}

/// What happens when an action exits non-zero: warn and continue (the default), or stop the session preparation.
public enum ProjectActionOnFail: String, CaseIterable, Equatable, Sendable {
    case warn
    case stop

    public var title: String {
        switch self {
        case .warn: "Warn and continue"
        case .stop: "Stop the session"
        }
    }
}

/// The schema's defaults (`src/config/projects.ts`, docs/adr/0039); values equal to them are omitted when writing `projects.json`.
public let defaultProjectActionOn = true
public let defaultProjectActionOnFail = ProjectActionOnFail.warn

/// One action of a project's entry in `projects.json`.
public struct ProjectAction: Equatable, Sendable {
    public var name: String
    public var command: String
    public var when: ProjectActionWhen
    public var on: Bool
    public var onFail: ProjectActionOnFail

    public init(
        name: String = "",
        command: String = "",
        when: ProjectActionWhen,
        on: Bool = defaultProjectActionOn,
        onFail: ProjectActionOnFail = defaultProjectActionOnFail
    ) {
        self.name = name
        self.command = command
        self.when = when
        self.on = on
        self.onFail = onFail
    }
}

/// One action being edited on the Actions screen: carries a stable `id` so typing keeps focus across edits and reloads.
public struct ProjectActionDraft: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var action: ProjectAction

    public init(id: UUID = UUID(), action: ProjectAction) {
        self.id = id
        self.action = action
    }
}

public enum ProjectActionField: Equatable, Hashable, Sendable { case name, command }

/// What is wrong with an action, by field, in words; empty when both name and command contain non-whitespace characters.
public func projectActionProblems(_ action: ProjectAction) -> [ProjectActionField: String] {
    var problems: [ProjectActionField: String] = [:]
    if action.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        problems[.name] = "Name must not be blank"
    }
    if action.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        problems[.command] = "Command must not be blank"
    }
    return problems
}

/// Actions decoded from the `actions` array of a `projects.json` entry, filling defaults when `on` or `onFail` are absent.
public func projectActions(from raw: Any?) -> [ProjectAction] {
    guard let items = raw as? [[String: Any]] else { return [] }
    return items.compactMap { item in
        guard let name = item["name"] as? String,
              let command = item["command"] as? String,
              let whenRaw = item["when"] as? String,
              let when = ProjectActionWhen(rawValue: whenRaw)
        else { return nil }
        let on = item["on"] as? Bool ?? defaultProjectActionOn
        let onFail = (item["onFail"] as? String).flatMap(ProjectActionOnFail.init(rawValue:)) ?? defaultProjectActionOnFail
        return ProjectAction(name: name, command: command, when: when, on: on, onFail: onFail)
    }
}

/// Encodes one action for `projects.json`, omitting `on` and `onFail` when they equal their defaults. nil when name or command is blank.
public func encodedProjectAction(_ action: ProjectAction) -> [String: Any]? {
    guard projectActionProblems(action).isEmpty else { return nil }
    var object: [String: Any] = [
        "name": action.name,
        "command": action.command,
        "when": action.when.rawValue,
    ]
    if action.on != defaultProjectActionOn { object["on"] = action.on }
    if action.onFail != defaultProjectActionOnFail { object["onFail"] = action.onFail.rawValue }
    return object
}

/// What should be written to `projects.json` from the editor's current drafts: valid drafts are written, a newly added invalid draft is omitted,
/// and a previously saved draft whose name or command was cleared keeps its last valid saved value so transient edits do not erase it.
public func mergedProjectActions(drafts: [ProjectActionDraft], saved: [UUID: ProjectAction]) -> [ProjectAction] {
    drafts.compactMap { draft in
        projectActionProblems(draft.action).isEmpty ? draft.action : saved[draft.id]
    }
}

/// Summary text shown on the project page's Actions row.
public func projectActionsSummary(_ count: Int) -> String {
    switch count {
    case 0: "None"
    case 1: "1 action"
    default: "\(count) actions"
    }
}
