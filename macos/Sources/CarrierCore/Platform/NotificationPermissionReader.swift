import Foundation

/// The system's notification centre, as far as the Notifications page needs it.
public protocol NotificationPermissionReader {
    func read(_ done: @escaping (SystemNotificationAnswer) -> Void)
}
