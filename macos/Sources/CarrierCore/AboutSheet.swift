import Foundation

// The About sheet's texts (docs/specs/macos-app-redesign.md, story 31): the version comes from the app bundle, the
// connection line and the icon's dot from the state of Carrier. No diagnostics here.

public struct AboutLink: Equatable {
    public var title: String
    public var url: URL
}

public struct AboutSheet: Equatable {
    public var name: String
    public var version: String
    /// "Connected", "Stopped", "Incompatible version" or "Connecting…"
    public var connection: String
    /// The icon's dot: green when connected, grey otherwise.
    public var connected: Bool
    public var summary: String
    public var links: [AboutLink]
    public var footer: String
}

/// `version` and `build` are the bundle's `CFBundleShortVersionString` and `CFBundleVersion`; both are nil outside a bundle. `state` is nil until Carrier first answers.
public func aboutSheet(version: String?, build: String?, state: ConnectionState?) -> AboutSheet {
    let versionLine = switch (version, build) {
    case (let version?, let build?): "Version \(version) (\(build))"
    case (let version?, nil): "Version \(version)"
    case (nil, let build?): "Build \(build)"
    case (nil, nil): "Version unknown"
    }
    let connection = switch state {
    case .running?: "Connected"
    case .stopped?: "Stopped"
    case .incompatible?: "Incompatible version"
    case nil: "Connecting…"
    }
    let links = [
        ("GitHub", "https://github.com/AshuLab/carrier"),
        ("Documentation", "https://github.com/AshuLab/carrier/tree/main/docs"),
        ("Release notes", "https://github.com/AshuLab/carrier/releases"),
    ].compactMap { title, url in browserURL(url).map { AboutLink(title: title, url: $0) } }
    var connected = false
    if case .running? = state { connected = true }
    return AboutSheet(
        name: "Carrier", version: versionLine, connection: connection, connected: connected,
        summary: "Menu bar app for the Carrier orchestrator. The engine runs on its own; this app watches it and controls it.",
        links: links, footer: "© 2026 AshuLab · Signed ad hoc"
    )
}

/// What can happen to the open sheet.
public enum AboutInput {
    case escape
    case clickOutside
    case clickInside
}
