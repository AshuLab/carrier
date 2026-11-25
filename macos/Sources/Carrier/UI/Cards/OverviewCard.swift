import SwiftUI

/// A Carrier home card: a rounded fill with its rows divided by hairlines.
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
