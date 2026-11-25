import CarrierCore
import SwiftUI

/// What a state of a thing is, in a word and an icon, in its colour: indigo is private, green is watched.
public struct Badge: View {
    let text: String
    let icon: AppIcon
    let tint: Color

    public init(text: String, icon: AppIcon, tint: Color) { self.text = text; self.icon = icon; self.tint = tint }

    public var body: some View {
        Label(text, icon: icon).font(.caption.weight(.medium)).foregroundStyle(tint)
            .padding(.horizontal, Tokens.Space.s8).padding(.vertical, Tokens.Space.s2).background(Capsule().fill(tint.opacity(0.14)))
    }
}
