import SwiftUI

/// The chevron at the right of a card's line or row: right when folded, down when open.
public struct CardChevron: View {
    let open: Bool
    var width: CGFloat = 16

    public init(open: Bool, width: CGFloat = 16) { self.open = open; self.width = width }

    public var body: some View {
        Glyph(.chevronRight, size: 9).foregroundStyle(.tertiary)
            .rotationEffect(.degrees(open ? 90 : 0)).frame(width: width).accessibilityHidden(true)
    }
}
