import CarrierCore
import SwiftUI

/// A text field of a settings form, drawn as the capsule buttons are (the same quiet fill) with the theme's accent as its ring
/// while it has the focus. Put it on a `TextField`; a click anywhere in the box, padding included, puts the cursor in it.
private struct SettingsFieldModifier: ViewModifier {
    let width: CGFloat?
    let icon: AppIcon?
    @Environment(\.settingsInvalid) private var invalid
    /// The caller's own focus state, when it needs to know about the focus (to save as the person leaves the field); else the field keeps its own.
    let external: FocusState<Bool>.Binding?
    @FocusState private var own: Bool

    private var focus: FocusState<Bool>.Binding { external ?? $own }
    private var focused: Bool { focus.wrappedValue }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        HStack(spacing: 7) {
            if let icon { Glyph(icon, size: 12).foregroundStyle(.secondary) }
            // a form makes a field's title its label, at the left of it, and aligns its text to the trailing edge: here the title is the prompt
            content.textFieldStyle(.plain).labelsHidden().multilineTextAlignment(.leading).focused(focus).focusEffectDisabled()
            if invalid { Glyph(.warningFilled, size: 11).foregroundStyle(.orange).accessibilityHidden(true) }
        }
            .padding(.horizontal, 10).padding(.vertical, 6)
            // a fixed width, or the whole width it is given
            .frame(minWidth: width, maxWidth: width ?? .infinity)
            // a fill only while idle: a half-point hairline over a translucent fill drew uneven edges
            .background(shape.fill(Color.primary.opacity(focused ? 0.09 : 0.07)))
            .overlay { if invalid { shape.strokeBorder(Color.orange, lineWidth: 1.5) } else if focused { shape.strokeBorder(.tint, lineWidth: 1.5) } }
            .contentShape(shape)
            .onTapGesture { focus.wrappedValue = true }
            .animation(.easeOut(duration: 0.12), value: focused)
    }
}

extension View {
    /// `icon` is drawn inside the box before the text (a magnifying glass for a search).
    /// Inside a row with a `problem` the ring is orange and a warning mark sits in the box, the same size as without them: nothing moves.
    func settingsField(width: CGFloat? = nil, icon: AppIcon? = nil, focused: FocusState<Bool>.Binding? = nil) -> some View {
        modifier(SettingsFieldModifier(width: width, icon: icon, external: focused))
    }
}
