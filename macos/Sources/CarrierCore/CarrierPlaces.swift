import Foundation

// Every path inside the Carrier folder is computed here and nowhere else (docs/adr/0034); no config file is read to find one.
// The top holds only the files a person edits; each process owns one subfolder, split inside by lifecycle.

/// The Carrier folder: `CARRIER_HOME` in the app's own environment, else `~/.carrier`.
public func carrierFolder(environment: [String: String], home: String) -> String {
    environment["CARRIER_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? home + "/.carrier"
}

/// The places of one Carrier folder.
public struct CarrierPlaces: Sendable, Equatable {
    public let folder: String

    public init(folder: String) { self.folder = folder }
    public init(environment: [String: String] = ProcessInfo.processInfo.environment, home: String = NSHomeDirectory()) {
        folder = carrierFolder(environment: environment, home: home)
    }

    // The files a person edits.
    /// The engine's config, the file the Behavior and Repos tabs edit.
    public var engineConfig: String { folder + "/engine.json" }
    public var chatConfig: String { folder + "/chat.json" }
    public var providers: String { folder + "/providers.json" }

    // The engine's: its clones, review checkouts, state and logs.
    public var engine: String { folder + "/engine" }
    public var engineLogs: String { engine + "/logs" }
    /// What the app saw the last time it started the engine.
    public var engineStartLog: String { engineLogs + "/app-start.log" }
    /// What the last Homebrew upgrade run from the app wrote.
    public var engineUpgradeLog: String { engineLogs + "/app-upgrade.log" }
    public var engineState: String { engine + "/state" }
    public var controlSocket: String { engineState + "/control.sock" }

    // The chat host's. It does not read the engine's config.
    public var chat: String { folder + "/chat" }
    public var chatState: String { chat + "/state" }
    public var chatLogs: String { chat + "/logs" }
    public var chatStartLog: String { chatLogs + "/app-start.log" }
    public var chatSocket: String { chatState + "/chat.sock" }
    public var chatWorktrees: String { chat + "/worktrees" }
    /// The default projects folder; `projectsFolder` in `chat.json` changes it.
    public var chatProjects: String { chat + "/projects" }
    /// The app's copies of the files a person attaches: `<id>/<name>`.
    public var chatAttachments: String { chat + "/attachments" }

    // The app's: state it keeps, its logs, and a cache that can be deleted and comes back.
    public var app: String { folder + "/app" }
    public var appState: String { app + "/state" }
    public var appLogs: String { app + "/logs" }
    public var appCache: String { app + "/cache" }
    public var terminals: String { appState + "/terminals.json" }
    public var dictations: String { appState + "/dictations.jsonl" }
    public var dictationStatistics: String { appState + "/dictation-statistics.json" }
    public var dictationAudio: String { appState + "/audio" }
    public var dictationLog: String { appLogs + "/dictation.log" }
    /// Downloaded speech models: `<recognizer>/<model>/`.
    public var speechModels: String { appCache + "/models" }
    /// The `ZDOTDIR` shim of the app's terminals, rewritten at each start.
    public var zshShim: String { appCache + "/zsh-bottom-prompt" }
}

/// The engine's config: `<folder>/engine.json`.
public func configFilePath(
    environment: [String: String] = ProcessInfo.processInfo.environment, home: String = NSHomeDirectory()
) -> String {
    CarrierPlaces(environment: environment, home: home).engineConfig
}

/// The engine's folder, `<folder>/engine`.
public func engineFolder(
    environment: [String: String] = ProcessInfo.processInfo.environment, home: String = NSHomeDirectory()
) -> String {
    CarrierPlaces(environment: environment, home: home).engine
}

/// The engine's control socket: `<folder>/engine/state/control.sock`.
public func controlSocketPath(
    environment: [String: String] = ProcessInfo.processInfo.environment, home: String = NSHomeDirectory()
) -> String {
    CarrierPlaces(environment: environment, home: home).controlSocket
}

/// The chat host's socket: `<folder>/chat/state/chat.sock`.
public func chatSocketPath(
    environment: [String: String] = ProcessInfo.processInfo.environment, home: String = NSHomeDirectory()
) -> String {
    CarrierPlaces(environment: environment, home: home).chatSocket
}
