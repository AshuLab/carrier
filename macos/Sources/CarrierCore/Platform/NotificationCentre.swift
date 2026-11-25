import Foundation

/// Where notifications go; the app's is the system's notification centre (`Carrier/Platform/SystemNotificationCentre.swift`).
public protocol NotificationCentre {
    func post(_ notifications: [EpicNotification])
    /// Settings' "Send a test": shown even after a denial, since the person may have just allowed it.
    func sendTest()
}
