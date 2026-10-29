import SwiftUI

// What the sheets of the new-session draft (the workspace and the start branch) have in common.

/// What a state of a thing is, in a word and an icon, in its colour: indigo is private, green is watched.
struct Badge: View {
    let text: String
    let icon: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: icon).font(.caption.weight(.medium)).foregroundStyle(tint)
            .padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(tint.opacity(0.14)))
    }
}

/// What a click on the row under the pointer does, as a small solid pill at its end. It is always laid out and only shown under the
/// pointer, so the row is the same height with or without it.
struct RowHint: View {
    let text: String
    let shown: Bool

    var body: some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 3).background(Capsule().fill(Color.accentColor))
            .opacity(shown ? 1 : 0).accessibilityHidden(true)
    }
}

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
        .background(RoundedRectangle(cornerRadius: 8).fill(fill ?? (hovering && enabled ? Color.secondary.opacity(0.14) : .clear)))
        .onHover { hovering = $0 }
    }
}
