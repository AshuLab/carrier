import Foundation

/// The App group's preferences, kept in user defaults so they hold across a relaunch: each with its default, and a bad saved value
/// reads as the default. The keys are the ones that already existed, so nothing a person set is lost.
public struct AppPreferences {
    let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// What a preference holds: the saved value, or its default while none is saved or the saved one is not valid.
    public func value<V: PreferenceValue>(_ key: PreferenceKey<V>) -> V { V.read(defaults, key.name) ?? key.defaultValue }

    public func store<V: PreferenceValue>(_ value: V, for key: PreferenceKey<V>) { value.write(defaults, key.name) }

    /// What an optional preference holds: nil while none is saved or the saved one is not valid.
    public func value<V: PreferenceValue>(_ key: OptionalPreferenceKey<V>) -> V? { V.read(defaults, key.name) }

    /// Keeps the value of an optional preference, or takes it out for nil (`@AppStorage` has no optional `Double`).
    public func store<V: PreferenceValue>(_ value: V?, for key: OptionalPreferenceKey<V>) {
        if let value { value.write(defaults, key.name) } else { defaults.removeObject(forKey: key.name) }
    }

    /// The page Settings was left on: state, not a preference, so the schema has no entry for it and no page's Reset takes it out.
    public var lastSettingsPage: SettingsPage {
        get { defaults.string(forKey: Self.lastSettingsPageKey).flatMap(SettingsPage.init(rawValue:)) ?? .general }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.lastSettingsPageKey) }
    }

    private static let lastSettingsPageKey = "settingsLastPage"

    /// Takes the keys of one page out (the schema says which: `design/preferences.json`), so it reads as its defaults again; the other pages are not touched.
    public func reset(_ page: SettingsPage) { Preference.reset(page, in: defaults) }
}

/// The provider (a chat agent's name), model and reasoning a new session opens with, and what it may do (the options about access, by the
/// provider's own option id: Claude's permission mode, Codex's approvals and sandbox); an empty one is the provider's own.
public struct NewSessionStart: Equatable {
    public var agent: String
    public var model: String
    public var effort: String
    public var access: [String: String]

    public init(agent: String = "", model: String = "", effort: String = "", access: [String: String] = [:]) {
        self.agent = agent
        self.model = model
        self.effort = effort
        self.access = access
    }

    /// The access as it is kept in a preference: a JSON object of option and value. Anything else reads as none.
    public static func access(fromJSON text: String) -> [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: Data(text.utf8))) ?? [:]
    }

    public static func json(fromAccess access: [String: String]) -> String {
        (try? JSONEncoder().encode(access)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }
}

/// Stop asks first only when it interrupts epics and the person did not switch the question off.
public func asksBeforeStopping(_ snapshot: PanelSnapshot, switchOn: Bool) -> Bool {
    switchOn && snapshot.stopNeedsConfirmation
}
