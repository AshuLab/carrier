import Foundation

/// The three Menu bar settings, kept in user defaults so they hold across a relaunch (docs/specs/macos-app-redesign.md,
/// stories 30 and 33).
public struct MenuBarStore {
    public static let styleKey = "menu.iconStyle"
    public static let animatesKey = "menu.animate"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var style: IconStyle {
        get { defaults.string(forKey: Self.styleKey).flatMap(IconStyle.init(rawValue:)) ?? .countAndBar }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.styleKey) }
    }

    public var animates: Bool {
        get { defaults.object(forKey: Self.animatesKey) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.animatesKey) }
    }

    public var showsEpics: Bool {
        get { defaults.object(forKey: showEpicsKey) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: showEpicsKey) }
    }
}
