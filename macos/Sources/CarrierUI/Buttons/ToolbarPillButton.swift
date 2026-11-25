import CarrierCore
import SwiftUI

/// A word with its icon for a glass pill of the toolbar: 12 pt type, the pill's height, a quiet fill under the pointer, the count of what is
/// applied as a small accent capsule, and the icon turning while `spinning`. The caller puts the glass on the pill (`.glassEffect(.regular,
/// in: .capsule)`, on the button or on the row of buttons that share one) and hides the toolbar's own (`sharedBackgroundVisibility(.hidden)`):
/// the toolbar's glass is taller than these labels need and cannot be made smaller.
public struct ToolbarPillButton: View {
    public static let height: CGFloat = 28

    let title: String
    var icon: AppIcon?
    /// An image in the place of the symbol (the GitHub mark).
    var mark: Image?
    var badge = 0
    var spinning = false
    /// The icon's own colour (Stop's red); the words keep the text colour.
    var iconTint: Color?
    let action: () -> Void

    public init(
        title: String,
        icon: AppIcon? = nil,
        mark: Image? = nil,
        badge: Int = 0,
        spinning: Bool = false,
        iconTint: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.mark = mark
        self.badge = badge
        self.spinning = spinning
        self.iconTint = iconTint
        self.action = action
    }
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled

    public var body: some View {
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
                        .accessibilityLabel(Copy.pieceFiltersApplied(count: badge))
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

/// Accent glass capsule pill button at `ToolbarPillButton.height` (28 pt), shared between headers and primary empty-state CTAs.
public struct AccentGlassPillButton: View {
    @Environment(\.pieceTheme) private var theme
    let title: String
    var icon: AppIcon? = nil
    let action: () -> Void

    public init(title: String, icon: AppIcon? = nil, action: @escaping () -> Void) { self.title = title; self.icon = icon; self.action = action }
    @Environment(\.isEnabled) private var enabled

    public var body: some View {
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
        .glassEffect(.regular.tint(theme.accentGlass).interactive(enabled), in: .capsule)
        .opacity(enabled ? 1 : 0.45)
    }
}

/// Compact icon-only button sized to `ToolbarPillButton.height` (28 pt) for grouped `.glassEffect(.regular, in: .capsule)` toolbars.
public struct ToolbarGlassIconButton: View {
    let icon: AppIcon
    /// What the button opened is open: a fill of the accent under the icon, so the state is not the color of the icon alone.
    var active = false
    let name: String
    let action: () -> Void

    public init(
        icon: AppIcon,
        active: Bool = false,
        name: String,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.active = active
        self.name = name
        self.action = action
    }
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled

    public var body: some View {
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
public struct ToolbarSearchField: View {
    @Binding var query: String?
    let placeholder: String
    let focused: FocusState<Bool>.Binding
    var onDismiss: (() -> Void)? = nil

    public init(
        query: Binding<String?>,
        placeholder: String,
        focused: FocusState<Bool>.Binding,
        onDismiss: (() -> Void)? = nil
    ) {
        self._query = query
        self.placeholder = placeholder
        self.focused = focused
        self.onDismiss = onDismiss
    }

    public var body: some View {
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
                .help(Copy.pieceCloseSearchHelp())
                .accessibilityLabel(Copy.pieceCloseSearch())
            }
            .padding(.horizontal, Tokens.Space.s12)
            .frame(width: 220, height: ToolbarPillButton.height)
        } else {
            ToolbarPillButton(title: Copy.pieceSearch(), icon: .search) {
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
