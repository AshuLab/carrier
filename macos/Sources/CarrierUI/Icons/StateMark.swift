import CarrierCore
import SwiftUI

/// What a state wears inside its glyph: its text, or, with "Tell states apart by shape" on (`PieceTheme.statesByShape`), the symbol of its shape. A state with
/// no symbol, or no text with the setting off, draws nothing.
struct StateMark: View {
    var text = ""
    let symbol: AppIcon?
    let size: CGFloat
    var weight = Font.Weight.heavy
    @Environment(\.pieceTheme) private var theme

    @ViewBuilder var body: some View {
        if theme.statesByShape, let symbol {
            Glyph(symbol, size: size, bold: true)
        } else if text.isEmpty == false {
            Text(text).scaledFont(size, weight: weight)
        }
    }
}
