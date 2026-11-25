import CarrierCore
import SwiftUI

/// A row that goes somewhere: a chevron at its end. Without an `action` it is a plain row. A tap gesture, not a button, so
/// buttons inside the row (Open PR) keep their own clicks.
struct OverviewLinkRow<Content: View>: View {
    var action: (() -> Void)?
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: Tokens.Space.s12) {
            content
            if action != nil {
                Glyph(.chevronRight, size: 11).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, Tokens.Space.s12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { action?() }
        .accessibilityAddTraits(action == nil ? [] : .isButton)
    }
}
