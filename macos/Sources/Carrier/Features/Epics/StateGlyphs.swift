import CarrierCore
import CarrierUI
import SwiftUI

extension GlyphTint {
    /// The system's color of that name.
    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .blue: .blue
        case .green: .green
        case .gray: .gray
        }
    }
}

extension Attention {
    /// Red when something failed, orange when a person's input is needed (and for an epic whose kind is not known).
    var color: Color { tint.color }
}

extension StateGlyph {
    /// The glyph of an epic's state, as `EpicMenuState.glyphLook` says (the area builds it; the piece draws it).
    init(state: EpicMenuState, attention: Attention? = nil) {
        let look = state.glyphLook(attention: attention)
        let drawn: Look =
            switch look.form {
            case .ring: .ring
            case .disc: .disc(color: look.tint.color, mark: look.mark, symbol: look.shape.map(stateSymbol))
            case .hollow: .hollow
            }
        self.init(look: drawn, label: look.label)
    }
}

extension Disc {
    /// A disc whose state has `shape`, which it shows as the symbol when states are told apart by shape.
    init(color: Color, mark: String, shape: StateShape?, size: CGFloat = 18) {
        self.init(color: color, mark: mark, symbol: shape.map(stateSymbol), size: size)
    }
}

extension StateMark {
    /// A mark whose state has `shape`, which it shows as the symbol when states are told apart by shape.
    init(text: String = "", shape: StateShape?, size: CGFloat, weight: Font.Weight = .heavy) {
        self.init(text: text, symbol: shape.map(stateSymbol), size: size, weight: weight)
    }
}
