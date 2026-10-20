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

public func controlSocketPath(
    environment: [String: String] = ProcessInfo.processInfo.environment, home: String = NSHomeDirectory()
) -> String {
    let config = try? Data(contentsOf: URL(fileURLWithPath: configFilePath(environment: environment, home: home)))
    return sharedRoot(configJSON: config, home: home) + "/orchestrator/control.sock"
}
