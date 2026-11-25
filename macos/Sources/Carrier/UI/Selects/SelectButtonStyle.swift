import SwiftUI

/// The face of a button that opens a choice (the model picker's): no box, its words and `SelectChevron` after them as a system pop-up in a form has them,
/// a little dimmer under the pointer and when pressed.
struct SelectButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Face(configuration: configuration) }

    private struct Face: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false

        var body: some View {
            configuration.label
                .padding(.vertical, 4).padding(.horizontal, 6)
                // the box a pop-up has, shown only under the pointer (and a little more when pressed); the margin it takes is given back, so the
                // word stays where it was and a row's right edge is the same with and without it
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(enabled ? (configuration.isPressed ? 0.14 : hovered ? 0.08 : 0) : 0)))
                .padding(.horizontal, -6)
                .opacity(enabled ? 1 : 0.5)
                .contentShape(Rectangle())
                .onHover { hovered = $0 }
                .animation(.easeOut(duration: 0.12), value: hovered)
        }
    }
}
