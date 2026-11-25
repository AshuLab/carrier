import CarrierCore
import SwiftUI

/// A word with its icon for a glass pill of the toolbar: 12 pt type, the pill's height, a quiet fill under the pointer, the count of what is
/// applied as a small accent capsule, and the icon turning while `spinning`. The caller puts the glass on the pill (`.glassEffect(.regular,
/// in: .capsule)`, on the button or on the row of buttons that share one) and hides the toolbar's own (`sharedBackgroundVisibility(.hidden)`):
/// the toolbar's glass is taller than these labels need and cannot be made smaller.
struct ToolbarPillButton: View {
    static let height: CGFloat = 28

    let title: String
    var icon: AppIcon?
    /// An image in the place of the symbol (the GitHub mark).
    var mark: Image?
    var badge = 0
    var spinning = false
    /// The icon's own colour (Stop's red); the words keep the text colour.
    var iconTint: Color?
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: Tokens.Space.s5) {
                if let mark {
                    mark.renderingMode(.template).resizable().scaledToFit().frame(width: 12, height: 12)
                } else if let icon {
                    Glyph(icon, size: 12).foregroundStyle(iconTint ?? .primary).glyphSpinning(spinning)
                }
                Text(title).scaledFont(12, weight: .medium)
                if badge > 0 {
                    Text("\(badge)").scaledFont(10, weight: .semibold).monospacedDigit().foregroundStyle(.white)
                        .padding(.horizontal, Tokens.Space.s6).padding(.vertical, Tokens.Space.s1).background(Capsule().fill(.tint))
                        .accessibilityLabel("\(badge) filters applied")
                }
            }
            .padding(.horizontal, Tokens.Space.s12).frame(height: Self.height)
            .background(Capsule().fill(Color.primary.opacity(hovered && enabled ? 0.1 : 0)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain).onHover { hovered = $0 }
        .opacity(enabled ? 1 : 0.5)
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

extension Color {
    /// The accent a main action is tinted with on glass (the New session pill, the message box's send button): darkened, so white reads on it and it is not as loud as the system's prominent button.
    static var accentGlass: Color { themeAccent.mix(with: .black, by: 0.4) }

    /// The fill of the selected row of a sidebar list. On dark the accent is deepened, so the white words keep their contrast and it is not as
    /// loud as the accent itself; on light the accent at 45 % behind the dark words is already quiet.
    static func selectedRow(dark: Bool) -> Color { dark ? themeAccent.mix(with: .black, by: 0.5).opacity(0.85) : themeAccent.opacity(0.45) }
}

/// Accent glass capsule pill button at `ToolbarPillButton.height` (28 pt), shared between headers and primary empty-state CTAs.
struct AccentGlassPillButton: View {
    let title: String
    var icon: AppIcon? = nil
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: Tokens.Space.s5) {
                if let icon { Glyph(icon, size: 11) }
                Text(title).scaledFont(12, weight: .medium)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Tokens.Space.s14)
            .frame(height: ToolbarPillButton.height)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // off: dimmed, and the glass does not answer the pointer, as the other toolbar pills do
        .glassEffect(.regular.tint(Color.accentGlass).interactive(enabled), in: .capsule)
        .opacity(enabled ? 1 : 0.45)
    }
}

/// Compact icon-only button sized to `ToolbarPillButton.height` (28 pt) for grouped `.glassEffect(.regular, in: .capsule)` toolbars.
struct ToolbarGlassIconButton: View {
    let icon: AppIcon
    /// What the button opened is open: a fill of the accent under the icon, so the state is not the color of the icon alone.
    var active = false
    let name: String
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Glyph(icon, size: 12)
                .foregroundStyle(active ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .padding(.horizontal, Tokens.Space.s10)
                .frame(height: ToolbarPillButton.height)
                .background(Capsule().fill(active ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(Color.primary.opacity(hovered && enabled ? 0.1 : 0))))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .opacity(enabled ? 1 : 0.5)
        .animation(.easeOut(duration: 0.12), value: hovered)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// Shared toolbar Search toggle that expands inline into a 220 pt glass-pill search field.
struct ToolbarSearchField: View {
    @Binding var query: String?
    let placeholder: String
    let focused: FocusState<Bool>.Binding
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        if query != nil {
            HStack(spacing: Tokens.Space.s6) {
                Glyph(.search, size: 11)
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)
                TextField(placeholder, text: Binding(get: { query ?? "" }, set: { query = $0 }))
                    .textFieldStyle(.plain)
                    .scaledFont(12)
                    .focused(focused)
                    .onKeyPress(.escape) {
                        dismiss()
                        return .handled
                    }
                Button(action: dismiss) {
                    Glyph(.closeCircleFilled, size: 11)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close search (Esc)")
                .accessibilityLabel("Close search")
            }
            .padding(.horizontal, Tokens.Space.s12)
            .frame(width: 220, height: ToolbarPillButton.height)
        } else {
            ToolbarPillButton(title: "Search", icon: .search) {
                query = ""
                focused.wrappedValue = true
            }
        }
    }

    private func dismiss() {
        query = nil
        onDismiss?()
    }
}
