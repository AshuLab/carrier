import AppKit
import CarrierCore
import SwiftUI

/// A copy button after whatever it modifies, which fades in while the pointer is over the pair and shows a check for a moment once it has
/// copied. The room is kept while it is hidden, so the text does not move when it appears.
private struct CopyOnHover: ViewModifier {
    let text: String
    @State private var hovered = false
    @State private var copied = false

    func body(content: Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s4) {
            content
            Button(action: copy) {
                Glyph(copied ? .check : .copy, size: 11)
                    .foregroundStyle(copied ? Color.green : Color.secondary).frame(width: 20, height: 20)
                    .background(Circle().fill(Color.primary.opacity(0.1))).contentShape(Circle())
            }
            .buttonStyle(.plain).help(Copy.settingsCopy()).accessibilityLabel(Copy.settingsCopy())
            .opacity(hovered || copied ? 1 : 0).allowsHitTesting(hovered || copied)
            .animation(.easeOut(duration: 0.15), value: hovered)
        }
        .onHover { hovered = $0 }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            copied = false
        }
    }
}

extension View {
    /// A copy button for `text` after this view, shown while the pointer is over it: for a path, a URL or an error a person may want to paste.
    func copyOnHover(_ text: String) -> some View { modifier(CopyOnHover(text: text)) }
}
