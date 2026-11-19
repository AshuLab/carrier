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
    /// The vertical padding of a section's row, and between an item's lines; an item's row takes its padding from the density, on all four
    /// sides when it has a project icon (the tile is as far from the left edge of its fill as from the top and bottom).
    static let sectionPadding: CGFloat = 8
    static let lineGap: CGFloat = 3
    /// Above a group's title, so it reads where a group begins; under it the first row is closer.
    static let groupTop: CGFloat = 10
}

/// The sidebar: Home, Sessions, Terminal and Carrier stacked in that order, then Settings and Usage. The open section takes the room that is
/// left and scrolls its own list; the sections above it are rows at the top and the ones under it rows at the foot (Archive closes Sessions' panel).
/// The rows draw their own fill, selected or hovered, so what is under a section is plain rows and not a `List`.
struct SidebarView: View {
    private let timeChanges = TimeFormatChanges()
    let snapshot: PanelSnapshot?
    let state: ConnectionState?
    let sessions: Sessions
    let terminalStore: CarrierTerminalStore
    @Binding var selection: Selection
    /// Which of Sessions, Terminal, Carrier and Archive is unfolded, nil when all are folded.
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
    let newTerminal: () -> Void
    let closeTerminal: (UUID) -> Void
    /// Carrier's search: not remembered between launches.
    @State private var searching = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    /// Whether the open section's list has moved under its row: the row then has a fill and a faint shadow.
    @State private var scrolled = false
    /// The width the person left the sidebar at, read once: the column opens at it (`SidebarWidthKeeper`), and what they drag it to is stored for the next launch.
    @State private var openWidth = SidebarStore().width
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sidebarEpicCount: Int { snapshot.map { sidebarGroups($0, by: groupBy).reduce(0) { $0 + $1.count } } ?? 0 }

    private func carrierRow(epicCount: Int) -> some View {
        CarrierRow(
            state: state, selected: selection == .carrier, unfolded: open == .carrier, hasEpics: epicCount > 0,
            select: { selection = .carrier }, groupBy: $groupBy, searching: $searching
        )
    }

    /// The sections in the order they are stacked, Home before and Settings and Usage after. The open one takes all the room that is left, the
    /// ones above it fold to their row at the top and the ones under it to their row at the foot, so Terminal is one more section as Sessions is.
    private enum Slot: Int, CaseIterable { case sessions, terminal, carrier }

    private var openSlot: Slot? {
        switch open {
        case .sessions, .archive: .sessions
        case .terminal: .terminal
        case .carrier: .carrier
        case nil: nil
        }
    }

    /// With none open, Sessions and Terminal are at the top and Carrier alone at the foot.
    private var above: [Slot] {
        guard let openSlot else { return [.sessions, .terminal] }
        return Slot.allCases.filter { $0.rawValue < openSlot.rawValue }
    }

    private var below: [Slot] {
        guard let openSlot else { return [.carrier] }
        return Slot.allCases.filter { $0.rawValue > openSlot.rawValue }
    }

    @ViewBuilder private func slot(_ slot: Slot, epicCount: Int, pinned: Bool = false) -> some View {
        switch slot {
        case .sessions:
            SessionsRows(
                sessions: sessions, sort: $sessionSort, selection: $selection, selected: selection == .sessions,
                select: { selection = .sessions },
                // Archive is a panel under the list, not a replacement for it: the sessions stay unfolded while it is open
                open: Binding(get: { open == .sessions || open == .archive }, set: { open = $0 ? .sessions : nil }), pinHeader: pinned,
                searchRequest: searchRequest, newSession: { selection = .newSession }, newSessionIn: newSessionIn
            )
        case .terminal:
            TerminalRows(
                store: terminalStore,
                selection: $selection,
                selected: selection == .terminals,
                select: { selection = .terminals },
                open: Binding(get: { open == .terminal }, set: { open = $0 ? .terminal : nil }), pinHeader: pinned,
                searchRequest: searchRequest,
                newTerminal: newTerminal,
                closeTerminal: closeTerminal
            )
        case .carrier:
            if pinned {
                Section { epicsList(epicCount: epicCount) } header: { carrierRow(epicCount: epicCount).pinnedSectionHeader() }
            } else {
                carrierRow(epicCount: epicCount)
                epicsList(epicCount: epicCount)
            }
        }
    }

