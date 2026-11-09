import CarrierCore
import SwiftUI

/// What every sidebar row is laid out with. The scroll area and the foot keep `edge` on both sides, so nothing inside has a side margin
/// of its own; a row draws its fill edge to edge of that and keeps its content `inset` inside the fill. The type has four levels, one
/// for each job: a section (Home, Sessions, Carrier), a group's title, an item's title (a session, an epic) and its detail.
enum SidebarMetrics {
    static let edge: CGFloat = 8
    static let inset: CGFloat = 12
    static var section: Font { Font.scaled(16, weight: .medium) }
    static var group: Font { Font.scaled(12, weight: .semibold) }
    static var item: Font { Font.scaled(14) }
    static var detail: Font { Font.scaled(12) }
    /// Between rows: each one carries its own vertical padding.
    static let rowGap: CGFloat = 2
    /// The vertical padding of a section's row and of an item's row, and between an item's lines.
    static let sectionPadding: CGFloat = 8
    static let itemPadding: CGFloat = 7
    static let lineGap: CGFloat = 3
    /// Above a group's title, so it reads where a group begins; under it the first row is closer.
    static let groupTop: CGFloat = 10
}

/// The sidebar: the Home row, Sessions, then Carrier with the epics in groups under it, in a scroll area; Archive and Settings are fixed
/// in the foot. The rows draw their own fill, selected or hovered, so what is under a section is plain rows and not a `List`.
struct SidebarView: View {
    let snapshot: PanelSnapshot?
    let state: ConnectionState?
    let sessions: Sessions
    @Binding var selection: Selection
    /// Which of Sessions, Carrier and Archive is unfolded, nil when all are folded.
    @Binding var open: OpenSection?
    @Binding var groupBy: GroupBy
    @Binding var sessionSort: SessionSort
    @Binding var collapse: SidebarCollapse
    /// The last ⌘F, for the open section to show its search.
    let searchRequest: SearchRequest?
    /// Choosing a session from the Archive list.
    let chooseArchived: (String) -> Void
    /// Settings is a sheet over the window, not a page: the row opens it and is never the selected one.
    let openSettings: () -> Void
    /// The + of a workspace's header: a new session in that folder.
    let newSessionIn: (String) -> Void
    /// Carrier's search: not remembered between launches.
    @State private var searching = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        let epicCount = snapshot.map { sidebarGroups($0, by: groupBy).reduce(0) { $0 + $1.count } } ?? 0
        ScrollView {
            LazyVStack(alignment: .leading, spacing: SidebarMetrics.rowGap) {
                SidebarSectionRow(title: "Home", icon: "house", selected: selection == .home, action: { selection = .home }).help("Home (⌘1)")
                SessionsRows(
                    sessions: sessions, sort: $sessionSort, selection: $selection, selected: selection == .sessions,
                    select: { selection = .sessions }, open: Binding(get: { open == .sessions }, set: { open = $0 ? .sessions : nil }),
                    searchRequest: searchRequest, newSession: { selection = .newSession }, newSessionIn: newSessionIn
                )
                CarrierRow(
                    state: state, selected: selection == .carrier, unfolded: open == .carrier, hasEpics: epicCount > 0,
                    select: { selection = .carrier }, groupBy: $groupBy, searching: $searching
                )
                if let snapshot, open == .carrier {
                    if searching {
                        SidebarSearchField(placeholder: "Search epics", text: $query, focus: $searchFocused, close: { searching = false })
                    }
                    let queried = query.trimmingCharacters(in: .whitespaces).isEmpty == false
                    let groups = sidebarGroups(snapshot, by: groupBy, query: query)
                    switch SidebarListState(shown: groups.reduce(0) { $0 + $1.count }, of: epicCount, query: query) {
                    case .empty: SidebarEmptyBlock(state: .noEpics)
                    case .noMatch(let typed): SidebarNoResults(query: typed, clear: { query = "" })
                    case .rows: EmptyView()
                    }
                    ForEach(groups.indices, id: \.self) { index in
                        let group = groups[index]
                        // while a query is typed every group is open, so there is nothing to toggle
                        let expanded = queried || !collapse.isCollapsed(group, by: groupBy, query: query)
                        Button {
                            if queried == false { collapse.toggle(group, by: groupBy) }
                        } label: {
                            HStack {
                                Text(group.title)
                                Spacer(minLength: 0)
                                Text("\(group.count)").monospacedDigit()
                                Image(systemName: "chevron.right").imageScale(.small).rotationEffect(.degrees(expanded ? 90 : 0))
                                    .opacity(queried ? 0 : 1)
                            }
                            .font(SidebarMetrics.group).foregroundStyle(.secondary)
                            .frame(height: 22).padding(.horizontal, SidebarMetrics.inset).padding(.top, SidebarMetrics.groupTop)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityHint(expanded ? "Folds the group" : "Unfolds the group")
                        if expanded {
                            ForEach(group.rows, id: \.selection) { row in
                                SidebarRowView(row: row).selectableSidebarRow(selected: selection == row.selection) { selection = row.selection }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, SidebarMetrics.edge).padding(.vertical, 8)
        }
        .onChange(of: searching) { if searching { searchFocused = true } else { query = "" } }
        .onChange(of: searchRequest) {
            if searchRequest?.section == .carrier && epicCount > 0 && open == .carrier {
                searching = true
                searchFocused = true
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 268, max: 320)
        .safeAreaBar(edge: .bottom, spacing: 0) {
            // Archive above the divider and Settings alone under it; both stay while the list above scrolls, over the system's scroll pocket
            VStack(spacing: 0) {
                ArchiveSection(
                    sessions: sessions, selection: $selection, open: open == .archive, choose: chooseArchived, searchRequest: searchRequest
                )
                .padding(.horizontal, SidebarMetrics.edge).padding(.vertical, 8)
                Divider()
                SidebarSectionRow(title: "Settings", icon: "gearshape", selected: false, action: openSettings)
                    .padding(.horizontal, SidebarMetrics.edge).padding(.vertical, 8)
            }
        }
    }
}

/// The Carrier section: its name and the engine's state as a pill with the search and the grouping menu, and its slots as bars under
/// them, nothing else; the epics follow it. Choosing it shows the Carrier home. Hovering it shows when the next check
/// is, the uptime and the rate limit.
private struct CarrierRow: View {
    @ObservedObject private var start = StartController.shared
    let state: ConnectionState?
    let selected: Bool
    /// Folded, the row is its state and slots; unfolded, it also has the search and the grouping menu, and the epics follow.
    let unfolded: Bool
    /// Without epics there is nothing to search, so the magnifier is dimmed.
    let hasEpics: Bool
    let select: () -> Void
    @Binding var groupBy: GroupBy
    /// Whether the search field is open under the row; the list owns the field.
    @Binding var searching: Bool
    @State private var groupMenu = false

    var body: some View {
        let card = carrierCardState(state, lastTotal: SidebarStore().slotsTotal)
        let snapshot: PanelSnapshot? = if case .running(let snapshot)? = state { snapshot } else { nil }
        // the hover: running says when the next check is, uptime and rate limit; an incompatible engine says why
        let detail: String? = if let snapshot { Self.hover(snapshot) } else if case .incompatible(let update)? = state { update ?? state?.menuLine } else { nil }
        SidebarSectionRow(title: "Carrier", icon: "paperplane", selected: selected, action: select, actions: {
            Text(card.title)
                .font(SidebarMetrics.detail.weight(.semibold))
                .foregroundStyle(Self.tint(card.kind))
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Capsule().fill(Self.tint(card.kind).opacity(0.28)))
            // the epics exist only while Carrier answers, so there is nothing to search or group before
            if snapshot != nil && unfolded {
                IconButton(
                    icon: "magnifyingglass", name: searching ? "Close epic search" : "Search epics", enabled: hasEpics, why: "No epics to search",
                    shortcut: "⌘F", pressed: searching
                ) {
                    searching.toggle()
                }
                IconButton(icon: "ellipsis", name: "Group epics by") { groupMenu = true }
                    .popover(isPresented: $groupMenu, arrowEdge: .trailing) {
                        ChoiceMenu(
                            title: "Group by", options: GroupBy.allCases.map { ($0.title, $0) }, selection: $groupBy,
                            close: { groupMenu = false }
                        )
                    }
            }
        }, below: {
            if state == .stopped, let notice = engineNotConfiguredNotice(configExists: start.configExists) {
                Text(notice).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if let slots = card.slots {
                HStack(spacing: 8) {
                    SegmentedProgress(done: slots.busy, total: slots.total, tint: Self.tint(card.kind))
                    Text("\(slots.busy)/\(slots.total)").font(.scaled(11).monospacedDigit()).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(slots.busy) of \(slots.total) slots busy")
            }
        })
        .help(([detail, "Carrier (⌘3)"].compactMap { $0 }).joined(separator: "\n"))
        // remembered so a stopped engine, even after a relaunch, still draws its slots
        .onChange(of: snapshot?.slots.total, initial: true) { if let total = snapshot?.slots.total { SidebarStore().slotsTotal = total } }
    }

    private static func tint(_ kind: CarrierCardState.Kind) -> Color {
        switch kind {
        case .running: .green
        case .paused, .problem: .orange
        case .stopped, .connecting: .gray
        }
    }

    private static func hover(_ snapshot: PanelSnapshot) -> String {
        let box = carrierBox(snapshot)
        return ([box.uptime] + box.rows.map { "\($0.label): \($0.value)" }).joined(separator: " · ")
    }
}

/// A 22-point plain button with an accessible name and a tooltip; `why` is the tooltip and the hint while it is disabled. In a list
/// row it runs its action and does not select the row.
struct IconButton: View {
    let icon: String
    let name: String
    var enabled = true
    var why: String?
    /// Shown after the name in the tooltip.
    var shortcut: String?
    /// Drawn while what the button opened is open.
    var pressed = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon).frame(width: 22, height: 22).contentShape(Rectangle())
                .background(RoundedRectangle(cornerRadius: 5).fill(pressed ? Color.primary.opacity(0.15) : .clear))
        }
        .buttonStyle(.plain)
        .disabled(enabled == false)
        .help(enabled ? name + (shortcut.map { " (\($0))" } ?? "") : why ?? name)
        .accessibilityLabel(name)
        .accessibilityHint(enabled ? "" : why ?? "")
        .accessibilityAddTraits(pressed ? .isSelected : [])
    }
}

extension GroupBy {
    var title: String { self == .status ? "Status" : "Repository" }
}

/// A popover of choices, one ticked; choosing one closes it.
struct ChoiceMenu<Value: Hashable>: View {
    let title: String
    let options: [(title: String, value: Value)]
    @Binding var selection: Value
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.bottom, 2)
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                Button {
                    selection = option.value
                    close()
                } label: {
                    HStack {
                        Text(option.title)
                        Spacer(minLength: 0)
                        if selection == option.value { Image(systemName: "checkmark") }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option.value ? .isSelected : [])
            }
        }
        .padding(8)
        .frame(width: 160)
    }
}

