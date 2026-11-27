import CarrierCore
import CarrierUI
import SwiftUI

/// The sidebar: Home, Sessions, Terminal and Carrier stacked in that order, then Settings and Usage as two icon buttons at the foot. The open section takes the room that is
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
                        SidebarSearchField(placeholder: Copy.sidebarSearchEpics(), text: $query, focus: $searchFocused, close: { searching = false })
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
                            .sidebarFont(.group).foregroundStyle(.secondary)
                            .frame(height: 22).padding(.horizontal, SidebarMetrics.inset)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(HoverFillButtonStyle())
                        .padding(.top, SidebarMetrics.groupTop)
                        .accessibilityElement(children: .combine)
                        .accessibilityHint(expanded ? Copy.sidebarFoldGroup() : Copy.sidebarUnfoldGroup())
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
        VStack(spacing: Tokens.Space.none) {
            VStack(alignment: .leading, spacing: SidebarMetrics.rowGap) {
                SidebarSectionRow(title: Copy.sidebarHome(), icon: .home, selected: selection == .home, action: { selection = .home }).help(Copy.sidebarHomeHelp())
                ForEach(above, id: \.self) { slot($0, epicCount: epicCount) }
            }
            .padding(.horizontal, SidebarMetrics.edge).padding(.top, Tokens.Space.s8)
            if let openSlot {
                // the open section's list scrolls in the room between the rows above and the rows under it
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: SidebarMetrics.rowGap, pinnedViews: [.sectionHeaders]) {
                        slot(openSlot, epicCount: epicCount, pinned: true)
                    }
                    .padding(.horizontal, SidebarMetrics.edge).padding(.bottom, Tokens.Space.s8)
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
                    .padding(.horizontal, SidebarMetrics.edge).padding(.vertical, Tokens.Space.s8)
                }
            } else {
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: SidebarMetrics.rowGap) {
                ForEach(below, id: \.self) { slot($0, epicCount: epicCount) }
            }
            .padding(.horizontal, SidebarMetrics.edge).padding(.vertical, Tokens.Space.s8)
            Divider()
            // two icon buttons at the two ends, no words: the name is the tooltip and the accessible label
            HStack(spacing: Tokens.Space.none) {
                IconButton(icon: .settings, name: Copy.sidebarSettings(), action: openSettings)
                Spacer(minLength: 0)
                IconButton(icon: .chartBar, name: Copy.sidebarUsage(), pressed: selection == .usage, action: { selection = .usage })
            }
            .padding(.horizontal, SidebarMetrics.edge).padding(.vertical, Tokens.Space.s8)
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
        // the content's own minimum: the column's modifier below left the item at 140, so the column could be dragged to half of it
        .frame(minWidth: SidebarStore.widthRange.lowerBound)
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
    @Environment(\.pieceTheme) private var theme
    /// How far the fade reaches under the row.
    private static let fade: CGFloat = 14

    func body(content: Content) -> some View {
        let sidebar = theme.surfaces.sidebar
        content
            .padding(.top, Tokens.Space.s8)
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
