import CarrierCore
import SwiftUI

/// A state's disc: a filled circle with its mark in white. With "Tell states apart by shape" on (`PieceTheme.statesByShape`), the state's own symbol in
/// its colour instead (a triangle, a seal, an octagon, the mark cut out of it): the outline is what tells it apart, and one symbol centred in its box
/// replaces a disc with a symbol inside it. A state with no `symbol` keeps its disc.
struct Disc: View {
    let color: Color
    let mark: String
    var symbol: AppIcon?
    var size: CGFloat = 18
    @Environment(\.pieceTheme) private var theme

    var body: some View {
        if theme.statesByShape, let symbol {
            Glyph(symbol, size: size).foregroundStyle(color)
        } else {
            Circle().fill(color).frame(width: size, height: size)
                .overlay { Text(mark).scaledFont(size * 0.55, weight: .heavy).foregroundStyle(.white) }
        }
    }
}
