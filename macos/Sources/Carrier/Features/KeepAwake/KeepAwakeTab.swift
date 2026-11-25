import CarrierCore
import SwiftUI

/// The Keep awake page: the state now with the button that changes it, how a keep awake by hand starts, what follows the agents, and what the battery and the
/// notification do. Each setting is read by `KeepAwakeController` as it is changed; nothing is restarted.
struct KeepAwakeTabView: View {
    var controller = KeepAwakeController.shared
    @AppStorage(Preference.awakeScreen) private var screen
    @AppStorage(Preference.awakeMinutes) private var minutes
    @AppStorage(Preference.awakeAgents) private var agents
    @AppStorage(Preference.awakeGrace) private var grace
    @AppStorage(Preference.awakeBattery) private var battery
    @AppStorage(Preference.awakeNotify) private var notifies
    @AppStorage(Preference.awakeShortcut) private var shortcutText

    var body: some View {
        SettingsPageBody(reset: { AppPreferences().reset(.keepAwake) }) {
            SettingsGroup(id: "now", title: Copy.awakeGroupNow()) { statusRow }
            SettingsGroup(id: "by-hand", title: Copy.awakeGroupByHand()) {
                SettingsTabRow(id: "length", title: Copy.awakeRowLength(), detail: Copy.awakeRowLengthDetail(), first: true) {
                    ChoicePopUp(
                        label: Copy.awakeRowLength(), options: AwakeLength.choices.map { (value: $0, title: AwakeLength.title($0)) },
                        selection: Binding(get: { AwakeLength.valid(minutes) }, set: { minutes = $0 })
                    )
                }
                SettingsTabRow(id: "keep-the-screen-on", title: Copy.awakeRowScreen(), detail: Copy.awakeRowScreenDetail()) {
                    Toggle(Copy.awakeRowScreen(), isOn: $screen).labelsHidden().toggleStyle(.switch)
                }
                ShortcutRecorderRow(
                    id: "shortcut", shortcutText: shortcutText ?? "", title: Copy.awakeRowShortcut(), detail: Copy.awakeRowShortcutDetail(), name: Copy.awakeShortcutName(),
                    emptyText: Copy.awakeShortcutNone(), problem: controller.shortcutProblem,
                    current: { AppPreferences().awakeShortcut }, save: { AppPreferences().awakeShortcut = $0 },
                    taken: { $0 == AppPreferences().dictationShortcut ? Copy.awakeShortcutDictation() : nil })
            }
            SettingsGroup(id: "with-agents", title: Copy.awakeGroupAgents()) {
                SettingsTabRow(id: "keep-awake-while-agents-work", title: Copy.awakeRowAgents(), detail: Copy.awakeRowAgentsDetail(), first: true) {
                    Toggle(Copy.awakeRowAgents(), isOn: $agents).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "stay-awake-after-they-finish", title: Copy.awakeRowGrace(), detail: Copy.awakeRowGraceDetail()) {
                    ChoicePopUp(
                        label: Copy.awakeRowGrace(),
                        options: AwakeSettings.graceChoices.map { (value: $0, title: $0 == 0 ? Copy.awakeGraceNow() : Copy.awakeMinutes(minutes: $0)) },
                        selection: Binding(get: { AwakeSettings.graceChoices.contains(grace) ? grace : AwakeSettings().graceMinutes }, set: { grace = $0 })
                    )
                    .disabled(agents == false)
                }
            }
            SettingsGroup(id: "battery-and-notices", title: Copy.awakeGroupBattery()) {
                SettingsTabRow(id: "on-battery", title: Copy.awakeRowBattery(), detail: Copy.awakeRowBatteryDetail(), first: true) {
                    ChoicePopUp(
                        label: Copy.awakeRowBattery(), options: BatteryRule.allCases.map { (value: $0, title: $0.title()) },
                        selection: $battery
                    )
                }
                SettingsTabRow(id: "tell-me-when-it-stops-by-itself", title: Copy.awakeRowNotify(), detail: Copy.awakeRowNotifyDetail()) {
                    Toggle(Copy.awakeRowNotify(), isOn: $notifies).labelsHidden().toggleStyle(.switch)
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
            SettingsTabRow(title: title, detail: Copy.awakeStatusDetail(), first: true) {
                Toggle(Copy.awakeKeep(), isOn: Binding(
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
