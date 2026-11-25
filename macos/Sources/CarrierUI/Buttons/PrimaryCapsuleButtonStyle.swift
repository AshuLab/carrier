import CarrierCore
import SwiftUI

/// The main button of a tab's footer: a flat accent capsule, grey when it cannot be pressed.
public struct PrimaryCapsuleButtonStyle: ButtonStyle {
    /// The one button a screen is about (Start Carrier), bigger than a footer's.
    var large = false

    public init(large: Bool = false) { self.large = large }

    public func makeBody(configuration: Configuration) -> some View { Face(configuration: configuration, large: large) }

    private struct Face: View {
        let configuration: ButtonStyleConfiguration
        let large: Bool
        @Environment(\.isEnabled) private var enabled
        @Environment(\.controlSize) private var size
        @Environment(\.pieceTheme) private var theme

        var body: some View {
            let small = !large && (size == .small || size == .mini)
            configuration.label.scaledFont(large ? 15 : (small ? 12 : 13), weight: .semibold)
                .foregroundStyle(enabled ? Color.white : Color.secondary)
                .padding(.horizontal, large ? Tokens.Space.s24 : (small ? Tokens.Space.s11 : Tokens.Space.s16))
                .padding(.vertical, large ? Tokens.Space.s9 : (small ? Tokens.Space.s3 : Tokens.Space.s6))
                // the accent is a light pastel on the dark themes: darkened for the fill so the white label reads over any theme
                .background(Capsule().fill(enabled ? theme.accent.mix(with: .black, by: 0.4) : Color.secondary.opacity(0.18)))
                .contentShape(Capsule())
                .shadow(color: .black.opacity(enabled ? 0.3 : 0), radius: 1, y: 1)
                .opacity(configuration.isPressed ? 0.8 : 1)
        }
    }
}
