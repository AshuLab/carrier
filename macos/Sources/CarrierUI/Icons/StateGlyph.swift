import CarrierCore
import SwiftUI

/// The glyph of an epic's state, 20 points square as in the mockup: a turning ring while it runs, a filled disc with a mark (or the symbol of its
/// shape) for a state that needs you or is done, and a hollow grey circle while it waits. The area says which, in which color, with which mark and
/// words (`StateGlyph(state:attention:)`); the piece only draws them.
struct StateGlyph: View {
    enum Look {
        case ring
        /// `symbol` is what the disc wears instead of `mark` when the person asked for states to be told apart by shape.
        case disc(color: Color, mark: String, symbol: AppIcon?)
        case hollow
    }

    let look: Look
    /// What a screen reader says for it.
    let label: String

    var body: some View {
        glyph.frame(width: 20, height: 20).accessibilityElement(children: .ignore).accessibilityLabel(label)
    }

    @ViewBuilder private var glyph: some View {
        switch look {
        case .ring: SpinningRing()
        case .disc(let color, let mark, let symbol): Disc(color: color, mark: mark, symbol: symbol)
        case .hollow: Circle().strokeBorder(Color.gray, lineWidth: 2).frame(width: 14, height: 14)
        }
    }
}
