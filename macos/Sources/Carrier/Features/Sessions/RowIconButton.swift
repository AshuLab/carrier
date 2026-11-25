import CarrierCore
import CarrierUI
import SwiftUI

/// A round 28 pt button of a list row's right edge; one that is on (a pinned session's Pin) wears the accent.
struct RowIconButton: View {
    let symbol: AppIcon
    let title: String
    var selected = false
    /// Why the button is off, in words: the tooltip then.
    var why: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Glyph(symbol, size: 12).foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary)).frame(width: 28, height: 28)
                .background(Circle().fill(selected ? AnyShapeStyle(.tint.opacity(0.2)) : AnyShapeStyle(Color.secondary.opacity(0.14))))
        }
        .buttonStyle(.plain).disabled(why != nil).opacity(why == nil ? 1 : 0.4).help(why ?? title).accessibilityLabel(title).accessibilityHint(why ?? "").accessibilityAddTraits(selected ? .isSelected : [])
    }
}
