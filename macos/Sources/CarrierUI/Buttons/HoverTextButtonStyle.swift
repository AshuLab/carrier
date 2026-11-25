import CarrierCore
import SwiftUI

/// A button that is only its text (or icon) until the pointer is over it, when a pill lights behind it: light enough to sit beside a
/// message without weighing as much as it.
struct HoverTextButtonStyle: ButtonStyle {
    let tint: Color?
    /// Turns red under the pointer, as a choice that does not allow does.
    var danger = false
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaledFont(12, weight: .medium)
            .foregroundStyle(danger && hovered ? Color.red : tint ?? (hovered ? Color.primary : Color.secondary))
            .padding(.horizontal, Tokens.Space.s10).frame(minWidth: 26, minHeight: 26)
            .background(Capsule().fill(danger && hovered ? Color.red.opacity(0.14) : Color.primary.opacity(configuration.isPressed ? 0.16 : hovered ? 0.09 : 0)))
            .opacity(enabled ? 1 : 0.4)
            .contentShape(Capsule())
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.12), value: hovered)
    }
}
