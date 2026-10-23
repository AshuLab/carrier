import Foundation

// Where Carrier's control socket lives: the engine's own rule (src/config/default-path.ts and schema.ts), read from the config file's content.

public func configFilePath(environment: [String: String], home: String) -> String {
    let carrierHome = environment["CARRIER_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? home + "/.carrier"
    return carrierHome + "/config.json"
}

/// The `root` of the config file with `~` expanded; `~/.solve` when the file is missing, is not JSON or has no usable `root`.
public func sharedRoot(configJSON: Data?, home: String) -> String {
    let object = configJSON.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
    let root = (object?["root"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "~/.solve"
    if root == "~" { return home }
    return root.hasPrefix("~/") ? home + root.dropFirst() : root
}

/// The `root` of the config file at `configPath`, as `sharedRoot` reads it.
public func configRoot(configPath: String, home: String) -> String {
    sharedRoot(configJSON: try? Data(contentsOf: URL(fileURLWithPath: configPath)), home: home)
}

/// The config file the app works with: `CARRIER_HOME` in the app's own environment (a dev run, the fixtures) wins, then the
/// one chosen in the setup, then the engine's default. The root is never saved: it is read from that file each time.
public func activeConfigPath(saved: SetupSettings?, environment: [String: String], home: String) -> String {
    if environment["CARRIER_HOME"].map({ $0.isEmpty == false }) == true { return configFilePath(environment: environment, home: home) }
    if let chosen = saved?.configPath, chosen.isEmpty == false { return chosen }
    return configFilePath(environment: environment, home: home)
}

/// Tests pass `saved: nil`; the app reads what the person saved, so a changed config file is followed at once.
public func controlSocketPath(
    saved: SetupSettings? = SetupStore().load(),
    environment: [String: String] = ProcessInfo.processInfo.environment, home: String = NSHomeDirectory()
) -> String {
    let configPath = activeConfigPath(saved: saved, environment: environment, home: home)
    return configRoot(configPath: configPath, home: home) + "/orchestrator/control.sock"
}
