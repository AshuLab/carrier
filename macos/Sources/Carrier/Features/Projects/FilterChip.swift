import CarrierCore
import SwiftUI

/// A filter as a small capsule that is on or off: a quiet fill and a fine edge when off, the person's accent when on (the piece of `SegmentedChoice`, in its own
/// capsule). For a set that grows with the data (the tags of the projects) or filters that are not one list of choices; a few fixed choices are a `SegmentedChoice`.
/// A row of them narrows a list; the first of a set that excludes each other is "All".
struct FilterChip: View {
    let title: String
    var icon: AppIcon?
    let on: Bool
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.pieceTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Glyph(icon, size: 11) }
                Text(title).scaledFont(12, weight: .medium)
            }
            .foregroundStyle(on ? theme.accentInk(scheme) : hovered ? Color.primary : Color.secondary)
            .padding(.horizontal, 11).padding(.vertical, 4)
            .background(Capsule().fill(on ? theme.accent.opacity(0.24) : Color.primary.opacity(hovered ? 0.1 : 0.06)))
            .overlay(Capsule().strokeBorder(on ? theme.accent.opacity(0.45) : Color.primary.opacity(0.06), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain).onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
