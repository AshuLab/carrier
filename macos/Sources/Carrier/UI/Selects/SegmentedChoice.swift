import CarrierCore
import SwiftUI

/// A few choices that exclude each other, in one quiet capsule: the chosen one is a piece tinted with the person's accent (`.tint`: the one they picked,
/// else the theme's, else the Mac's) that slides to the next choice. The choices are as wide as the widest one, so the piece does not change size as it moves,
/// and every one has the same type and padding whether chosen or not (Usage's metric and range).
struct SegmentedChoice<Value: Hashable>: View {
    let options: [(value: Value, title: String, icon: AppIcon?)]
    @Binding var selection: Value
    @Namespace private var thumb

    var body: some View {
        EqualWidthRow {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Segment(title: option.title, icon: option.icon, on: selection == option.value, thumb: thumb) { selection = option.value }
            }
        }
        .padding(Tokens.Space.s2)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
        .animation(.smooth(duration: 0.25), value: selection)
        .accessibilityElement(children: .contain)
    }

    private struct Segment: View {
        let title: String
        let icon: AppIcon?
        let on: Bool
        let thumb: Namespace.ID
        let action: () -> Void
        @State private var hovered = false
        @Environment(\.colorScheme) private var scheme
        @Environment(\.pieceTheme) private var theme

        var body: some View {
            Button(action: action) {
                HStack(spacing: Tokens.Space.s5) {
                    if let icon { Glyph(icon, size: 11) }
                    Text(title).scaledFont(12, weight: .medium)
                }
                // the chosen one reads in the accent, a little lifted in the dark and deepened in the light so it keeps its contrast on the tinted piece
                .foregroundStyle(on ? theme.accentInk(scheme) : hovered ? Color.primary : Color.secondary)
                .padding(.horizontal, Tokens.Space.s14).padding(.vertical, Tokens.Space.s4)
                // the whole of the slot the row gives it, so the tinted piece (its background) is as wide as the widest choice and not as the words
                .frame(maxWidth: .infinity)
                .background {
                    if on {
                        Capsule().fill(.tint.opacity(0.24))
                            .overlay(Capsule().strokeBorder(.tint.opacity(0.45), lineWidth: 1))
                            .matchedGeometryEffect(id: "thumb", in: thumb)
                    } else if hovered {
                        Capsule().fill(Color.primary.opacity(0.07))
                    }
                }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain).onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.12), value: hovered)
            .accessibilityAddTraits(on ? .isSelected : [])
        }
    }
}
