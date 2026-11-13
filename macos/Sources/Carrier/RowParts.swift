import SwiftUI

/// The small outlined capsule beside a session's title (its workspace, "Archived").
struct RowTag: View {
    let text: String

    var body: some View {
        Text(text).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().strokeBorder(Color.secondary.opacity(0.5)))
    }
}

/// A round 28 pt button of a list row's right edge; one that is on (a pinned session's Pin) wears the accent.
struct RowIconButton: View {
    let symbol: String
    let title: String
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.scaled(12)).foregroundStyle(selected ? Color.themeAccent : .secondary).frame(width: 28, height: 28)
                .background(Circle().fill(selected ? Color.themeAccent.opacity(0.2) : Color.secondary.opacity(0.14)))
        }
        .buttonStyle(.plain).help(title).accessibilityLabel(title).accessibilityAddTraits(selected ? .isSelected : [])
    }
}
