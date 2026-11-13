import Foundation

// The GitHub identity the engine acts as: `orchestratorProfile` of `config.json`, one of the file's `profiles`. Left out of the file it is the
// author's profile, so choosing the default removes the key. The engine is asked to reload after the write (EngineReload.swift).

public struct EngineIdentity: Equatable {
    /// The title of the choice that removes the key
    public static let defaultTitle = "Author's identity"

    /// The names `profiles` declares, in order
    public let declared: [String]
    /// `orchestratorProfile` as the file has it; nil when it is left out
    public let current: String?

    /// nil when `config` is not a JSON object.
    public init?(config: Data) {
        guard let file = (try? JSONSerialization.jsonObject(with: config)) as? [String: Any] else { return nil }
        declared = (file["profiles"] as? [String: Any] ?? [:]).keys.sorted()
        current = file["orchestratorProfile"] as? String
    }

    /// The profile the file names without declaring it: it stays on the list, so opening the page never changes it.
    public var undeclared: String? { current.flatMap { declared.contains($0) ? nil : $0 } }

    /// The profiles the choice lists after the default.
    public var choices: [String] { declared + (undeclared.map { [$0] } ?? []) }

    /// What the choice lists: the default (nil, which takes the key out) first, then `choices`. With no file to read it is the default alone.
    public static func options(_ identity: EngineIdentity?) -> [(value: String?, title: String)] {
        [(value: nil, title: defaultTitle)] + (identity?.choices ?? []).map { (value: $0, title: $0) }
    }
}

/// `json` with `orchestratorProfile` set to `name`, or taken out when `name` is nil (the default); the file's other keys are left as they were.
/// nil when `json` is not a JSON object: the app never makes a config file.
public func applyingOrchestratorProfile(_ name: String?, to json: Data) -> Data? {
    guard var file = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else { return nil }
    if let name { file["orchestratorProfile"] = name } else { file.removeValue(forKey: "orchestratorProfile") }
    return try? JSONSerialization.data(withJSONObject: file, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
}

/// Writes the choice into the file at `path`, read just now so another tab's save in between is not lost, and asks the engine to reload once it
/// is written. `.failed` when the file cannot be read or is not an object (nothing is written, nothing asked).
public func saveOrchestratorProfile(_ name: String?, path: String, reload: AfterWrite = reloadInBackground) -> RoleSave {
    saveConfig(path: path, unusable: "The config file could not be read.", edit: { applyingOrchestratorProfile(name, to: $0) }, reload: reload)
}
