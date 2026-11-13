import Foundation

// The Engine page of Settings (docs/specs/engine-in-settings.md): its groups, rows, titles and descriptions as plain values. The view only
// draws this; the later groups of the page add themselves here.

/// The row a view has to draw for. The Starting rows are switches over an app preference, the Files rows a button over a path.
public enum EngineRowID: Equatable {
    case startOnOpen, confirmStop, carrierFolder, logs, startLog
}

/// A Files row's path: `shown` is in the person's words (`~`), `path` is what Reveal or Open acts on, and `exists` is false while there is nothing there yet.
public struct EngineFile: Equatable {
    public enum Action: Equatable { case reveal, open }
    public let shown: String
    public let path: String
    public let action: Action
    public let exists: Bool
    /// The button's words: its verb, or "Not created yet" (the button is disabled) while the path is missing.
    public var buttonTitle: String { exists ? (action == .reveal ? "Reveal" : "Open") : "Not created yet" }
}

public struct EngineRow: Equatable {
    public let id: EngineRowID
    public let title: String
    public let detail: String
    public var file: EngineFile?
}

public struct EngineGroup: Equatable {
    public let title: String
    public let rows: [EngineRow]
}

/// `configured` is whether the engine has a config file: without one, starting when the app opens does nothing and the row says so.
/// `folder` is the Carrier folder; `exists` says whether a path is there (a folder or a file).
public func engineGroups(configured: Bool, folder: String, home: String, exists: (String) -> Bool) -> [EngineGroup] {
    func file(_ id: EngineRowID, _ title: String, _ detail: String, _ path: String, _ action: EngineFile.Action) -> EngineRow {
        EngineRow(id: id, title: title, detail: detail, file: EngineFile(shown: tildePath(path, home: home), path: path, action: action, exists: exists(path)))
    }
    let logs = folder + "/engine/logs"
    return [
        EngineGroup(title: "Starting", rows: [
            EngineRow(
                id: .startOnOpen, title: "Start Carrier when the app opens",
                detail: configured ? "Carrier starts working on ready epics as soon as the app opens" : "Does nothing until the engine is configured"
            ),
            EngineRow(id: .confirmStop, title: "Ask before stopping Carrier", detail: "Only when stopping would interrupt epics that are running"),
        ]),
        EngineGroup(title: "Files", rows: [
            file(.carrierFolder, "Carrier folder", "Where Carrier keeps its config, clones and logs", folder, .reveal),
            file(.logs, "Logs", "What Carrier wrote while it ran", logs, .reveal),
            file(.startLog, "Start log", "What the app saw the last time it started Carrier", logs + "/app-start.log", .open),
        ]),
    ]
}
