import Foundation

// The Engine tab of Settings as plain values: the readiness banner and the paths, each found or not
// (docs/specs/macos-app-redesign.md, story 30). The views map them one to one; the values are the saved `SetupSettings`.

/// The three values the app starts Carrier with, in the order the tab lists them.
public enum EngineField: CaseIterable {
    case carrier, node, path
}

extension SetupSettings {
    public subscript(field: EngineField) -> String {
        get {
            switch field {
            case .carrier: carrier
            case .node: node
            case .path: path
            }
        }
        set {
            switch field {
            case .carrier: carrier = newValue
            case .node: node = newValue
            case .path: path = newValue
            }
        }
    }
}

public struct EngineRow: Equatable {
    /// What the row's button asks for.
    public enum Choice: Equatable { case file, folder, edit }

    public var field: EngineField
    public var title: String
    public var hint: String
    /// What the row shows (a path with the home folder as `~`); nil is a value not found.
    public var value: String?
    public var choice: Choice
    /// The path Reveal opens in Finder; nil for a value that is not a path or not found.
    public var revealPath: String?

    public var found: Bool { value != nil }
}

public struct ReadinessBanner: Equatable {
    public enum State: Equatable { case ready, missing, detecting }

    public var state: State
    public var title: String
    public var detail: String
}

public struct EngineTabModel: Equatable {
    public var banner: ReadinessBanner
    public var rows: [EngineRow]
}

/// Whether the Engine tab lists the paths: always when something needs the person (a path missing, or detecting), and when all
/// is found only after they asked to see them.
public func enginePathsShown(_ banner: ReadinessBanner, opened: Bool) -> Bool {
    banner.state != .ready || opened
}

public func engineTab(_ settings: SetupSettings, detecting: Bool, home: String = NSHomeDirectory()) -> EngineTabModel {
    func shown(_ path: String) -> String {
        path == home ? "~" : path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
    func row(_ field: EngineField, _ title: String, _ hint: String, _ choice: EngineRow.Choice) -> EngineRow {
        let path = settings[field]
        return EngineRow(
            field: field, title: title, hint: hint, value: path.isEmpty ? nil : shown(path), choice: choice,
            revealPath: path.isEmpty ? nil : path
        )
    }
    var pathRow = row(.path, "PATH", "What Carrier gets when the app starts it", .edit)
    if settings.path.isEmpty == false {
        let folders = enginePath(detected: settings.path, node: settings.node).split(separator: ":").count
        pathRow.value = "\(folders) \(folders == 1 ? "folder" : "folders") · node’s folder first"
        pathRow.revealPath = nil
    }
    let rows = [
        row(.carrier, "Carrier", "The script that starts Carrier", .file),
        row(.node, "Node", "Runs Carrier", .file),
        pathRow,
    ]

    let banner: ReadinessBanner
    let missing = startMissing(settings)
    if detecting {
        banner = ReadinessBanner(state: .detecting, title: "Looking for what Carrier needs", detail: "Asking your shell, this takes a few seconds.")
    } else if missing.isEmpty {
        banner = ReadinessBanner(state: .ready, title: "Start Carrier is ready", detail: "Everything it needs was found.")
    } else {
        let names = missing.count > 1 ? missing.dropLast().joined(separator: ", ") + " and " + missing.last! : missing[0]
        banner = ReadinessBanner(
            state: .missing, title: "Start Carrier needs \(names)",
            detail: "Choose where it is, or run Detect again if you just installed it."
        )
    }
    return EngineTabModel(banner: banner, rows: rows)
}
