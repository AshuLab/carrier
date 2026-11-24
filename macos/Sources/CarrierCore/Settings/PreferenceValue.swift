import Foundation

/// A value that user defaults hold under a preference's name: read as nil when nothing valid is saved there, so the caller falls back to the
/// preference's default. The enums of `Preferences.generated.swift` conform to it through their raw value.
public protocol PreferenceValue {
    static func read(_ defaults: UserDefaults, _ name: String) -> Self?
    func write(_ defaults: UserDefaults, _ name: String)
}

extension Bool: PreferenceValue {
    public static func read(_ defaults: UserDefaults, _ name: String) -> Bool? { defaults.object(forKey: name) as? Bool }
    public func write(_ defaults: UserDefaults, _ name: String) { defaults.set(self, forKey: name) }
}

extension Int: PreferenceValue {
    public static func read(_ defaults: UserDefaults, _ name: String) -> Int? { defaults.object(forKey: name) as? Int }
    public func write(_ defaults: UserDefaults, _ name: String) { defaults.set(self, forKey: name) }
}

extension Double: PreferenceValue {
    public static func read(_ defaults: UserDefaults, _ name: String) -> Double? { defaults.object(forKey: name) as? Double }
    public func write(_ defaults: UserDefaults, _ name: String) { defaults.set(self, forKey: name) }
}

extension String: PreferenceValue {
    public static func read(_ defaults: UserDefaults, _ name: String) -> String? { defaults.string(forKey: name) }
    public func write(_ defaults: UserDefaults, _ name: String) { defaults.set(self, forKey: name) }
}

extension PreferenceValue where Self: RawRepresentable, RawValue == String {
    public static func read(_ defaults: UserDefaults, _ name: String) -> Self? { defaults.string(forKey: name).flatMap(Self.init(rawValue:)) }
    public func write(_ defaults: UserDefaults, _ name: String) { defaults.set(rawValue, forKey: name) }
}
