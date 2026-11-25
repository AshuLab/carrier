import CarrierCore
import SwiftUI

/// A capsule with a word in it: its color at 16% under the same color, so the state is never the color alone.
public struct StatusChip: View {
    let text: String
    let tint: Color

    public init(text: String, tint: Color) { self.text = text; self.tint = tint }

    public var body: some View {
        Text(text).scaledFont(11, weight: .medium).foregroundStyle(tint)
            .padding(.horizontal, Tokens.Space.s8).padding(.vertical, Tokens.Space.s1)
            .background(Capsule().fill(tint.opacity(0.16)))
    }
}
