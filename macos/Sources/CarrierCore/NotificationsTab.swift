import Foundation

// The Notifications tab of Settings as plain values: the system permission in the four states it shows, and the two switches
// (docs/specs/macos-app-redesign.md, story 30). The system's notification centre is read through a protocol.

public let notifyNeedsYouKey = "notify.needsYou"
public let notifyReadyForTestKey = "notify.readyForTest"

extension UserDefaults {
    /// The switches, both on until the person turns one off. The defaults are not registered here: an unset key reads as on.
    public var notificationKinds: NotificationKinds {
        NotificationKinds(
            needsYou: object(forKey: notifyNeedsYouKey) as? Bool ?? true,
            readyForTest: object(forKey: notifyReadyForTestKey) as? Bool ?? true
        )
    }
}

/// What the system says about this app's notifications.
public enum SystemNotificationAnswer: Equatable {
    case allowed, denied, notAsked
}

/// What the tab shows. `noBundle` is the app run outside `Carrier.app` (`swift run`), where the centre must not be touched.
public enum NotificationPermission: Equatable {
    case allowed, denied, notAsked, noBundle

    public var text: String {
        switch self {
        case .allowed: "Allowed in System Settings"
        case .denied: "Denied in System Settings"
        case .notAsked: "Not asked yet · the first notification asks"
        case .noBundle: "Only available from Carrier.app"
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
        case .allowed: done(.allowed)
        case .denied: done(.denied)
        case .notAsked: done(.notAsked)
        }
    }
}
