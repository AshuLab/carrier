import AppKit
import CarrierCore
import SwiftUI

struct NotificationsTabView: View {
    let centre: any NotificationCentre
    let reader: any NotificationPermissionReader
    @AppStorage(Preference.notifyNeedsYou) private var needsYou
    @AppStorage(Preference.notifyReadyForTest) private var readyForTest
    @AppStorage(Preference.notifyProblem) private var problem
    @AppStorage(Preference.notifyChatNeedsAttention) private var chatNeedsAttention
    @AppStorage(Preference.notifyChatDone) private var chatDone
    @AppStorage(Preference.notifyOnlyWhenAway) private var onlyWhenAway
    @AppStorage(Preference.notifyDockBadge) private var dockBadge
    @AppStorage(Preference.notifySound) private var sound
    @AppStorage(Preference.notifyReminder) private var reminder
    @AppStorage(Preference.notifyQuiet) private var quiet
    @AppStorage(Preference.notifyQuietStart) private var quietStart
    @AppStorage(Preference.notifyQuietEnd) private var quietEnd
    @State private var permission: NotificationPermission?
    @State private var testAdvice: String?

    var body: some View {
        SettingsPageBody(reset: { AppPreferences().reset(.notifications) }) {
            SettingsGroup(id: "carrier", title: "Carrier") {
                SettingsTabRow(id: "needs-attention", title: "Needs attention", detail: "An epic stopped and waits for a person", first: true) {
                    Toggle("Needs attention", isOn: $needsYou).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "ready-for-test", title: "Ready for test", detail: "An epic finished and has a PR to try") {
                    Toggle("Ready for test", isOn: $readyForTest).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "a-problem", title: "A problem", detail: "GitHub refuses a repo, or Carrier stops by itself") {
                    Toggle("A problem", isOn: $problem).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsGroup(id: "chat", title: "Chat") {
                SettingsTabRow(id: "needs-attention", title: "Needs attention", detail: "A session waits for an approval", first: true) {
                    Toggle("Chat needs attention", isOn: $chatNeedsAttention).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "done", title: "Done", detail: "A session finished its turn") {
                    Toggle("Chat done", isOn: $chatDone).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsGroup(id: "delivery", title: "Delivery") {
                SettingsTabRow(id: "only-when-carrier-is-not-in-front", title: "Only when Carrier is not in front", detail: "No banner while its window is the one you are looking at", first: true) {
                    Toggle("Only when Carrier is not in front", isOn: $onlyWhenAway).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "dock-badge", title: "Dock badge", detail: "The Dock icon counts the epics that need a person and the sessions that wait for an approval") {
                    Toggle("Dock badge", isOn: $dockBadge).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "play-a-sound", title: "Play a sound", detail: "A banner plays the notification sound") {
                    Toggle("Play a sound", isOn: $sound).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "remind-me-again", title: "Remind me again", detail: "While an epic or a session still needs attention. Ready for test and Done never remind") {
                    // a saved value that is not a choice reads as Never, as the watcher does
                    ChoicePopUp(
                        label: "Remind me again", options: ReminderInterval.allCases.map { (value: $0, title: $0.title) },
                        selection: Binding(get: { ReminderInterval(rawValue: reminder) ?? .never }, set: { reminder = $0.rawValue })
                    )
                }
                SettingsTabRow(id: "quiet-hours", title: "Quiet hours", detail: "No banner and no sound: notifications wait in the Notification Center") {
                    Toggle("Quiet hours", isOn: $quiet).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "from", title: "From", detail: "When the quiet starts") {
                    timePicker("From", $quietStart)
                }
                .disabled(quiet == false)
                SettingsTabRow(id: "until", title: "Until", detail: "When it ends, the next day if it is earlier than the start") {
                    timePicker("Until", $quietEnd)
                }
                .disabled(quiet == false)
            }
            SettingsGroup(id: "permission", title: "Permission") {
                SettingsTabRow(id: "system-permission", title: "System permission", detail: permission?.text ?? "Checking…", first: true) {
                    HStack {
                        if permission != .noBundle {
                            Button { NSWorkspace.shared.open(Self.systemSettingsURL) } label: { Label("Open System Settings", icon: .settings) }
                        }
                        if permission == .notAsked {
                            Button { send() } label: { Label("Allow", icon: .check) }.buttonStyle(PrimaryCapsuleButtonStyle())
                        }
                        Button { send() } label: { Label("Send a test", icon: .send) }.disabled(permission == .noBundle)
                    }
                }
            }
            if let testAdvice {
                Label(testAdvice, icon: .warningFilled).scaledFont(12).foregroundStyle(.orange).padding(.horizontal, Tokens.Space.s14)
            }
        }
        .buttonStyle(SecondaryCapsuleButtonStyle())
        .task { refresh() }
        // back from System Settings, where the person may have changed the answer
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    /// A time of day kept as minutes after midnight, chosen from a menu of every half hour (and the saved time itself when it is none of
    /// those), written in the clock the Time format setting says.
    private func timePicker(_ name: String, _ minutes: Binding<Int>) -> some View {
        let hours = TimeFormat.stored().hours
        let options = Array(Set(Array(stride(from: 0, to: 1440, by: 30)) + [minutes.wrappedValue])).sorted()
        func label(_ minutes: Int) -> String {
            let date = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
            return clockTime(date, hours: hours, locale: .current)
        }
        return ChoicePopUp(label: name, options: options.map { (value: $0, title: label($0)) }, selection: minutes)
    }

    private static let systemSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!

    /// A test that macOS would swallow says why instead; otherwise it is sent (the first one also asks for the permission).
    private func send() {
        testAdvice = permission?.testAdvice
        guard testAdvice == nil else { return }
        centre.sendTest()
    }

    private func refresh() {
        readPermission(bundleIdentifier: Bundle.main.bundleIdentifier, reader: reader) {
            permission = $0
            if $0.testAdvice == nil { testAdvice = nil }
        }
    }
}