    /// Carrier's epics, under its row while Carrier is the open section.
    @ViewBuilder private func epicsList(epicCount: Int) -> some View {
            if let snapshot, open == .carrier {
                LazyVStack(alignment: .leading, spacing: SidebarMetrics.rowGap) {
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
                                Glyph(.chevronRight, size: 11).rotationEffect(.degrees(expanded ? 90 : 0))
                                    .opacity(queried ? 0 : 1)
                            }
                            .font(SidebarMetrics.group).foregroundStyle(.secondary)
                            .frame(height: 22).padding(.horizontal, SidebarMetrics.inset)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(HoverFillButtonStyle())
                        .padding(.top, SidebarMetrics.groupTop)
                        .accessibilityElement(children: .combine)
                        .accessibilityHint(expanded ? "Folds the group" : "Unfolds the group")
                        if expanded {
                            ForEach(group.rows, id: \.selection) { row in
                                SidebarRowView(row: row).selectableSidebarRow(selected: selection == row.selection) { selection = row.selection }
                            }
                        }
                    }
                }
                .transition(reduceMotion ? .opacity : .reveal)
            }
    }

    var body: some View {
        let epicCount = sidebarEpicCount
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: SidebarMetrics.rowGap) {
                SidebarSectionRow(title: "Home", icon: .home, selected: selection == .home, action: { selection = .home }).help("Home (⌘1)")
                ForEach(above, id: \.self) { slot($0, epicCount: epicCount) }
            }
            .padding(.horizontal, SidebarMetrics.edge).padding(.top, 8)
            if let openSlot {
                // the open section's list scrolls in the room between the rows above and the rows under it
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: SidebarMetrics.rowGap, pinnedViews: [.sectionHeaders]) {
                        slot(openSlot, epicCount: epicCount, pinned: true)
                    }
                    .padding(.horizontal, SidebarMetrics.edge).padding(.bottom, 8)
                }
                .onScrollGeometryChange(for: Bool.self, of: { $0.contentOffset.y > 1 }, action: { _, moved in scrolled = moved })
                .environment(\.sidebarScrolled, scrolled)
                .frame(maxHeight: .infinity)
                // Archive is the foot of Sessions' panel, only there while Sessions (or Archive itself) is the open section: archived sessions are noise otherwise
                if openSlot == .sessions {
                    ArchiveSection(
                        sessions: sessions, selection: $selection, open: open == .archive, toggle: { open = open == .archive ? .sessions : .archive },
                        choose: chooseArchived, searchRequest: searchRequest
                    )
                    .padding(.horizontal, SidebarMetrics.edge).padding(.vertical, 8)
                }
            } else {
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: SidebarMetrics.rowGap) {
                ForEach(below, id: \.self) { slot($0, epicCount: epicCount) }
            }
            .padding(.horizontal, SidebarMetrics.edge).padding(.vertical, 8)
            Divider()
            VStack(spacing: SidebarMetrics.rowGap) {
                SidebarSectionRow(title: "Settings", icon: .settings, selected: false, action: openSettings)
                SidebarSectionRow(title: "Usage", icon: .chartBar, selected: selection == .usage, action: { selection = .usage })
            }
            .padding(.horizontal, SidebarMetrics.edge).padding(.vertical, 8)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        // the open section's list slides open and shut, and the rows move between the top, the list and the foot with it
        .animation(.smooth(duration: 0.25), value: open)
        .onChange(of: searching) { if searching { searchFocused = true } else { query = "" } }
        .onChange(of: searchRequest) {
            if searchRequest?.section == .carrier && epicCount > 0 && open == .carrier {
                searching = true
                searchFocused = true
            }
        }
        .themedSidebarBackground()
        .navigationSplitViewColumnWidth(min: SidebarStore.widthRange.lowerBound, ideal: openWidth, max: SidebarStore.widthRange.upperBound)
        .background(SidebarWidthKeeper(width: openWidth))
    }
}

extension EnvironmentValues {
    /// Whether the open section's list has moved under its pinned row.
    @Entry var sidebarScrolled = false
}

