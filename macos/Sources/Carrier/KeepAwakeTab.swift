import CarrierCore
import SwiftUI

/// The Keep awake page: the state now with the button that changes it, how a keep awake by hand starts, what follows the agents, and what the battery and the
/// notification do. Each setting is read by `KeepAwakeController` as it is changed; nothing is restarted.
struct KeepAwakeTabView: View {
    var controller = KeepAwakeController.shared
    @AppStorage(AppPreferences.awakeScreenKey) private var screen = false
    @AppStorage(AppPreferences.awakeMinutesKey) private var minutes = AwakeLength.defaultMinutes
    @AppStorage(AppPreferences.awakeAgentsKey) private var agents = false
    @AppStorage(AppPreferences.awakeGraceKey) private var grace = AwakeSettings().graceMinutes
    @AppStorage(AppPreferences.awakeBatteryKey) private var battery = BatteryRule.standard.rawValue
    @AppStorage(AppPreferences.awakeNotifyKey) private var notifies = true
    @AppStorage(AppPreferences.awakeShortcutKey) private var shortcutText = ""

    var body: some View {
        SettingsPageBody(reset: { AppPreferences().reset(.keepAwake) }) {
            SettingsGroup(title: "Now") { statusRow }
            SettingsGroup(title: "By hand") {
                SettingsTabRow(title: "Length", detail: "What the menu's Keep awake item and the shortcut start", first: true) {
                    ChoicePopUp(
                        label: "Length", options: AwakeLength.choices.map { (value: $0, title: AwakeLength.title($0)) },
                        selection: Binding(get: { AwakeLength.valid(minutes) }, set: { minutes = $0 })
                    )
                }
                SettingsTabRow(title: "Keep the screen on", detail: "Off lets the screen sleep while the Mac stays awake: enough for agents, and it saves power") {
                    Toggle("Keep the screen on", isOn: $screen).labelsHidden().toggleStyle(.switch)
                }
                ShortcutRecorderRow(
                    shortcutText: shortcutText, title: "Shortcut", detail: "Turns keep awake on or off from any app, with no window", name: "Keep awake shortcut",
                    emptyText: "None", problem: controller.shortcutProblem,
                    current: { AppPreferences().awakeShortcut }, save: { AppPreferences().awakeShortcut = $0 },
                    taken: { $0 == AppPreferences().dictationShortcut ? "Dictation uses these keys" : nil })
            }
            SettingsGroup(title: "With agents") {
                SettingsTabRow(title: "Keep awake while agents work", detail: "While an epic runs or a session works, so a long job is not cut by sleep", first: true) {
                    Toggle("Keep awake while agents work", isOn: $agents).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(title: "Stay awake after they finish", detail: "Time to read the result before the Mac may sleep") {
                    ChoicePopUp(
                        label: "Stay awake after they finish",
                        options: AwakeSettings.graceChoices.map { (value: $0, title: $0 == 0 ? "Right away" : "\($0) min") },
                        selection: Binding(get: { AwakeSettings.graceChoices.contains(grace) ? grace : AwakeSettings().graceMinutes }, set: { grace = $0 })
                    )
                    .disabled(agents == false)
                }
            }
            SettingsGroup(title: "Battery and notices") {
                SettingsTabRow(title: "On battery", detail: "It goes on by itself when the Mac is plugged in or charged again", first: true) {
                    ChoicePopUp(
                        label: "On battery", options: BatteryRule.allCases.map { (value: $0.rawValue, title: $0.title) },
                        selection: Binding(get: { BatteryRule(rawValue: battery)?.rawValue ?? BatteryRule.standard.rawValue }, set: { battery = $0 })
                    )
                }
                SettingsTabRow(title: "Tell me when it stops by itself", detail: "A notification when the time runs out or the battery ends it. Not when you turn it off") {
                    Toggle("Tell me when it stops by itself", isOn: $notifies).labelsHidden().toggleStyle(.switch)
                }
            }
        }
    }

    /// The state in a sentence (it says Paused and why when the battery holds it) and the switch that does what the menu's first item does. The time left is read again every 20 seconds.
    private var statusRow: some View {
        TimelineView(.periodic(from: .now, by: 20)) { context in
            let settings = controller.settings
            let decision = controller.decision
            // the tick only makes this draw again: the time left is read from the clock now, or it would lag by up to a tick
            let _ = context.date
            let title = awakeStatus(decision, settings: settings, now: Date())
            SettingsTabRow(title: title, detail: "Closing the lid or choosing Sleep still puts the Mac to sleep", first: true) {
                Toggle("Keep awake", isOn: Binding(
                    get: { decision.isManual },
                    set: { _ in
                        controller.toggle()
                        AccessibilityNotification.Announcement(awakeStatus(controller.decision, settings: controller.settings, now: Date())).post()
                    })
                ).labelsHidden().toggleStyle(.switch)
            }
        }
    }
}
