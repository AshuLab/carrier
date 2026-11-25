import CarrierCore
import SwiftUI

struct GeneralTabView: View {
    /// Three times as the two settings write them now, taken as if it were 6:00 PM: 11 minutes ago, this afternoon and this morning, so a
    /// clock shows both its PM and its AM.
    private func displayPreview() -> some View {
        let calendar = Calendar.current
        func today(_ hour: Int, _ minute: Int) -> Date { calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date() }
        let now = today(18, 0)
        let format = TimeFormat.stored()
        return SettingsPreview {
            HStack(spacing: 10) {
                ForEach([today(17, 49), today(15, 40), today(9, 5)], id: \.self) { date in
                    Text(timeText(date, now: now, format: format)).monospacedDigit()
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.1)))
                }
            }
        }
    }

    @AppStorage(Preference.menuIconStyle) private var style
    @AppStorage(Preference.menuAnimate) private var animates
    @AppStorage(Preference.menuShowEpics) private var showsEpics
    @AppStorage(Preference.displayTimeStyle) private var timeStyle
    @AppStorage(Preference.displayClock) private var clockHours

    var body: some View {
        SettingsPageBody(reset: { AppPreferences().reset(.general) }) {
            SettingsGroup(id: "menu-bar", title: "Menu bar") {
                SettingsTabRow(id: "icon-style", title: "Icon style", detail: "What the icon in the menu bar shows", first: true) {
                    ChoicePopUp(
                        label: "Icon style", options: IconStyle.allCases.map { (value: $0, title: $0.title) },
                        selection: $style
                    )
                }
                SettingsTabRow(id: "animate-the-icon", title: "Animate the icon", detail: "A segment moves over the bar while epics run, except in Low Power Mode") {
                    Toggle("Animate the icon", isOn: $animates).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "list-epics-in-the-menu", title: "List epics in the menu", detail: "The epics that run or wait show under the status") {
                    Toggle("List epics in the menu", isOn: $showsEpics).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsGroup(id: "display", title: "Display") {
                SettingsTabRow(id: "time-format", title: "Time format", detail: "Ages read \"11m\" or as a time, \"14:32\"", first: true) {
                    ChoicePopUp(
                        label: "Time format", options: [(value: TimeStyle.relative, title: "Relative"), (value: .clock, title: "Clock")],
                        selection: $timeStyle
                    )
                }
                SettingsTabRow(id: "clock", title: "Clock", detail: "How clock times count the hours") {
                    ChoicePopUp(
                        label: "Clock", options: [(value: ClockHours.system, title: "System"), (value: .h12, title: "12 hours"), (value: .h24, title: "24 hours")],
                        selection: $clockHours
                    )
                }
                displayPreview()
            }
        }
    }
}
