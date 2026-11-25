import SwiftUI

// What the new-session draft's sheets and controls have in common.

/// How tall a control of the draft is: the ones of the sentence and the selects of the box.
let controlHeight: CGFloat = 28

extension View {
    /// The fill and the edge of a control of the draft, the text's own colour faint so they follow the appearance; a `tint` colours both.
    func controlSurface(tint: Color = .primary) -> some View {
        background(
            RoundedRectangle(cornerRadius: 8).fill(tint.opacity(tint == .primary ? 0.07 : 0.14))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tint.opacity(tint == .primary ? 0.14 : 0.4), lineWidth: 1))
        )
    }
}
