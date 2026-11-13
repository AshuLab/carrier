import Foundation

// The Engine page of Settings (docs/specs/engine-in-settings.md): its groups, rows, titles and descriptions as plain values. The view only
// draws this; the later groups of the page add themselves here.

/// The row a view has to draw for. The Starting rows are switches over an app preference; the Programs rows are `carrier`, `node`, the `PATH`
/// and the button that looks for the tools again.
public enum EngineRowID: Equatable {
    case startOnOpen, confirmStop
    case carrier, node, path, lookAgain
}

public struct EngineRow: Equatable {
    public let id: EngineRowID
    public let title: String
    public let detail: String
    /// The quiet monospaced line under the detail: a path, or "Not found" in its place.
    public var note: String?
    /// The `carrier` row only: the person set their own, so the row offers "Use the Homebrew one".
    public var offersHomebrew = false
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
public func engineGroups(configured: Bool, programs: EnginePrograms) -> [EngineGroup] {
    [
        EngineGroup(title: "Starting", rows: [
            EngineRow(
                id: .startOnOpen, title: "Start Carrier when the app opens",
                detail: configured ? "Carrier starts working on ready epics as soon as the app opens" : "Does nothing until the engine is configured"
            ),
            EngineRow(id: .confirmStop, title: "Ask before stopping Carrier", detail: "Only when stopping would interrupt epics that are running"),
        ]),
        EngineGroup(title: "Programs", rows: programRows(programs)),
    ]
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
