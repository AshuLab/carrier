import CarrierCore
import SwiftUI

/// A row that is a button: it takes a faint fill under the pointer, or `fill` when it is the chosen one.
struct HoverRow<Content: View>: View {
    let action: () -> Void
    var fill: Color?
    @ViewBuilder let content: (Bool) -> Content
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            content(hovering && enabled).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.control).fill(fill ?? (hovering && enabled ? Color.secondary.opacity(0.14) : .clear)))
        .onHover { hovering = $0 }
    }
}
