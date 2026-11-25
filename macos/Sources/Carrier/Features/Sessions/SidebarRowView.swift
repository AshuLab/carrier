import CarrierCore
import SwiftUI

extension View {
    /// An epic or a session under a section: the fill is drawn here, like the section rows', so it keeps the list's margin and does not
    /// reach the edges as the list's own highlight does.
    func selectableSidebarRow(selected: Bool, action: @escaping () -> Void) -> some View {
        modifier(SelectableSidebarRow(selected: selected, action: action))
    }

}

struct SidebarRowView: View {
    let row: SidebarRow
    @AppStorage(Preference.appearanceDensity) private var density
    private static let titleLine: CGFloat = 17, detailLine: CGFloat = 15

    private var detailColor: Color {
        guard row.state == .needsYou else { return .secondary }
        return row.attention == .error ? .red : SessionRowView.attention
    }

    var body: some View {
        HStack(spacing: SidebarMetrics.inset) {
            ProjectIcon(repo: row.repo, name: row.name, colorKey: projectColorKey(row.repo), working: row.state == .running)
            VStack(alignment: .leading, spacing: SidebarMetrics.lineGap) {
                // two lines before the ellipsis: a title is a sentence, and the number no longer takes room from it
                Text(row.title ?? row.name).font(SidebarMetrics.item).lineLimit(2)
                Text("#\(row.issue) · \(row.detail)").font(SidebarMetrics.detail).monospacedDigit().foregroundStyle(detailColor)
                    .lineLimit(1).truncationMode(.tail).frame(height: Self.detailLine, alignment: .leading)
            }
            Spacer(minLength: 4)
            Text(row.age).font(SidebarMetrics.detail.monospacedDigit()).foregroundStyle(.tertiary).lineLimit(1)
                .frame(height: Self.titleLine).frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, density.rowPadding).padding(.vertical, density.rowPadding)
        .hoverCard { EpicCardView(card: row.card) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(([row.title ?? row.name, row.state.label, row.detail] + (row.age.isEmpty ? [] : [row.age])).joined(separator: ", "))
    }
}

private struct SelectableSidebarRow: ViewModifier {
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let dark = scheme == .dark
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.control).fill(selected ? Color.selectedRow(dark: dark) : Color.primary.opacity(hovered ? (dark ? 0.07 : 0.05) : 0)))
            .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.control))
            .environment(\.rowActive, selected || hovered)
            .environment(\.rowState, selected ? .selected : hovered ? .hovered : .resting)
            .onTapGesture(perform: action)
            .onHover { hovered = $0 }
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(.default, action)
    }
}
