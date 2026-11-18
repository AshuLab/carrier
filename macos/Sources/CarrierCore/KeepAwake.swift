import Foundation

// Keep awake (docs/macos/keep-awake.md): the rules that say whether the Mac is kept from sleeping and the words that say why. Pure
// values, so each rule is tested; the power assertion, the timer, the battery and the menu are in `Carrier/KeepAwakeController.swift`.

/// The lengths a manual keep awake can have, in minutes; 0 is until the person turns it off.
public enum AwakeLength {
    public static let choices = [30, 60, 120, 300, 0]
    public static let defaultMinutes = 60

    /// "30 min", "1 hour", "5 hours", "Until I turn it off". A saved length that is not one of the choices reads as the default.
    public static func title(_ minutes: Int) -> String {
        switch minutes {
        case 0: "Until I turn it off"
        case 60: "1 hour"
        case let hours where hours >= 120 && hours % 60 == 0: "\(hours / 60) hours"
        default: "\(minutes) min"
        }
    }

    public static func valid(_ minutes: Int) -> Int { choices.contains(minutes) ? minutes : defaultMinutes }
}

/// What the battery may do to a keep awake. Plugged in, nothing: a desktop Mac has no battery and is always plugged in.
public enum BatteryRule: String, CaseIterable, Sendable {
    case never, below30, below20, below10, pluggedIn

    public static let standard = BatteryRule.below20

    public var title: String {
        switch self {
        case .never: "Keep awake on battery too"
        case .below30: "Stop below 30 %"
        case .below20: "Stop below 20 %"
        case .below10: "Stop below 10 %"
        case .pluggedIn: "Only while plugged in"
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
public func awakeRemaining(_ seconds: TimeInterval) -> String {
    let minutes = Int((max(seconds, 0) / 60).rounded(.up))
    if minutes < 1 { return "under 1 min" }
    if minutes < 60 { return "\(minutes) min" }
    return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
}

/// The line of the menu and the page: one sentence that says the state and what ends it.
public func awakeStatus(_ decision: AwakeDecision, settings: AwakeSettings, now: Date) -> String {
    if let blocked = decision.blocked {
        switch blocked {
        case .batteryLow(let percent): return "Paused: battery at \(percent) %"
        case .unplugged: return "Paused: on battery"
        }
    }
    switch decision.reason {
    case .manual(let end?)?: return "Awake · \(awakeRemaining(end.timeIntervalSince(now))) left"
    case .manual(nil)?: return "Awake until you turn it off"
    case .agents?: return "Awake while agents work"
    case .grace(let end)?: return "Awake · \(awakeRemaining(end.timeIntervalSince(now))) after agents finished"
    case nil: return settings.followsAgents ? "Off · wakes up when agents work" : "Off"
    }
}

/// What the menu's first item says it will do when clicked: stop what was asked for by hand, or start the default length.
public func awakeToggleTitle(manualActive: Bool, defaultMinutes: Int) -> String {
    if manualActive { return "Stop keeping awake" }
    let length = AwakeLength.valid(defaultMinutes)
    return length == 0 ? "Keep awake" : "Keep awake for \(AwakeLength.title(length))"
}

/// What the notification says when a keep awake ends by itself: the timer ran out, or the battery ended it.
public func awakeEndedNotice(_ block: AwakeBlock?) -> (title: String, body: String) {
    switch block {
    case .batteryLow(let percent)?: ("Keep awake paused", "The battery is at \(percent) %. Your Mac can sleep now; plug it in and it goes on.")
    case .unplugged?: ("Keep awake paused", "Your Mac is on battery. It can sleep now; plug it in and it goes on.")
    case nil: ("Keep awake ended", "Your Mac can sleep again.")
    }
}
