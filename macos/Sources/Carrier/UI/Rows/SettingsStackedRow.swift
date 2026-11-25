import SwiftUI

/// A row whose control is wide (a text of several lines): the title and the detail on top and the control under them, the whole width of the card.
struct SettingsStackedRow<Control: View>: View {
    var id: String?
    let title: String
    let detail: String
    var first = false
    @ViewBuilder var control: Control
    @Environment(\.settingsForm) private var form

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).fontWeight(.medium)
                if detail.isEmpty == false { Text(detail).scaledFont(11).foregroundStyle(.secondary) }
            }
            control
        }
        .padding(.vertical, form ? 4 : 12).frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { if first == false && form == false { SettingsDivider() } }
        .settingsAnchored(id)
    }
}
