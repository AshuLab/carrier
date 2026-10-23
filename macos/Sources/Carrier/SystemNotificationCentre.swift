import AppKit
import CarrierCore
import UserNotifications

extension NotificationWatcher {
    /// The app's watcher, fed from the main queue.
    static let app = NotificationWatcher(centre: SystemNotificationCentre.shared, kinds: { UserDefaults.standard.notificationKinds })
}

/// The system's notification centre. `UNUserNotificationCenter.current()` aborts a process that is not inside a bundle with an
/// identifier, and a Swift `catch` cannot stop that, so nothing here touches it without one. Permission is asked when the
/// first notification is due, not at launch; a denial is remembered, so it is not asked about again. Main thread only.
final class SystemNotificationCentre: NSObject, NotificationCentre, NotificationPermissionReader, UNUserNotificationCenterDelegate {
    static let shared = SystemNotificationCentre()

    private var waiting: [EpicNotification] = []
    private var checking = false
    private var denied = false

    func post(_ notifications: [EpicNotification]) {
        guard Bundle.main.bundleIdentifier != nil else {
            log("no bundle identifier, \(notifications.count) notification(s) not shown: run Carrier.app")
            return
        }
        guard denied == false else { return }
        waiting += notifications
        guard checking == false else { return }
        checking = true
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.getNotificationSettings { settings in
            DispatchQueue.main.async { self.settled(settings.authorizationStatus, center) }
        }
    }

    /// Settings' "Send a test": asks again even after a denial, since the person may have just allowed it in System Settings.
    func sendTest() {
        denied = false
        post([EpicNotification(title: "Carrier test", body: "Notifications work", isTest: true)])
    }

    /// Takes the clicks on notifications, also those of ones shown before the app was last started. Needs a bundle.
    func attachDelegate() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().delegate = self
    }

    /// The system's answer; call only inside a bundle (`readPermission` checks).
    func read(_ done: @escaping (SystemNotificationAnswer) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let style: NotificationDelivery.Style = switch settings.alertStyle {
            case .banner: .banners
            case .alert: .alerts
            default: .none
            }
            let answer: SystemNotificationAnswer = switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: .allowed(NotificationDelivery(style: style, soundOn: settings.soundSetting == .enabled))
            case .notDetermined: .notAsked
            default: .denied
            }
            DispatchQueue.main.async { done(answer) }
        }
    }

    private func settled(_ status: UNAuthorizationStatus, _ center: UNUserNotificationCenter) {
        switch status {
        case .authorized, .provisional:
            show(center)
        case .notDetermined:
            center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                DispatchQueue.main.async {
                    if let error { self.log("notification permission failed: \(error)") }
                    if granted { self.show(center) } else { self.deny() }
                }
            }
        default:
            deny()
        }
    }

    private func show(_ center: UNUserNotificationCenter) {
        for notification in waiting {
            let content = UNMutableNotificationContent()
            content.title = notification.title
            content.body = notification.body
            content.sound = .default
            var info: [String: Any] = ["test": notification.isTest]
            if let epic = notification.epic { info["repo"] = epic.repo; info["issue"] = epic.issue }
            content.userInfo = info
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) { error in
                if let error { self.log("notification not shown: \(error)") }
            }
        }
        waiting = []
        checking = false
    }

    private func deny() {
        log("notifications are not allowed: not asking again until the app restarts")
        denied = true
        waiting = []
        checking = false
    }

    /// Show the banner even while the app is frontmost, unless the person asked for none then (the test always shows).
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        let isTest = notification.request.content.userInfo["test"] as? Bool ?? false
        let show = shouldPresent(onlyWhenAway: UserDefaults.standard.notifiesOnlyWhenAway, appIsActive: NSApp.isActive, isTest: isTest)
        done(show ? [.banner, .sound] : [])
    }

    /// A click opens the window, on the epic when the notification is about one.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let epic = (info["repo"] as? String).flatMap { repo in (info["issue"] as? Int).map { EpicRef(repo: repo, issue: $0) } }
        DispatchQueue.main.async {
            WindowController.shared.open(epic: epic)
            done()
        }
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data("carrier: \(message)\n".utf8))
    }

    /// What the self-test logs: whether the centre may be touched. It asks the system nothing, so no prompt can appear.
    static var selfTestSummary: String {
        Bundle.main.bundleIdentifier.map { "bundle \($0), centre touched on the first notification" } ?? "no bundle identifier, centre never touched"
    }
}
