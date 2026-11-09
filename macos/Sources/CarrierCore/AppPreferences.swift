import Foundation

/// The App group's preferences, kept in user defaults so they hold across a relaunch: each with its default, and a bad saved value
/// reads as the default. The keys are the ones that already existed, so nothing a person set is lost.
public struct AppPreferences {
    public static let styleKey = "menu.iconStyle"
    public static let animatesKey = "menu.animate"
    public static let confirmStopKey = "stop.confirm"
    public static let timeStyleKey = "display.timeStyle"
    public static let clockHoursKey = "display.clock"
    public static let colorSchemeKey = "appearance.colorScheme"
    public static let densityKey = "appearance.density"
    public static let themeKey = "appearance.theme"
    public static let accentKey = "appearance.accent"
    public static let tintKey = "appearance.tint"
    public static let translucentKey = "appearance.translucent"
    public static let sendKeyKey = "chat.sendKey"
    public static let writingToolsKey = "chat.writingTools"
    public static let checksSpellingKey = "chat.checkSpelling"
    public static let correctsSpellingKey = "chat.correctSpelling"

    public static let defaultStyle = IconStyle.countAndBar
    public static let defaultAnimates = true
    public static let defaultShowsEpics = true
    public static let defaultConfirmStop = true
    public static let defaultColorScheme = ColorSchemeChoice.system
    public static let defaultDensity = Density.comfortable
    public static let defaultTheme = Theme.carrier
    public static let defaultTint = Tint.off
    public static let defaultSendKey = SendKey.return
    public static let defaultWritingTools = false
    public static let defaultChecksSpelling = true
    public static let defaultCorrectsSpelling = false

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

    /// How ages and times read everywhere in the app: relative or as a clock time.
    public var timeStyle: TimeStyle {
        get { defaults.string(forKey: Self.timeStyleKey).flatMap(TimeStyle.init(rawValue:)) ?? .relative }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.timeStyleKey) }
    }

    /// The clock of clock times: the Mac's, 12 or 24 hours.
    public var clockHours: ClockHours {
        get { defaults.string(forKey: Self.clockHoursKey).flatMap(ClockHours.init(rawValue:)) ?? .system }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.clockHoursKey) }
    }

    /// The appearance of every window of the app: the Mac's, or light or dark whatever the Mac is.
    public var colorScheme: ColorSchemeChoice {
        get { defaults.string(forKey: Self.colorSchemeKey).flatMap(ColorSchemeChoice.init(rawValue:)) ?? Self.defaultColorScheme }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.colorSchemeKey) }
    }

    /// The text size of the whole interface in percent, the one the type scale reads.
    public var textSize: Int {
        get { TypeScale.stored(in: defaults).percent }
        nonmutating set { defaults.set(TypeScale(percent: newValue).percent, forKey: TypeScale.percentKey) }
    }

    public var density: Density {
        get { defaults.string(forKey: Self.densityKey).flatMap(Density.init(rawValue:)) ?? Self.defaultDensity }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.densityKey) }
    }

    public var theme: Theme {
        get { defaults.string(forKey: Self.themeKey).flatMap(Theme.init(rawValue:)) ?? Self.defaultTheme }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.themeKey) }
    }

    /// The accent the person picked; nil is the theme's own.
    public var accent: AccentColor? {
        get { defaults.string(forKey: Self.accentKey).flatMap(AccentColor.init(rawValue:)) }
        nonmutating set { defaults.set(newValue?.rawValue, forKey: Self.accentKey) }
    }

    public var tint: Tint {
        get { defaults.string(forKey: Self.tintKey).flatMap(Tint.init(rawValue:)) ?? Self.defaultTint }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.tintKey) }
    }

    /// Whether windows are translucent: what the person chose, and while they did not, the opposite of the system's Reduce transparency.
    public func translucent(systemReducesTransparency: Bool) -> Bool {
        defaults.object(forKey: Self.translucentKey) as? Bool ?? (systemReducesTransparency == false)
    }

    public func setTranslucent(_ value: Bool) { defaults.set(value, forKey: Self.translucentKey) }

    /// The key that sends in the message box; the other one makes a new line.
    public var sendKey: SendKey {
        get { defaults.string(forKey: Self.sendKeyKey).flatMap(SendKey.init(rawValue:)) ?? Self.defaultSendKey }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.sendKeyKey) }
    }

    /// Whether the system's Writing Tools offer to rewrite the text of the message box.
    public var writingTools: Bool {
        get { defaults.object(forKey: Self.writingToolsKey) as? Bool ?? Self.defaultWritingTools }
        nonmutating set { defaults.set(newValue, forKey: Self.writingToolsKey) }
    }

    public var checksSpelling: Bool {
        get { defaults.object(forKey: Self.checksSpellingKey) as? Bool ?? Self.defaultChecksSpelling }
        nonmutating set { defaults.set(newValue, forKey: Self.checksSpellingKey) }
    }

    public var correctsSpelling: Bool {
        get { defaults.object(forKey: Self.correctsSpellingKey) as? Bool ?? Self.defaultCorrectsSpelling }
        nonmutating set { defaults.set(newValue, forKey: Self.correctsSpellingKey) }
    }

    /// Takes the keys of one page out, so it reads as its defaults again; the other pages are not touched.
    public func reset(_ page: SettingsPage) {
        for key in Self.keys(of: page) { defaults.removeObject(forKey: key) }
    }

    // the pages that gain preferences add their keys here
    private static func keys(of page: SettingsPage) -> [String] {
        switch page {
        case .general: [styleKey, animatesKey, showEpicsKey, confirmStopKey, timeStyleKey, clockHoursKey]
        case .sidebar:
            [
                SidebarStore.groupByKey, SidebarStore.sessionSortKey, SidebarStore.archiveSortKey, SidebarStore.showsIconKey,
                SidebarStore.showsBranchKey, SidebarStore.showsProvidersKey, SidebarStore.showsAgeKey,
            ]
        case .appearance: [colorSchemeKey, TypeScale.percentKey, densityKey, themeKey, accentKey, tintKey, translucentKey]
        case .chat: [sendKeyKey, writingToolsKey, checksSpellingKey, correctsSpellingKey]
        default: []
        }
    }
}

public enum ColorSchemeChoice: String, CaseIterable {
    case system, light, dark

    public var title: String { rawValue.capitalized }
}

/// How tight the app packs its rows: the vertical padding of a sidebar row and the space between the messages of a conversation.
public enum Density: String, CaseIterable {
    case compact, comfortable

    public var title: String { rawValue.capitalized }
    public var rowPadding: CGFloat { self == .compact ? 4 : 7 }
    public var messageGap: CGFloat { self == .compact ? 8 : 12 }
}

/// The key that sends a message: Return, or ⌘Return. Shift+Return makes a new line whichever is chosen.
public enum SendKey: String, CaseIterable {
    case `return`, commandReturn

    /// Whether Return pressed with these modifiers sends; if not, it makes a new line.
    public func sends(command: Bool, shift: Bool) -> Bool {
        guard shift == false else { return false }
        return self == .commandReturn ? command : command == false
    }
}

/// Stop asks first only when it interrupts epics and the person did not switch the question off.
public func asksBeforeStopping(_ snapshot: PanelSnapshot, switchOn: Bool) -> Bool {
    switchOn && snapshot.stopNeedsConfirmation
}
