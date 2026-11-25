import CarrierCore
import SwiftUI

/// A sidebar section ([glossary](../../docs/glossary.md)): an icon of 15 points, a title and its actions, and under them whatever the
/// section shows of itself (Carrier's slots). No fill at rest, a faint grey on hover and a light neutral grey when selected, drawn here
/// and not by the list, so it covers this row and never what unfolds under it. A click anywhere on it, but on its actions, runs `action`.
/// `actions` are what the row says (a count, a state) and are always there; `hoverActions` are its buttons, which fade in while the pointer
/// is over the row and stay while `keepActions` (a menu they opened is open, a search they started is on), left of `actions`.
struct SidebarSectionRow<Actions: View, HoverActions: View, Below: View>: View {
    @Environment(\.pieceTheme) private var theme
    let title: String
    let icon: AppIcon
    let selected: Bool
    var keepActions = false
    let action: () -> Void
    @ViewBuilder let actions: Actions
    @ViewBuilder let hoverActions: HoverActions
    @ViewBuilder let below: Below
    @State private var hovered = false
    @Environment(\.colorScheme) private var scheme

    init(
        title: String, icon: AppIcon, selected: Bool, keepActions: Bool = false, action: @escaping () -> Void,
        @ViewBuilder actions: () -> Actions = { EmptyView() }, @ViewBuilder hoverActions: () -> HoverActions = { EmptyView() },
        @ViewBuilder below: () -> Below = { EmptyView() }
    ) {
        self.title = title
        self.icon = icon
        self.selected = selected
        self.keepActions = keepActions
        self.action = action
        self.actions = actions()
        self.hoverActions = hoverActions()
        self.below = below()
    }

    var body: some View {
        // the system's selection colour at 45% when selected, a faint grey (5%, 7% dark) when hovered
        let dark = scheme == .dark
        VStack(alignment: .leading, spacing: Tokens.Space.s8) {
            HStack(spacing: Tokens.Space.s8) {
                // the one control a keyboard reaches: Tab (with Full Keyboard Access) and Space run `action`; a click anywhere on the
                // row, but on its actions, still does through the tap below
                Button(action: action) {
                    HStack(spacing: Tokens.Space.s8) {
                        Glyph(icon, size: 18)
                            .foregroundStyle(selected ? .primary : .secondary)
                        Text(title).sidebarFont(.section)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityAddTraits(selected ? .isSelected : [])
                // the buttons take their room even while hidden, so the row does not move when the pointer comes in
                let shown = hovered || keepActions
                HStack(spacing: Tokens.Space.none) { hoverActions }
                    .opacity(shown ? 1 : 0).allowsHitTesting(shown)
                    .animation(.easeOut(duration: 0.15), value: shown)
                actions
            }
            .frame(minHeight: 24)
            below
        }
        .padding(.horizontal, SidebarMetrics.inset).padding(.vertical, SidebarMetrics.sectionPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.control).fill(selected ? theme.selectedRow(dark: dark) : Color.primary.opacity(hovered ? (dark ? 0.07 : 0.05) : 0)))
        .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.control))
        .onTapGesture(perform: action)
        .onHover { hovered = $0 }
        .accessibilityElement(children: .contain)
    }
}