extension View {
    /// The row of the open section while it is pinned at the top of the scroll: once the list has moved under it, it gets a fill (the theme's
    /// sidebar color, or a material where the sidebar is glass) and a faint shadow, so the rows slide under it and not through it.
    func pinnedSectionHeader() -> some View { modifier(PinnedSectionHeader()) }
}

private struct PinnedSectionHeader: ViewModifier {
    @Environment(\.sidebarScrolled) private var scrolled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How far the fade reaches under the row.
    private static let fade: CGFloat = 14

    func body(content: Content) -> some View {
        let sidebar = AppTheme.shared.surfaces.sidebar
        content
            .padding(.top, 8)
            .background {
                Rectangle()
                    .fill(sidebar.alpha == 1 ? AnyShapeStyle(Color(sidebar)) : AnyShapeStyle(.thinMaterial))
                    // reaches the edges of the column, past the padding the list has, and a little under the row
                    .padding(.horizontal, -SidebarMetrics.edge).padding(.bottom, -Self.fade)
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.7), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                    .opacity(scrolled ? 1 : 0)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: scrolled)
    }
}

/// Puts the sidebar column at the width the person left it, once when the window opens, and keeps what they drag it to. SwiftUI's own
/// `ideal` width is not what a launch opens at, so this asks the split view of AppKit under the column.
private struct SidebarWidthKeeper: NSViewRepresentable {
    let width: Double

    func makeNSView(context: Context) -> KeeperView { KeeperView(width: width) }
    func updateNSView(_ view: KeeperView, context: Context) {}

    final class KeeperView: NSView {
        private let width: Double
        private weak var split: NSSplitView?
        private var observer: NSObjectProtocol?
        private var pending: DispatchWorkItem?

        init(width: Double) {
            self.width = width
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        deinit { observer.map(NotificationCenter.default.removeObserver) }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, split == nil else { return }
            // after the first layout, which would otherwise take the width back; once more a moment later for the window's own restore
            DispatchQueue.main.async { [weak self] in self?.attach() }
        }

        private func attach() {
            var ancestor = superview
            while let view = ancestor, view is NSSplitView == false { ancestor = view.superview }
            guard let split = ancestor as? NSSplitView, split.arrangedSubviews.count > 1 else { return }
            self.split = split
            split.setPosition(width, ofDividerAt: 0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak split, width] in split?.setPosition(width, ofDividerAt: 0) }
            observer = NotificationCenter.default.addObserver(forName: NSSplitView.didResizeSubviewsNotification, object: split, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.changed() }
            }
        }

        /// Stored a moment after the drag settles; a column folded away, or under the minimum, is not the person's choice.
        private func changed() {
            guard let split, let column = split.arrangedSubviews.first, split.isSubviewCollapsed(column) == false else { return }
            let width = column.frame.width
            guard width >= SidebarStore.widthRange.lowerBound else { return }
            pending?.cancel()
            let save = DispatchWorkItem { SidebarStore().width = width }
            pending = save
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: save)
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
        SidebarSectionRow(title: "Carrier", icon: .send, selected: selected, keepActions: groupMenu || searching, action: select, actions: {
            Text(card.title)
                .font(SidebarMetrics.detail.weight(.semibold))
                .foregroundStyle(Self.tint(card.kind))
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Capsule().fill(Self.tint(card.kind).opacity(0.28)))
        }, hoverActions: {
            // the epics exist only while Carrier answers, so there is nothing to search or group before
            if snapshot != nil && unfolded {
                IconButton(
                    icon: .search, name: searching ? "Close epic search" : "Search epics", enabled: hasEpics, why: "No epics to search",
                    shortcut: "⌘F", pressed: searching
                ) {
                    searching.toggle()
                }
                IconButton(icon: .dots, name: "Group epics by") { groupMenu = true }
                    .popover(isPresented: $groupMenu, arrowEdge: .trailing) {
                        ChoiceMenu(
                            title: "Group by", options: GroupBy.allCases.map { ($0.title, $0) }, selection: $groupBy,
                            close: { groupMenu = false }
                        )
                    }
            }
        }, below: {
            if state == .stopped, let notice = engineNotConfiguredNotice(configExists: start.configExists) {
                // a line limit, so the height this asks for has a ceiling: measured at no width, wrapped text wants a line per word, and the
                // foot of the sidebar then asked for more than the window had and pushed the rows above and under it out of sight
                Text(notice).font(.caption).foregroundStyle(.orange).lineLimit(4).fixedSize(horizontal: false, vertical: true).help(notice)
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
        case .idle, .stopped, .connecting: .gray
        }
    }

    private static func hover(_ snapshot: PanelSnapshot) -> String {
        let box = carrierBox(snapshot)
        return ([box.uptime] + box.rows.map { "\($0.label): \($0.value)" }).joined(separator: " · ")
    }
}