extension View {
    /// An epic or a session under a section: the fill is drawn here, like the section rows', so it keeps the list's margin and does not
    /// reach the edges as the list's own highlight does.
    func selectableSidebarRow(selected: Bool, action: @escaping () -> Void) -> some View {
        modifier(SelectableSidebarRow(selected: selected, action: action))
    }

}

/// A sidebar section ([glossary](../../docs/glossary.md)): an icon of 15 points, a title and its actions, and under them whatever the
/// section shows of itself (Carrier's slots). No fill at rest, a faint grey on hover and a light neutral grey when selected, drawn here
/// and not by the list, so it covers this row and never what unfolds under it. A click anywhere on it, but on its actions, runs `action`.
struct SidebarSectionRow<Actions: View, Below: View>: View {
    let title: String
    let icon: String
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let actions: Actions
    @ViewBuilder let below: Below
    @State private var hovered = false
    @Environment(\.colorScheme) private var scheme

    init(
        title: String, icon: String, selected: Bool, action: @escaping () -> Void, @ViewBuilder actions: () -> Actions = { EmptyView() },
        @ViewBuilder below: () -> Below = { EmptyView() }
    ) {
        self.title = title
        self.icon = icon
        self.selected = selected
        self.action = action
        self.actions = actions()
        self.below = below()
    }

