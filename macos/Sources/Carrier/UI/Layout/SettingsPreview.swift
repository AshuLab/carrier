import SwiftUI

/// A sample of what the rows around it change, inside the group of those rows so that it sits next to the controls.
struct SettingsPreview<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.settingsForm) private var form

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview").sectionLabel()
            content.frame(maxWidth: .infinity)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { if form == false { SettingsDivider() } }
    }
}
