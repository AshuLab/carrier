import Foundation

// Keep awake (docs/macos/keep-awake.md): the rules that say whether the Mac is kept from sleeping and the words that say why. Pure
// values, so each rule is tested; the timer and the menu are in `Carrier/Platform/KeepAwakeController.swift`, the power assertion and the battery behind `KeepAwakeAssertion`.

/// The lengths a manual keep awake can have, in minutes; 0 is until the person turns it off.
public enum AwakeLength {
    public static let choices = [30, 60, 120, 300, 0]
    public static let defaultMinutes = 60

    /// "30 min", "1 hour", "5 hours", "Until I turn it off". A saved length that is not one of the choices reads as the default.
    public static func title(_ minutes: Int, bundle: Bundle? = nil, locale: Locale = .current) -> String {
        switch minutes {
        case 0: Copy.awakeLengthForever(bundle: bundle, locale: locale)
        case 60: Copy.awakeLengthHours(hours: 1, bundle: bundle, locale: locale)
        case let hours where hours >= 120 && hours % 60 == 0: Copy.awakeLengthHours(hours: hours / 60, bundle: bundle, locale: locale)
        default: Copy.awakeMinutes(minutes: minutes, bundle: bundle, locale: locale)
        }
    }

    public static func valid(_ minutes: Int) -> Int { choices.contains(minutes) ? minutes : defaultMinutes }
}

/// What the battery may do to a keep awake. Plugged in, nothing: a desktop Mac has no battery and is always plugged in.
public enum BatteryRule: String, CaseIterable, Sendable {
    case never, below30, below20, below10, pluggedIn

    public static let standard = BatteryRule.below20

    public func title(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        switch self {
        case .never: Copy.awakeBatteryNever(bundle: bundle, locale: locale)
        case .below30: Copy.awakeBatteryBelow(percent: 30, bundle: bundle, locale: locale)
        case .below20: Copy.awakeBatteryBelow(percent: 20, bundle: bundle, locale: locale)
        case .below10: Copy.awakeBatteryBelow(percent: 10, bundle: bundle, locale: locale)
        case .pluggedIn: Copy.awakeBatteryPluggedIn(bundle: bundle, locale: locale)
        }
    }

    var threshold: Int? {
        switch self {
        case .below30: 30
        case .below20: 20
        case .below10: 10
        case .never, .pluggedIn: nil
        }
    }
}

/// How the Mac is powered now.
public struct PowerFacts: Equatable, Sendable {
    public var onBattery: Bool
    /// nil when the Mac has no battery or it did not say.
    public var percent: Int?

    public init(onBattery: Bool, percent: Int?) {
        self.onBattery = onBattery
        self.percent = percent
    }
}

/// What the person asked for by hand: a length, or no end.
public enum AwakeManual: Equatable, Sendable {
    case until(Date)
    case indefinite
}

/// What the Keep awake page sets.
public struct AwakeSettings: Equatable, Sendable {
    /// Also keep the display on; off keeps the Mac awake and lets the screen sleep.
    public var keepsScreenOn = false
    /// What the menu's first item and the shortcut start, in minutes (0 is until turned off).
    public var defaultMinutes = AwakeLength.defaultMinutes
    /// Keep awake by itself while an epic or a session works.
    public var followsAgents = false
    /// Minutes it stays on after the work stopped, so the person can read the end.
    public var graceMinutes = 5
    public var battery = BatteryRule.standard
    /// Say it with a notification when it stops by itself.
    public var notifies = true

    public static let graceChoices = [0, 5, 15, 30]

    public init() {}
}

/// Why the Mac is being kept awake.
public enum AwakeReason: Equatable, Sendable {
    case manual(until: Date?)
    case agents
    case grace(until: Date)
}

/// Why a keep awake that was asked for is not holding.
public enum AwakeBlock: Equatable, Sendable {
    case batteryLow(Int)
    case unplugged
}

/// The answer: whether to hold, why, and what stops it when it was asked for and does not hold.
public struct AwakeDecision: Equatable, Sendable {
    public var reason: AwakeReason?
    public var blocked: AwakeBlock?

    public init(reason: AwakeReason? = nil, blocked: AwakeBlock? = nil) {
        self.reason = reason
        self.blocked = blocked
    }

    public var holds: Bool { reason != nil && blocked == nil }

    public var isManual: Bool {
        if case .manual = reason { return true }
        return false
    }
}

/// Decides from what the person asked, what the agents do and how the Mac is powered. An end that already passed is no manual keep
/// awake. The agents count only with the switch on; the grace is counted from the last time work was seen.
public func awakeDecision(
    now: Date, manual: AwakeManual?, settings: AwakeSettings, agentsWorking: Bool, lastWorked: Date?, power: PowerFacts
) -> AwakeDecision {
    var reason: AwakeReason?
    switch manual {
    case .indefinite?: reason = .manual(until: nil)
    case .until(let end)? where end > now: reason = .manual(until: end)
    default: break
    }
    if reason == nil, settings.followsAgents {
        if agentsWorking {
            reason = .agents
        } else if let lastWorked, settings.graceMinutes > 0 {
            let end = lastWorked.addingTimeInterval(Double(settings.graceMinutes) * 60)
            if end > now { reason = .grace(until: end) }
        }
    }
    return AwakeDecision(reason: reason, blocked: reason == nil ? nil : block(settings.battery, power))
}

private func block(_ rule: BatteryRule, _ power: PowerFacts) -> AwakeBlock? {
    guard power.onBattery else { return nil }
    if rule == .pluggedIn { return .unplugged }
    if let limit = rule.threshold, let percent = power.percent, percent < limit { return .batteryLow(percent) }
    return nil
}

