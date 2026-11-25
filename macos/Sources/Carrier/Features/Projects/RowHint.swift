import CarrierCore
import SwiftUI

/// What a click on the row under the pointer does, as a small solid pill at its end. It is always laid out and only shown under the
/// pointer, so the row is the same height with or without it.
struct RowHint: View {
    @Environment(\.pieceTheme) private var theme
    let text: String
    let shown: Bool

    var body: some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(.white)
            // the deepened accent the title bar's pills have under their white words: the accent itself, a light one, left the word without contrast
            .padding(.horizontal, Tokens.Space.s10).padding(.vertical, Tokens.Space.s3).background(Capsule().fill(theme.accentGlass))
            .opacity(shown ? 1 : 0).accessibilityHidden(true)
    }
}
