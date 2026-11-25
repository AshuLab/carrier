import CarrierCore
import SwiftUI

/// A capsule with a word in it: its color at 16% under the same color, so the state is never the color alone.
struct StatusChip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text).scaledFont(11, weight: .medium).foregroundStyle(tint)
            .padding(.horizontal, Tokens.Space.s8).padding(.vertical, Tokens.Space.s1)
            .background(Capsule().fill(tint.opacity(0.16)))
    }
}