    var body: some View {
        // the system's selection colour at 45% when selected, a faint grey (5%, 7% dark) when hovered
        let dark = scheme == .dark
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                // the one control a keyboard reaches: Tab (with Full Keyboard Access) and Space run `action`; a click anywhere on the
                // row, but on its actions, still does through the tap below
                Button(action: action) {
                    HStack(spacing: 8) {
                        Image(systemName: icon).resizable().scaledToFit().frame(width: 18, height: 18)
                            .foregroundStyle(selected ? .primary : .secondary)
                        Text(title).font(SidebarMetrics.section)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityAddTraits(selected ? .isSelected : [])
                actions
            }
            .frame(minHeight: 24)
            below
        }
        .padding(.horizontal, SidebarMetrics.inset).padding(.vertical, SidebarMetrics.sectionPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.45) : Color.primary.opacity(hovered ? (dark ? 0.07 : 0.05) : 0)))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture(perform: action)
        .onHover { hovered = $0 }
        .accessibilityElement(children: .contain)
    }
}

struct SidebarRowView: View {
    let row: SidebarRow
    private static let titleLine: CGFloat = 17, detailLine: CGFloat = 15

    /// What the project's icon wears for the epic's state: a halo while it runs, a mark on its corner when there is something to say.
    private var mark: ProjectIcon.Mark? {
        switch row.state {
        case .needsYou: .init(text: "!", color: (row.attention ?? .input).color)
        case .ready: .init(text: "✓", color: .blue)
        case .done: .init(text: "✓", color: .green)
        case .cancelled: .init(text: "✕", color: .gray)
        case .running, .waiting: nil
        }
    }

    private var detailColor: Color {
        guard row.state == .needsYou else { return .secondary }
        return row.attention == .error ? .red : SessionRowView.attention
    }

    var body: some View {
        HStack(spacing: SidebarMetrics.inset) {
            ProjectIcon(name: row.name, colorKey: projectColorKey(row.repo), halo: row.state == .running, mark: mark)
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
        .padding(.horizontal, SidebarMetrics.inset).padding(.vertical, SidebarMetrics.itemPadding)
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
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.45) : Color.primary.opacity(hovered ? (dark ? 0.07 : 0.05) : 0)))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onTapGesture(perform: action)
            .onHover { hovered = $0 }
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(.default, action)
    }
}
