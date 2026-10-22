import SwiftUI

/// An Overview section's title, above the card it heads: the name and, small, what it counts.
struct OverviewTitle: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.system(size: 15, weight: .semibold))
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 2)
    }
}

/// An Overview card: a rounded fill with its rows divided by hairlines.
struct OverviewCard<Content: View>: View {
    /// Dividers run the card's whole width instead of stopping at its padding: the rows are one unit.
    var fullWidthDividers = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(rows) { row in
                    if row.id != rows.first?.id { Divider().padding(.horizontal, fullWidthDividers ? -14 : 0) }
                    row
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.secondary.opacity(0.12), lineWidth: 0.5))
    }
}

/// A row that goes somewhere: a chevron at its end. Without an `action` it is a plain row. A tap gesture, not a button, so
/// buttons inside the row (Open PR) keep their own clicks.
struct OverviewLinkRow<Content: View>: View {
    var action: (() -> Void)?
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 12) {
            content
            if action != nil {
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { action?() }
        .accessibilityAddTraits(action == nil ? [] : .isButton)
    }
}
