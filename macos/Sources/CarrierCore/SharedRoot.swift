import Foundation

// Where Carrier's files live: the engine's places are computed from the Carrier folder (docs/adr/0016), no config file is read.

/// The Carrier folder: `CARRIER_HOME` in the app's own environment, else `~/.carrier`.
public func carrierFolder(environment: [String: String], home: String) -> String {
    environment["CARRIER_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? home + "/.carrier"
}

public func configFilePath(environment: [String: String], home: String) -> String {
    carrierFolder(environment: environment, home: home) + "/config.json"
}

/// The config file the app works with: `CARRIER_HOME` in the app's own environment (a dev run, the fixtures) wins, then the
/// one chosen in the setup, then the engine's default.
public func activeConfigPath(saved: SetupSettings?, environment: [String: String], home: String) -> String {
    if environment["CARRIER_HOME"].map({ $0.isEmpty == false }) == true { return configFilePath(environment: environment, home: home) }
    if let chosen = saved?.configPath, chosen.isEmpty == false { return chosen }
    return configFilePath(environment: environment, home: home)
}

/// The engine's folder, `<folder>/engine`: its clones, review checkouts, state and logs.
public func engineFolder(
    environment: [String: String] = ProcessInfo.processInfo.environment, home: String = NSHomeDirectory()
) -> String {
    carrierFolder(environment: environment, home: home) + "/engine"
}

/// The engine's control socket: `<folder>/engine/state/control.sock`.
public func controlSocketPath(
    environment: [String: String] = ProcessInfo.processInfo.environment, home: String = NSHomeDirectory()
) -> String {
    engineFolder(environment: environment, home: home) + "/state/control.sock"
}

/// The chat host's socket: `<folder>/chat/state/chat.sock`. It does not read the engine's config.
public func chatSocketPath(
    environment: [String: String] = ProcessInfo.processInfo.environment, home: String = NSHomeDirectory()
) -> String {
    carrierFolder(environment: environment, home: home) + "/chat/state/chat.sock"
}
