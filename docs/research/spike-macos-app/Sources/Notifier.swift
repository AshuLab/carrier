import SwiftUI
import UserNotifications

/// Notification test. Guards on the bundle id first: UNUserNotificationCenter.current() aborts without one.
final class Notifier: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var status = "not checked"
    @Published var lastResult = ""
    var available: Bool { Bundle.main.bundleIdentifier != nil }
    var build: String { (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "none (not a bundle)" }

    func setup() {
        guard available else { status = "no bundle id: run build-app.sh"; return }
        UNUserNotificationCenter.current().delegate = self
        refresh()
    }
    func refresh() {
        guard available else { return }
        UNUserNotificationCenter.current().getNotificationSettings { s in
            let name: String
            switch s.authorizationStatus {
            case .notDetermined: name = "notDetermined (never asked)"
            case .denied: name = "denied"
            case .authorized: name = "authorized"
            case .provisional: name = "provisional"
            @unknown default: name = "unknown"
            }
            DispatchQueue.main.async { self.status = name }
        }
    }
    func request() {
        guard available else { return }
        lastResult = "asking…"
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, err in
            DispatchQueue.main.async {
                self.lastResult = "granted=\(granted) error=\(err.map { "\($0)" } ?? "none")"
                self.refresh()
            }
        }
    }
    func send(_ title: String, _ body: String) {
        guard available else { return }
        let c = UNMutableNotificationContent(); c.title = title; c.body = body; c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil)) { err in
            DispatchQueue.main.async { self.lastResult = "add error=\(err.map { "\($0)" } ?? "none")" }
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent n: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound])   // show the banner even while the app is frontmost
    }
}
