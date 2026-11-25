import CarrierCore
import SwiftUI

/// The states of a sidebar button, drawn as the shape of the button: none at rest, a faint fill on hover, a stronger one while the mouse is
/// down, the middle one while what it opened is `open`, and the whole button dimmed when it is disabled (no fill then).
struct HoverFillButtonStyle: ButtonStyle {
    var open = false
    var radius: CGFloat = Tokens.Radius.small

    func makeBody(configuration: Configuration) -> some View {
        Shape(configuration: configuration, open: open, radius: radius)
    }

    private struct Shape: View {
        let configuration: ButtonStyleConfiguration
        let open: Bool
        let radius: CGFloat
        @State private var hovered = false
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            let fill = configuration.isPressed ? 0.2 : open ? (hovered ? 0.2 : 0.15) : hovered ? 0.1 : 0
            configuration.label
                .background(RoundedRectangle(cornerRadius: radius).fill(Color.primary.opacity(enabled ? fill : 0)))
                .opacity(enabled ? 1 : 0.35)
                .onHover { hovered = $0 }
                .animation(.easeOut(duration: 0.12), value: fill)
        }
    }
}
