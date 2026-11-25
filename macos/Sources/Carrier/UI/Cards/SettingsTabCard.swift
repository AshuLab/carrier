import SwiftUI

/// The card every group of rows of Settings sits on, with the room its rows need at the sides.
struct SettingsTabCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .padding(.horizontal, 14)
            .settingsCard()
    }
}

extension View {
    /// The card every group of rows, list and note of Settings sits on: rounded 14, `secondary` at 7 %.
    func settingsCard() -> some View { background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.07))) }
}
