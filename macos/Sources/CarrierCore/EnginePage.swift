import Foundation

// The Engine page of Settings (docs/specs/engine-in-settings.md): its groups, rows, titles and descriptions as plain values. The view only
// draws this; the later groups of the page add themselves here.

/// The row a view has to draw for. The Starting rows are switches over an app preference; the Programs rows are `carrier`, `node`, the `PATH`
/// and the button that looks for the tools again; `orchestratorProfile` is a choice written to `config.json`, the Files rows a button over a path.
public enum EngineRowID: Equatable {
    case startOnOpen, confirmStop
    case carrier, node, path, lookAgain
    case orchestratorProfile, carrierFolder, logs, startLog
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
    /// The quiet monospaced line under the detail: a path, or "Not found" in its place.
    public var note: String?
    /// The `carrier` row only: the person set their own, so the row offers "Use the Homebrew one".
    public var offersHomebrew = false
    /// What is wrong with the value, shown in orange in the place of the detail
    public var problem: String?
    public var file: EngineFile?
}

/// What the Programs group says about, all of it read by the caller: the paths and versions are inputs so the model is tested without a window.
public struct EnginePrograms: Equatable {
    public var carrier: String?
    /// The person's own `carrier` is set ("Use another…" on the `carrier` row).
    public var carrierIsOwn: Bool
    public var carrierVersion: String?
    public var setup: SetupSettings
    public var nodeVersion: String?

    public init(carrier: String?, carrierIsOwn: Bool, carrierVersion: String?, setup: SetupSettings, nodeVersion: String?) {
        self.carrier = carrier
        self.carrierIsOwn = carrierIsOwn
        self.carrierVersion = carrierVersion
        self.setup = setup
        self.nodeVersion = nodeVersion
    }
}

public struct EngineGroup: Equatable {
    public let title: String
    public let rows: [EngineRow]
}

/// `configured` is whether the engine has a config file: without one, starting when the app opens does nothing and the row says so.
/// `programs` is what the Programs group shows, all of it read by the caller.
/// `identity` is what that file says about the GitHub identity, nil when there is no file or it cannot be read (the row is then disabled by the view).
/// `folder` is the Carrier folder; `exists` says whether a path is there (a folder or a file).
public func engineGroups(
    configured: Bool, programs: EnginePrograms, identity: EngineIdentity?, folder: String, home: String, exists: (String) -> Bool
) -> [EngineGroup] {
    func file(_ id: EngineRowID, _ title: String, _ detail: String, _ path: String, _ action: EngineFile.Action) -> EngineRow {
        EngineRow(id: id, title: title, detail: detail, file: EngineFile(shown: tildePath(path, home: home), path: path, action: action, exists: exists(path)))
    }
    let places = ["CARRIER_HOME": folder]
    return [
        EngineGroup(title: "Starting", rows: [
            EngineRow(
                id: .startOnOpen, title: "Start Carrier when the app opens",
                detail: configured ? "Carrier starts working on ready epics as soon as the app opens" : "Does nothing until the engine is configured"
            ),
            EngineRow(id: .confirmStop, title: "Ask before stopping Carrier", detail: "Only when stopping would interrupt epics that are running"),
        ]),
        EngineGroup(title: "Programs", rows: programRows(programs)),
        EngineGroup(title: "GitHub identity", rows: [
            EngineRow(
                id: .orchestratorProfile, title: "Carrier acts on GitHub as",
                detail: configured ? "Reads issues and PRs and changes labels. Default is the author's identity" : "Available once the engine is configured",
                problem: identityProblem(configured: configured, identity: identity)
            ),
        ]),
        EngineGroup(title: "Files", rows: [
            file(.carrierFolder, "Carrier folder", "Where Carrier keeps its config, clones and logs", folder, .reveal),
            file(.logs, "Logs", "What Carrier wrote while it ran", engineLogsFolder(environment: places, home: home), .reveal),
            file(.startLog, "Start log", "What the app saw the last time it started Carrier", engineStartLogPath(environment: places, home: home), .open),
        ]),
    ]
}

/// A file that is there but is not a JSON object says so; one that names an undeclared profile says it is kept.
private func identityProblem(configured: Bool, identity: EngineIdentity?) -> String? {
    guard let identity else { return configured ? "config.json in the Carrier folder could not be read or is not a JSON object" : nil }
    return identity.undeclared.map { "“\($0)” is not in profiles; it is kept until you pick another" }
}

private func programRows(_ programs: EnginePrograms) -> [EngineRow] {
    let setup = programs.setup
    let carrierLine = [programs.carrierIsOwn ? "Your own carrier" : nil, programs.carrier == nil ? nil : programs.carrierVersion.map { "Version \($0)" }]
        .compactMap { $0 }.joined(separator: " · ")
    let nodeFound = setup.node.isEmpty == false
    let path = enginePath(detected: setup.path, node: setup.node)
    return [
        EngineRow(
            id: .carrier, title: "carrier", detail: carrierLine, note: programs.carrier ?? "Not found", offersHomebrew: programs.carrierIsOwn
        ),
        EngineRow(
            id: .node, title: "node", detail: nodeFound ? programs.nodeVersion.map { "Version \($0.trimmingPrefix("v"))" } ?? "" : "",
            note: nodeFound ? setup.node : "Not found"
        ),
        EngineRow(
            id: .path, title: "PATH",
            detail: setup.path.isEmpty ? "Not found yet, so the engine and the chat host start from the system's" : "What the engine and the chat host run with",
            note: path
        ),
        EngineRow(
            id: .lookAgain, title: "Look for the tools again",
            detail: "Asks your shell where node and the PATH are. Use it after installing a tool while the app was open"
        ),
    ]
}
