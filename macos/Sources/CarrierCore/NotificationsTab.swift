import Foundation

// The Notifications tab of Settings as plain values: the system permission as macOS says it (allowed with the style and the
// sound it set, denied, not asked, or no bundle), the three kinds of notification and the one thing about how they show that is
// the app's (not while its window is in front). Sound and banner style are macOS's, per app, in System Settings. The system's
// notification centre is read through a protocol.

public let notifyNeedsYouKey = "notify.needsYou"
public let notifyReadyForTestKey = "notify.readyForTest"
public let notifyProblemKey = "notify.problem"
public let notifyOnlyWhenAwayKey = "notify.onlyWhenAway"
public let notifySoundKey = "notify.sound"
public let notifyQuietKey = "notify.quiet"
public let notifyQuietStartKey = "notify.quietStart"
public let notifyQuietEndKey = "notify.quietEnd"

extension UserDefaults {
    /// The switches: needs attention and ready for test are on until the person turns them off, a problem is off until turned on. The
    /// defaults are not registered here: an unset key reads as its default.
    public var notificationKinds: NotificationKinds {
        NotificationKinds(
            needsYou: object(forKey: notifyNeedsYouKey) as? Bool ?? true,
            readyForTest: object(forKey: notifyReadyForTestKey) as? Bool ?? true,
            problem: object(forKey: notifyProblemKey) as? Bool ?? false
        )
    }

    /// No banner while the app's window is in front; on until turned off.
    public var notifiesOnlyWhenAway: Bool { object(forKey: notifyOnlyWhenAwayKey) as? Bool ?? true }

    /// A banner plays a sound; on until turned off.
    public var notifiesWithSound: Bool { object(forKey: notifySoundKey) as? Bool ?? true }

    /// Quiet hours: off until turned on, from 22:00 to 08:00 until the person picks others.
    public var quietHours: QuietHours {
        QuietHours(
            enabled: object(forKey: notifyQuietKey) as? Bool ?? false,
            start: object(forKey: notifyQuietStartKey) as? Int ?? QuietHours.defaultStart,
            end: object(forKey: notifyQuietEndKey) as? Int ?? QuietHours.defaultEnd
        )
    }
}

/// The hours in which a notification is kept and not shown: `start` and `end` are minutes after midnight. The window may cross
/// midnight (22:00 to 08:00); with equal start and end it is never quiet.
public struct QuietHours: Equatable {
    public static let defaultStart = 22 * 60
    public static let defaultEnd = 8 * 60

    public var enabled: Bool
    public var start: Int
    public var end: Int

    public init(enabled: Bool = false, start: Int = defaultStart, end: Int = defaultEnd) {
        self.enabled = enabled
        self.start = start
        self.end = end
    }

    /// Whether `date` is inside the hours, read on the clock of `calendar`. The start is in and the end is out.
    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard enabled, start != end else { return false }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return start < end ? (start <= minute && minute < end) : (minute >= start || minute < end)
    }
}

/// Whether a banner shows: always the test, and anything else unless the person asked for none while the app is in front and it is.
public func shouldPresent(onlyWhenAway: Bool, appIsActive: Bool, isTest: Bool) -> Bool {
    isTest || (onlyWhenAway && appIsActive) == false
}

/// How macOS shows this app's notifications, and whether it plays the sound.
public struct NotificationDelivery: Equatable {
    public enum Style: Equatable { case banners, alerts, none }

    public var style: Style
    public var soundOn: Bool

    public init(style: Style, soundOn: Bool) {
        self.style = style
        self.soundOn = soundOn
    }
}

/// What the system says about this app's notifications.
public enum SystemNotificationAnswer: Equatable {
    case allowed(NotificationDelivery), denied, notAsked
}

/// What the tab shows. `noBundle` is the app run outside `Carrier.app` (`swift run`), where the centre must not be touched.
public enum NotificationPermission: Equatable {
    case allowed(NotificationDelivery), denied, notAsked, noBundle

    public var text: String {
        switch self {
        case .allowed(let delivery):
            switch delivery.style {
            case .none: "Allowed · notifications set to None"
            case .banners: "Allowed · banners · sound \(delivery.soundOn ? "on" : "off")"
            case .alerts: "Allowed · alerts · sound \(delivery.soundOn ? "on" : "off")"
            }
        case .denied: "Denied in System Settings"
        case .notAsked: "Not asked yet · the first notification asks"
        case .noBundle: "Only available from Carrier.app"
        }
    }

    /// Why "Send a test" would show nothing; nil when it will, or when pressing it is what asks.
    public var testAdvice: String? {
        switch self {
        case .denied: "Notifications are off for Carrier in System Settings."
        case .allowed(let delivery) where delivery.style == .none: "Notifications are set to None for Carrier in System Settings."
        default: nil
        }
    }
}

/// The system's notification centre, as far as the tab needs it.
public protocol NotificationPermissionReader {
    func read(_ done: @escaping (SystemNotificationAnswer) -> Void)
}

/// The permission to show: without a bundle identifier the reader is never asked.
public func readPermission(bundleIdentifier: String?, reader: NotificationPermissionReader, done: @escaping (NotificationPermission) -> Void) {
    guard bundleIdentifier != nil else { return done(.noBundle) }
    reader.read { answer in
        switch answer {
        case .allowed(let delivery): done(.allowed(delivery))
        case .denied: done(.denied)
        case .notAsked: done(.notAsked)
        }
    }
}
