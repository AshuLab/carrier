import CarrierCore
import CarrierUI
import SwiftUI

/// What a session's row says of its background processes (a command, a monitor, a dev server): the terminal glyph and how many, in a small grey
/// capsule with no colour of its own and no motion, at the right of the second line. Nothing here says the model works: it is a fact beside the state.
/// The capsule's fill follows the row's state as the third line's does, so it does not shout on the selected row.
struct SessionProcessMark: View {
    let count: Int
    @Environment(\.rowState) private var state

    private var fill: Color {
        switch state {
        case .resting: Color.primary.opacity(0.08)
        case .hovered: Color.primary.opacity(0.13)
        case .selected: Color.white.opacity(0.14)
        }
    }

    private var words: Color { state == .selected ? Color.white.opacity(0.72) : .secondary }

    var body: some View {
        HStack(spacing: Tokens.Space.s3) {
            Glyph(.terminal, size: 9)
            Text("\(count)").scaledFont(10.5, weight: .medium).monospacedDigit()
        }
        .foregroundStyle(words).lineLimit(1).fixedSize()
        .padding(.horizontal, Tokens.Space.s6).frame(height: 15)
        .background(Capsule().fill(fill))
        .animation(.easeOut(duration: 0.12), value: state)
        .accessibilityHidden(true)
    }
}
