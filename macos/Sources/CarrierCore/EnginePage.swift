import Foundation

// The Engine page of Settings (docs/specs/engine-in-settings.md): its groups, rows, titles and descriptions as plain values. The view only
// draws this; the later groups of the page add themselves here.

/// The row a view has to draw for. Both Starting rows are switches over an app preference; `orchestratorProfile` is a choice written to `config.json`.
public enum EngineRowID: Equatable {
    case startOnOpen, confirmStop, orchestratorProfile
}

public struct EngineRow: Equatable {
    public let id: EngineRowID
    public let title: String
    public let detail: String
    /// What is wrong with the value, shown in orange in the place of the detail
    public var problem: String?
}

public struct EngineGroup: Equatable {
    public let title: String
    public let rows: [EngineRow]
}

/// `configured` is whether the engine has a config file: without one, starting when the app opens does nothing and the row says so.
/// `identity` is what that file says about the GitHub identity, nil when the file cannot be read (the row is then disabled by the view).
public func engineGroups(configured: Bool, identity: EngineIdentity?) -> [EngineGroup] {
    [
        EngineGroup(title: "Starting", rows: [
            EngineRow(
                id: .startOnOpen, title: "Start Carrier when the app opens",
                detail: configured ? "Carrier starts working on ready epics as soon as the app opens" : "Does nothing until the engine is configured"
            ),
            EngineRow(id: .confirmStop, title: "Ask before stopping Carrier", detail: "Only when stopping would interrupt epics that are running"),
        ]),
        EngineGroup(title: "GitHub identity", rows: [
            EngineRow(
                id: .orchestratorProfile, title: "Carrier acts on GitHub as",
                detail: identity == nil ? "Available once the engine is configured" : "Reads issues and PRs and changes labels. Default is the author's identity",
                problem: identity?.undeclared.map { "“\($0)” is not in profiles; it is kept until you pick another" }
            ),
        ]),
    ]
}
