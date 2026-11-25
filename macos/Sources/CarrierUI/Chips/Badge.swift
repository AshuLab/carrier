import CarrierCore
import SwiftUI

/// What a state of a thing is, in a word and an icon, in its colour: indigo is private, green is watched.
struct Badge: View {
    let text: String
    let icon: AppIcon
    let tint: Color

    var body: some View {
        Label(text, icon: icon).font(.caption.weight(.medium)).foregroundStyle(tint)
            .padding(.horizontal, Tokens.Space.s8).padding(.vertical, Tokens.Space.s2).background(Capsule().fill(tint.opacity(0.14)))
    }
}
