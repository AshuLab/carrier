import Foundation

// The GitHub identity the engine acts as: `orchestratorProfile` of `engine.json`, one of the file's `profiles`. Left out of the file it is the
// author's profile, so choosing the default removes the key. The choice is sent as `EngineConfigChange.orchestratorProfile`: the engine writes the file and runs on it.

public struct EngineIdentity: Equatable {
    /// The title of the choice that removes the key
    public static func defaultTitle(bundle: Bundle? = nil, locale: Locale = .current) -> String { Copy.lifecycleIdentityDefault(bundle: bundle, locale: locale) }

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
    public static func options(_ identity: EngineIdentity?, bundle: Bundle? = nil, locale: Locale = .current) -> [(value: String?, title: String)] {
        [(value: nil, title: defaultTitle(bundle: bundle, locale: locale))] + (identity?.choices ?? []).map { (value: $0, title: $0) }
    }
}
