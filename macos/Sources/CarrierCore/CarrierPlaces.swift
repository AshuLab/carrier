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
    public var controlSocket: String { engine + "/state/control.sock" }

    // The chat host's. It does not read the engine's config.
    public var chat: String { folder + "/chat" }
    public var chatState: String { chat + "/state" }
    public var chatLogs: String { chat + "/logs" }
    public var chatStartLog: String { chatLogs + "/app-start.log" }
    public var chatSocket: String { chatState + "/chat.sock" }
    public var chatWorktrees: String { chat + "/worktrees" }
    /// The default projects folder; `projectsFolder` in `chat.json` changes it.
    public var chatProjects: String { chat + "/projects" }
    /// The app's copies of the files a person attaches, until the message goes: `<id>/<name>`. The host then moves each one into
    /// `chat/sessions/<session>/attachments/` and sweeps what was never sent after a day.
    public var chatPending: String { chat + "/pending" }

    // The app's: state it keeps, its logs, and a cache that can be deleted and comes back.
    public var app: String { folder + "/app" }
    public var appState: String { app + "/state" }
    public var appLogs: String { app + "/logs" }
    /// Kept out of Time Machine (`prepareAppCache`).
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

/// Makes the app's cache folder and marks it excluded from backups, before anything is written in it: what is there downloads again.
@discardableResult
public func prepareAppCache(_ places: CarrierPlaces, fileManager: FileManager = .default) -> Bool {
    var url = URL(fileURLWithPath: places.appCache, isDirectory: true)
    do {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        return true
    } catch {
        FileHandle.standardError.write(Data("carrier: the app cache could not be kept out of backups: \(error)\n".utf8))
        return false
    }
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