/// The states of a sidebar button, drawn as the shape of the button: none at rest, a faint fill on hover, a stronger one while the mouse is
/// down, the middle one while what it opened is `open`, and the whole button dimmed when it is disabled (no fill then).
struct HoverFillButtonStyle: ButtonStyle {
    var open = false
    var radius: CGFloat = 6

    func makeBody(configuration: Configuration) -> some View {
        Shape(configuration: configuration, open: open, radius: radius)
    }

    private struct Shape: View {
        let configuration: ButtonStyleConfiguration
        let open: Bool
        let radius: CGFloat
        @State private var hovered = false
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            let fill = configuration.isPressed ? 0.2 : open ? (hovered ? 0.2 : 0.15) : hovered ? 0.1 : 0
            configuration.label
                .background(RoundedRectangle(cornerRadius: radius).fill(Color.primary.opacity(enabled ? fill : 0)))
                .opacity(enabled ? 1 : 0.35)
                .onHover { hovered = $0 }
                .animation(.easeOut(duration: 0.12), value: fill)
        }
    }
}

/// A 24-point button with an accessible name and a tooltip, drawn in `HoverFillButtonStyle`; `why` is the tooltip and the hint while it is
/// disabled. In a list row it runs its action and does not select the row.
struct IconButton: View {
    let icon: AppIcon
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
            Glyph(icon, size: 14).frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(HoverFillButtonStyle(open: pressed))
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
                        if selection == option.value { Glyph(.check) }
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
/// `actions` are what the row says (a count, a state) and are always there; `hoverActions` are its buttons, which fade in while the pointer
/// is over the row and stay while `keepActions` (a menu they opened is open, a search they started is on), left of `actions`.
struct SidebarSectionRow<Actions: View, HoverActions: View, Below: View>: View {
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                // the one control a keyboard reaches: Tab (with Full Keyboard Access) and Space run `action`; a click anywhere on the
                // row, but on its actions, still does through the tap below
                Button(action: action) {
                    HStack(spacing: 8) {
                        Glyph(icon, size: 18)
                            .foregroundStyle(selected ? .primary : .secondary)
                        Text(title).font(SidebarMetrics.section)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityAddTraits(selected ? .isSelected : [])
                // the buttons take their room even while hidden, so the row does not move when the pointer comes in
                let shown = hovered || keepActions
                HStack(spacing: 0) { hoverActions }
                    .opacity(shown ? 1 : 0).allowsHitTesting(shown)
                    .animation(.easeOut(duration: 0.15), value: shown)
                actions
            }
            .frame(minHeight: 24)
            below
        }
        .padding(.horizontal, SidebarMetrics.inset).padding(.vertical, SidebarMetrics.sectionPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.themeAccent.opacity(0.45) : Color.primary.opacity(hovered ? (dark ? 0.07 : 0.05) : 0)))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture(perform: action)
        .onHover { hovered = $0 }
        .accessibilityElement(children: .contain)
    }
}

struct SidebarRowView: View {
    let row: SidebarRow
    @AppStorage(AppPreferences.densityKey) private var density = AppPreferences.defaultDensity
    private static let titleLine: CGFloat = 17, detailLine: CGFloat = 15

    private var detailColor: Color {
        guard row.state == .needsYou else { return .secondary }
        return row.attention == .error ? .red : SessionRowView.attention
    }

    var body: some View {
        HStack(spacing: SidebarMetrics.inset) {
            ProjectIcon(name: row.name, colorKey: projectColorKey(row.repo), working: row.state == .running)
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
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.themeAccent.opacity(0.45) : Color.primary.opacity(hovered ? (dark ? 0.07 : 0.05) : 0)))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .environment(\.rowActive, selected || hovered)
            .onTapGesture(perform: action)
            .onHover { hovered = $0 }
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(.default, action)
    }
}
