import Foundation

// The Engine page of Settings (docs/specs/engine-in-settings.md): its groups, rows, titles and descriptions as plain values. The view only
// draws this; the later groups of the page add themselves here.

/// The row a view has to draw for. Both Starting rows are switches over an app preference.
public enum EngineRowID: Equatable {
    case startOnOpen, confirmStop
}

public struct EngineRow: Equatable {
    public let id: EngineRowID
    public let title: String
    public let detail: String
}

public struct EngineGroup: Equatable {
    public let title: String
    public let rows: [EngineRow]
}

/// `configured` is whether the engine has a config file: without one, starting when the app opens does nothing and the row says so.
public func engineGroups(configured: Bool) -> [EngineGroup] {
    [
        EngineGroup(title: "Starting", rows: [
            EngineRow(
                id: .startOnOpen, title: "Start Carrier when the app opens",
                detail: configured ? "Carrier starts working on ready epics as soon as the app opens" : "Does nothing until the engine is configured"
            ),
            EngineRow(id: .confirmStop, title: "Ask before stopping Carrier", detail: "Only when stopping would interrupt epics that are running"),
        ])
    ]
}
