import CarrierCore
import SwiftUI

/// An action of a `NoticeCard`, in the card's own colour so it reads on the glass the card is filled with and does not depend on the accent
/// the person chose: the card's colour, lighter on dark and deeper on light, on a pill of that colour. `quiet` is the secondary action (Copy
/// details, the cross that drops a message): near-primary words and a pill only under the pointer.
struct NoticeActionStyle: ButtonStyle {
    var quiet = false

    func makeBody(configuration: Configuration) -> some View { Face(configuration: configuration, quiet: quiet) }

    private struct Face: View {
        let configuration: ButtonStyleConfiguration
        let quiet: Bool
        @Environment(\.noticeTint) private var tint
        @Environment(\.colorScheme) private var scheme
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false

        var body: some View {
            let words = quiet ? Color.primary.opacity(0.78) : tint.mix(with: scheme == .dark ? .white : .black, by: scheme == .dark ? 0.4 : 0.45)
            let pill = quiet ? Color.primary.opacity(configuration.isPressed ? 0.2 : hovered ? 0.14 : 0) : tint.opacity(configuration.isPressed ? 0.46 : hovered ? 0.38 : 0.24)
            configuration.label
                .scaledFont(12, weight: .medium).foregroundStyle(words)
                .padding(.horizontal, Tokens.Space.s10).frame(minWidth: 26, minHeight: 26)
                .background(Capsule().fill(pill))
                .opacity(enabled ? 1 : 0.4)
                .contentShape(Capsule())
                .onHover { hovered = $0 }
                .animation(.easeOut(duration: 0.12), value: hovered)
        }
    }
}
