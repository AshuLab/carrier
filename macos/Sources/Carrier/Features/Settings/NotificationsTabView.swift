import AppKit
import CarrierCore
import CarrierUI
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
        let page = notificationsPage()
        SettingsPageBody(reset: { AppPreferences().reset(.notifications) }) {
            SettingsGroup(id: "carrier", title: page.groupCarrier) {
                SettingsTabRow(id: "needs-attention", title: page.needsAttention.title, detail: page.needsAttention.detail, first: true) {
                    Toggle(page.needsAttention.title, isOn: $needsYou).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "ready-for-test", title: page.ready.title, detail: page.ready.detail) {
                    Toggle(page.ready.title, isOn: $readyForTest).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "a-problem", title: page.problem.title, detail: page.problem.detail) {
                    Toggle(page.problem.title, isOn: $problem).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsGroup(id: "chat", title: page.groupChat) {
                SettingsTabRow(id: "needs-attention", title: page.chatNeedsAttention.title, detail: page.chatNeedsAttention.detail, first: true) {
                    Toggle(page.chatNeedsAttentionLabel, isOn: $chatNeedsAttention).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "done", title: page.chatDone.title, detail: page.chatDone.detail) {
                    Toggle(page.chatDoneLabel, isOn: $chatDone).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsGroup(id: "delivery", title: page.groupDelivery) {
                SettingsTabRow(id: "only-when-carrier-is-not-in-front", title: page.onlyAway.title, detail: page.onlyAway.detail, first: true) {
                    Toggle(page.onlyAway.title, isOn: $onlyWhenAway).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "dock-badge", title: page.dock.title, detail: page.dock.detail) {
                    Toggle(page.dock.title, isOn: $dockBadge).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "play-a-sound", title: page.sound.title, detail: page.sound.detail) {
                    Toggle(page.sound.title, isOn: $sound).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "remind-me-again", title: page.remind.title, detail: page.remind.detail) {
                    // a saved value that is not a choice reads as Never, as the watcher does
                    ChoicePopUp(
                        label: page.remind.title, options: ReminderInterval.allCases.map { (value: $0, title: $0.title()) },
                        selection: Binding(get: { ReminderInterval(rawValue: reminder) ?? .never }, set: { reminder = $0.rawValue })
                    )
                }
                SettingsTabRow(id: "quiet-hours", title: page.quiet.title, detail: page.quiet.detail) {
                    Toggle(page.quiet.title, isOn: $quiet).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "from", title: page.from.title, detail: page.from.detail) {
                    timePicker(page.from.title, $quietStart)
                }
                .disabled(quiet == false)
                SettingsTabRow(id: "until", title: page.until.title, detail: page.until.detail) {
                    timePicker(page.until.title, $quietEnd)
                }
                .disabled(quiet == false)
            }
            SettingsGroup(id: "permission", title: page.groupPermission) {
                SettingsTabRow(id: "system-permission", title: page.permission, detail: permission?.text() ?? page.checking, first: true) {
                    HStack {
                        if permission != .noBundle {
                            Button { NSWorkspace.shared.open(Self.systemSettingsURL) } label: { Label(page.openSystemSettings, icon: .settings) }
                        }
                        if permission == .notAsked {
                            Button { send() } label: { Label(page.allow, icon: .check) }.buttonStyle(PrimaryCapsuleButtonStyle())
                        }
                        Button { send() } label: { Label(page.sendTest, icon: .send) }.disabled(permission == .noBundle)
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
        testAdvice = permission?.testAdvice()
        guard testAdvice == nil else { return }
        centre.sendTest()
    }

    private func refresh() {
        readPermission(bundleIdentifier: Bundle.main.bundleIdentifier, reader: reader) {
            permission = $0
            if $0.testAdvice() == nil { testAdvice = nil }
        }
    }
}
