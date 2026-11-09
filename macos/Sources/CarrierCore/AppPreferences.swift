import Foundation

/// The App group's preferences, kept in user defaults so they hold across a relaunch: each with its default, and a bad saved value
/// reads as the default. The keys are the ones that already existed, so nothing a person set is lost.
public struct AppPreferences {
    public static let styleKey = "menu.iconStyle"
    public static let animatesKey = "menu.animate"
    public static let confirmStopKey = "stop.confirm"

    public static let defaultStyle = IconStyle.countAndBar
    public static let defaultAnimates = true
    public static let defaultShowsEpics = true
    public static let defaultConfirmStop = true

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var style: IconStyle {
        get { defaults.string(forKey: Self.styleKey).flatMap(IconStyle.init(rawValue:)) ?? Self.defaultStyle }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.styleKey) }
    }

    public var animates: Bool {
        get { defaults.object(forKey: Self.animatesKey) as? Bool ?? Self.defaultAnimates }
        nonmutating set { defaults.set(newValue, forKey: Self.animatesKey) }
    }

    public var showsEpics: Bool {
        get { defaults.object(forKey: showEpicsKey) as? Bool ?? Self.defaultShowsEpics }
        nonmutating set { defaults.set(newValue, forKey: showEpicsKey) }
    }

    /// Whether stopping Carrier asks first when it would interrupt epics.
    public var confirmStop: Bool {
        get { defaults.object(forKey: Self.confirmStopKey) as? Bool ?? Self.defaultConfirmStop }
        nonmutating set { defaults.set(newValue, forKey: Self.confirmStopKey) }
    }

    /// Takes the keys of one page out, so it reads as its defaults again; the other pages are not touched.
    public func reset(_ page: SettingsPage) {
        for key in Self.keys(of: page) { defaults.removeObject(forKey: key) }
    }

    // the pages that gain preferences add their keys here
    private static func keys(of page: SettingsPage) -> [String] {
        switch page {
        case .general: [styleKey, animatesKey, showEpicsKey, confirmStopKey]
        case .sidebar:
            [
                SidebarStore.groupByKey, SidebarStore.sessionSortKey, SidebarStore.archiveSortKey, SidebarStore.showsIconKey,
                SidebarStore.showsBranchKey, SidebarStore.showsProvidersKey, SidebarStore.showsAgeKey,
            ]
        default: []
        }
    }
}

/// Stop asks first only when it interrupts epics and the person did not switch the question off.
public func asksBeforeStopping(_ snapshot: PanelSnapshot, switchOn: Bool) -> Bool {
    switchOn && snapshot.stopNeedsConfirmation
}
