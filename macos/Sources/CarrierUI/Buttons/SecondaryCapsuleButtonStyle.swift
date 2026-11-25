import SwiftUI

/// Every other button of Settings: a quiet capsule in the neutral, so the one in the accent (`PrimaryCapsuleButtonStyle`: Done, Save) is
/// the only one that reads as the screen's main action. Smaller under `.controlSize(.small)`, for the buttons that sit in a row.
public struct SecondaryCapsuleButtonStyle: ButtonStyle {

    public init() {}
    public func makeBody(configuration: Configuration) -> some View { Face(configuration: configuration) }

    private struct Face: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var enabled
        @Environment(\.controlSize) private var size
        @State private var hovered = false

        var body: some View {
            let small = size == .small || size == .mini
            configuration.label.scaledFont(small ? 12 : 13, weight: .medium)
                .foregroundStyle(enabled ? Color.primary : Color.secondary)
                .padding(.horizontal, small ? 11 : 16).padding(.vertical, small ? 3 : 6)
                .background(Capsule().fill(Color.primary.opacity(configuration.isPressed ? 0.2 : hovered ? 0.15 : 0.09)))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                .opacity(enabled ? 1 : 0.5)
                .contentShape(Capsule())
                .onHover { hovered = $0 }
                .animation(.easeOut(duration: 0.12), value: hovered)
        }
    }
}
