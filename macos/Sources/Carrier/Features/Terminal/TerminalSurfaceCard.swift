import CarrierCore
import CarrierUI
import SwiftUI

/// One pane's surface as a rounded card that floats in its area (the area gives the margin and the gap between panes): the same surface as
/// the message box (`chatSurface`, so Settings > Chat > Surfaces applies) when the terminal's surface is translucent, and the theme's own
/// color under a fine edge when it is opaque.
struct TerminalSurfaceCard: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let profile: TerminalAppearanceProfile

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Tokens.Radius.panel, style: .continuous) }

    func body(content: Content) -> some View {
        content
            .clipShape(shape)
            .background {
                if profile.isSurfaceTranslucent {
                    Color.clear.chatSurface(flat: scheme == .dark ? Color.black.opacity(0.22) : Color.primary.opacity(0.07), in: shape)
                } else {
                    shape.fill(Color(profile.background))
                }
            }
            .overlay {
                if profile.isSurfaceTranslucent == false {
                    shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
            }
    }
}

extension View {
    func terminalSurfaceCard(_ profile: TerminalAppearanceProfile) -> some View {
        modifier(TerminalSurfaceCard(profile: profile))
    }
}
