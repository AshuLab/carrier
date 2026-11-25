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
            HStack(spacing: Tokens.Space.s10) {
                ForEach([today(17, 49), today(15, 40), today(9, 5)], id: \.self) { date in
                    Text(timeText(date, now: now, format: format)).monospacedDigit()
                        .frame(maxWidth: .infinity).padding(.vertical, Tokens.Space.s10)
                        .background(RoundedRectangle(cornerRadius: Tokens.Radius.tile).fill(Color.secondary.opacity(0.1)))
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
        let page = generalPage()
        SettingsPageBody(reset: { AppPreferences().reset(.general) }) {
            SettingsGroup(id: "menu-bar", title: page.menuBar) {
                SettingsTabRow(id: "icon-style", title: page.iconStyle.title, detail: page.iconStyle.detail, first: true) {
                    ChoicePopUp(
                        label: page.iconStyle.title, options: IconStyle.allCases.map { (value: $0, title: $0.title()) },
                        selection: $style
                    )
                }
                SettingsTabRow(id: "animate-the-icon", title: page.animate.title, detail: page.animate.detail) {
                    Toggle(page.animate.title, isOn: $animates).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "list-epics-in-the-menu", title: page.listEpics.title, detail: page.listEpics.detail) {
                    Toggle(page.listEpics.title, isOn: $showsEpics).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsGroup(id: "display", title: page.display) {
                SettingsTabRow(id: "time-format", title: page.timeFormat.title, detail: page.timeFormat.detail, first: true) {
                    ChoicePopUp(
                        label: page.timeFormat.title, options: [(value: TimeStyle.relative, title: page.relative), (value: .clock, title: page.clockOption)],
                        selection: $timeStyle
                    )
                }
                SettingsTabRow(id: "clock", title: page.clock.title, detail: page.clock.detail) {
                    ChoicePopUp(
                        label: page.clock.title, options: [(value: ClockHours.system, title: page.system), (value: .h12, title: page.hours12), (value: .h24, title: page.hours24)],
                        selection: $clockHours
                    )
                }
                displayPreview()
            }
        }
    }
}