/// The next moment the decision changes by itself (a manual end, the end of the grace), for the timer; nil when only an event can change it.
public func nextAwakeChange(_ decision: AwakeDecision) -> Date? {
    switch decision.reason {
    case .manual(let end)?: end
    case .grace(let end)?: end
    case .agents?, nil: nil
    }
}

/// "1 h 12 min", "42 min", "under 1 min": rounded up, so it never says 0 while there is time left.
public func awakeRemaining(_ seconds: TimeInterval, bundle: Bundle? = nil, locale: Locale = .current) -> String {
    let minutes = Int((max(seconds, 0) / 60).rounded(.up))
    if minutes < 1 { return Copy.awakeRemainingUnderMinute(bundle: bundle, locale: locale) }
    if minutes < 60 { return Copy.awakeMinutes(minutes: minutes, bundle: bundle, locale: locale) }
    return minutes % 60 == 0
        ? Copy.awakeRemainingHours(hours: minutes / 60, bundle: bundle, locale: locale)
        : Copy.awakeRemainingHoursMinutes(hours: minutes / 60, minutes: minutes % 60, bundle: bundle, locale: locale)
}

/// The line of the menu and the page: one sentence that says the state and what ends it.
public func awakeStatus(_ decision: AwakeDecision, settings: AwakeSettings, now: Date, bundle: Bundle? = nil, locale: Locale = .current) -> String {
    if let blocked = decision.blocked {
        switch blocked {
        case .batteryLow(let percent): return Copy.awakeStatusBatteryLow(percent: percent, bundle: bundle, locale: locale)
        case .unplugged: return Copy.awakeStatusOnBattery(bundle: bundle, locale: locale)
        }
    }
    switch decision.reason {
    case .manual(let end?)?: return Copy.awakeStatusManual(remaining: awakeRemaining(end.timeIntervalSince(now), bundle: bundle, locale: locale), bundle: bundle, locale: locale)
    case .manual(nil)?: return Copy.awakeStatusManualForever(bundle: bundle, locale: locale)
    case .agents?: return Copy.awakeStatusAgents(bundle: bundle, locale: locale)
    case .grace(let end)?: return Copy.awakeStatusGrace(remaining: awakeRemaining(end.timeIntervalSince(now), bundle: bundle, locale: locale), bundle: bundle, locale: locale)
    case nil: return settings.followsAgents ? Copy.awakeStatusOffAgents(bundle: bundle, locale: locale) : Copy.awakeStatusOff(bundle: bundle, locale: locale)
    }
}

/// What the menu's first item says it will do when clicked: stop what was asked for by hand, or start the default length.
public func awakeToggleTitle(manualActive: Bool, defaultMinutes: Int, bundle: Bundle? = nil, locale: Locale = .current) -> String {
    if manualActive { return Copy.awakeStop(bundle: bundle, locale: locale) }
    let length = AwakeLength.valid(defaultMinutes)
    return length == 0 ? Copy.awakeKeep(bundle: bundle, locale: locale) : Copy.awakeKeepFor(length: AwakeLength.title(length, bundle: bundle, locale: locale), bundle: bundle, locale: locale)
}

/// What the notification says when a keep awake ends by itself: the timer ran out, or the battery ended it.
public func awakeEndedNotice(_ block: AwakeBlock?, bundle: Bundle? = nil, locale: Locale = .current) -> (title: String, body: String) {
    switch block {
    case .batteryLow(let percent)?: (Copy.awakePausedTitle(bundle: bundle, locale: locale), Copy.awakeEndedBatteryLow(percent: percent, bundle: bundle, locale: locale))
    case .unplugged?: (Copy.awakePausedTitle(bundle: bundle, locale: locale), Copy.awakeEndedOnBattery(bundle: bundle, locale: locale))
    case nil: (Copy.awakeEndedTitle(bundle: bundle, locale: locale), Copy.awakeEndedBody(bundle: bundle, locale: locale))
    }
}

/// What the notification says when a keep awake was asked for and cannot start because of the battery: the person just did it and the menu closed on nothing.
public func awakeWaitingNotice(_ block: AwakeBlock, bundle: Bundle? = nil, locale: Locale = .current) -> (title: String, body: String) {
    switch block {
    case .batteryLow(let percent): (Copy.awakeWaitingTitle(bundle: bundle, locale: locale), Copy.awakeWaitingBatteryLow(percent: percent, bundle: bundle, locale: locale))
    case .unplugged: (Copy.awakeWaitingTitle(bundle: bundle, locale: locale), Copy.awakeWaitingOnBattery(bundle: bundle, locale: locale))
    }
}

/// The character a menu item shows for the shortcut, so the menu teaches the keys: a letter, digit or sign in lower case, or a space. The keys
/// with a name (arrows, F-keys) have no character to show, so the item shows none.
public func awakeMenuKey(_ shortcut: DictationShortcut?) -> String? {
    guard let shortcut else { return nil }
    if shortcut.key == "Space" { return " " }
    // the arrows are named by one character too, and a menu item needs another code for them
    guard shortcut.key.count == 1, "←→↑↓".contains(shortcut.key) == false else { return nil }
    return shortcut.key.lowercased()
}

/// What the icon says to the pointer and to VoiceOver: the icon is a picture of a count and a bar, so the cup needs its words.
public func awakeIconWords(awake: Bool, bundle: Bundle? = nil, locale: Locale = .current) -> (label: String, tip: String?) {
    awake ? (Copy.awakeIconAwake(bundle: bundle, locale: locale), Copy.awakeIconTip(bundle: bundle, locale: locale)) : (Copy.appName(bundle: bundle, locale: locale), nil)
}
