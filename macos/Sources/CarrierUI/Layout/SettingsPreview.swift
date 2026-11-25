import CarrierCore
import SwiftUI

/// A sample of what the rows around it change, inside the group of those rows so that it sits next to the controls.
public struct SettingsPreview<Content: View>: View {
    @ViewBuilder var content: Content

    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    @Environment(\.settingsForm) private var form

    public var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s8) {
            Text(Copy.piecePreview()).sectionLabel()
            content.frame(maxWidth: .infinity)
        }
        .padding(.vertical, Tokens.Space.s12)
        .overlay(alignment: .top) { if form == false { SettingsDivider() } }
    }
}
