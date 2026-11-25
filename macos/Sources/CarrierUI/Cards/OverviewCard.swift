import CarrierCore
import SwiftUI

/// A Carrier home card: a rounded fill with its rows divided by hairlines.
public struct OverviewCard<Content: View>: View {
    /// Dividers run the card's whole width instead of stopping at its padding: the rows are one unit.
    var fullWidthDividers = false
    @ViewBuilder let content: Content

    public init(fullWidthDividers: Bool = false, @ViewBuilder content: () -> Content) { self.fullWidthDividers = fullWidthDividers; self.content = content() }

    public var body: some View {
        VStack(spacing: Tokens.Space.none) {
            Group(subviews: content) { rows in
                ForEach(rows) { row in
                    if row.id != rows.first?.id { Divider().padding(.horizontal, fullWidthDividers ? -Tokens.Space.s14 : Tokens.Space.none) }
                    row
                }
            }
        }
        .padding(.horizontal, Tokens.Space.s14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.panel).fill(Color.secondary.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.panel).strokeBorder(Color.secondary.opacity(0.12), lineWidth: 0.5))
    }
}
