import CarrierCore
import SwiftUI

/// The card every group of rows of Settings sits on, with the room its rows need at the sides.
public struct SettingsTabCard<Content: View>: View {
    @ViewBuilder var content: Content

    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        VStack(spacing: Tokens.Space.none) { content }
            .padding(.horizontal, Tokens.Space.s14)
            .settingsCard()
    }
}

extension View {
    /// The card every group of rows, list and note of Settings sits on: rounded 14, `secondary` at 7 %.
    public func settingsCard() -> some View { background(RoundedRectangle(cornerRadius: Tokens.Radius.roomy).fill(Color.secondary.opacity(0.07))) }
}
