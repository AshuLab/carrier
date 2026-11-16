import CarrierCore
import SwiftUI

/// What a surface of the conversation is made of, by Settings > Chat > Surfaces: glass as the system draws it, or flat, the window's own
/// color under a quiet fill (`flat`) and a fine edge. The base is solid so what scrolls under the box or a card is not seen through it,
/// as the glass blurs it. A new card, bubble or box of the chat wears this and does not call `glassEffect` itself.
private struct ChatSurfaceModifier<S: InsettableShape>: ViewModifier {
    @AppStorage(AppPreferences.chatSurfaceKey) private var surface = AppPreferences.defaultChatSurface
    let glass: Glass
    let flat: Color
    let shape: S

    func body(content: Content) -> some View {
        switch surface {
        case .glass:
            content.glassEffect(glass, in: shape)
        case .flat:
            content
                .background(shape.fill(Color.themeWindow))
                .background(shape.fill(flat))
                .overlay(shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
        }
    }
}

extension View {
    /// `glass` is what the surface is as glass; `flat` is the fill it has over the window's color as flat.
    func chatSurface<S: InsettableShape>(_ glass: Glass = .regular, flat: Color = Color.primary.opacity(0.07), in shape: S) -> some View {
        modifier(ChatSurfaceModifier(glass: glass, flat: flat, shape: shape))
    }
}
