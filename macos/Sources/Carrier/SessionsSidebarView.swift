import CarrierCore
import SwiftUI

/// The Sessions section and, while `open`, the sessions under it in the chosen order (or its empty state). Rows of the sidebar's
/// list: each session draws its own selection and the section is drawn and selected by its own row; the buttons in them do not select. The magnifier opens a search
/// field under the row.
struct SessionsRows: View {
    let sessions: Sessions
    @AppStorage(SidebarStore.pinnedKey) private var pinnedStored = ""
    /// The order, shared with the Sessions home and remembered by the model.
    @Binding var sort: SessionSort
    @Binding var selection: Selection
    let selected: Bool
    /// Chooses Sessions, which unfolds it.
    let select: () -> Void
    @Binding var open: Bool
    /// The last ⌘F: when it asks for Sessions, the search field opens and takes the keyboard.
    let searchRequest: SearchRequest?
    let newSession: () -> Void
    /// The + of a workspace: a new session in that folder.
    let newSessionIn: (String) -> Void
    @State private var sortOpen = false
    /// The search field's text while it is open, nil while it is closed; not remembered between launches.
    @State private var query: String?
    @FocusState private var searching: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// What the pointer is over, by group: the header and each row of it. A group's + shows while the pointer is anywhere in the group; a set
    /// and not a flag, because leaving one row and entering the next arrive in either order.
    @State private var hovering: [String: Set<String>] = [:]

    private func track(_ group: String, _ id: String) -> (Bool) -> Void {
        { inside in
            if inside { hovering[group, default: []].insert(id) } else { hovering[group]?.remove(id) }
        }
    }

    private func openSearch() {
        // nothing to search while there are no open sessions
        guard sessions.open > 0 else { return }
        open = true
        if query == nil { query = "" }
        searching = true
    }

    var body: some View {
        SidebarSectionRow(title: "Sessions", icon: "bubble.left.and.bubble.right", selected: selected, keepActions: sortOpen || query != nil, action: select, actions: {
            if sessions.open > 0 {
                Text("\(sessions.open)").font(SidebarMetrics.detail.weight(.semibold).monospacedDigit()).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    .accessibilityLabel(sessions.openLabel)
            }
        }, hoverActions: {
            IconButton(
                icon: "magnifyingglass", name: "Search sessions", enabled: sessions.open > 0, why: "No sessions to search", shortcut: "⌘F",
                pressed: query != nil
            ) {
                if query == nil { openSearch() } else { query = nil }
            }
            IconButton(icon: "ellipsis", name: "Sort sessions") { sortOpen.toggle() }
                .popover(isPresented: $sortOpen, arrowEdge: .bottom) {
                    ChoiceMenu(
                        title: "Sort sessions", options: SessionSort.allCases.map { ($0.menuTitle, $0) },
                        selection: $sort, close: { sortOpen = false }
                    )
                }
            IconButton(icon: "plus", name: "New session", action: newSession)
        })
        .help("Sessions (⌘2)")
        // the field is only drawn while unfolded, so a query must not outlive it: the magnifier would look pressed with no field
        .onChange(of: open) { if open == false { query = nil } }
        .onChange(of: searchRequest) { if searchRequest?.section == .sessions { openSearch() } }
        if open {
            // one block, so the list slides open and shut (the animation is the sidebar's, on `open`)
            LazyVStack(alignment: .leading, spacing: SidebarMetrics.rowGap) {
                if query != nil {
                    // not `Binding($query)`: its getter force-unwraps, and the field reads it once more after the query is nil
                    SidebarSearchField(
                        placeholder: "Search sessions", text: Binding(get: { query ?? "" }, set: { query = $0 }), focus: $searching,
                        close: { query = nil }
                    )
                }
                let groups = sessionGroups(sessions.rows, by: sort, query: query ?? "", pinned: pinnedIds(pinnedStored), now: Date(), calendar: .current)
                if let notice = chatHostNotice(missing: ChatHostStarter.shared.missing) {
                    SidebarEmptyBlock(icon: "exclamationmark.triangle", title: notice.title, line: notice.line) { EmptyView() }
                }
                if ChatHostStarter.shared.restartAdvised {
                    SidebarEmptyBlock(icon: "arrow.clockwise", title: chatHostRestartNotice.title, line: chatHostRestartNotice.line) { EmptyView() }
                }
                if let notice = ChatHostStarter.shared.upgradeNotice {
                    SidebarEmptyBlock(icon: "exclamationmark.triangle", title: notice.title, line: notice.line) { EmptyView() }
                }
                switch SidebarListState(shown: groups.count, of: sessions.open, query: query ?? "") {
                case .empty where ChatHostStarter.shared.missing.isEmpty:
                    let empty = EmptyState.noSessions
                    SidebarEmptyBlock(icon: empty.icon, title: empty.title, line: empty.line) {
                        Button("New session", action: newSession).help("New session")
                    }
                case .noMatch(let typed): SidebarNoResults(query: typed, clear: { query = "" })
                case .rows, .empty: EmptyView()
                }
                ForEach(groups, id: \.title) { group in
                    GroupHeader(
                        title: group.title, over: hovering[group.title]?.isEmpty == false, hover: track(group.title, "header"),
                        add: sort == .workspace && group.title != "Pinned" ? group.rows.first.map { row in { newSessionIn(row.base) } } : nil
                    )
                    ForEach(group.rows, id: \.id) { row in
                        SessionRowView(row: row, showsWorkspace: sort != .workspace)
                            .selectableSidebarRow(selected: selection == .session(id: row.id)) { selection = .session(id: row.id) }
                            .onHover(perform: track(group.title, row.id))
                    }
                }
            }
            .transition(reduceMotion ? .opacity : .reveal)
        }
    }
}

extension SessionSort {
    var menuTitle: String {
        switch self {
        case .workspace: "By workspace"
        case .age: "By age"
        case .status: "By state"
        }
    }
}

/// The title of a group of sessions, the same height in every order: a workspace's also has a + that shows while the pointer is over the
/// group (`over`: its header or any of its sessions) and starts a session in it (`add`; the other orders have none, and the room stays).
private struct GroupHeader: View {
    let title: String
    let over: Bool
    let hover: (Bool) -> Void
    let add: (() -> Void)?

    var body: some View {
        HStack {
            Text(title).font(SidebarMetrics.group).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 0)
            if let add {
                // it hides a moment late: the pointer crossing the gap between two rows, or on its way to the button, does not blink it
                IconButton(icon: "plus", name: "New session in \(title)", action: add).opacity(over ? 1 : 0)
                    .animation(over ? .easeOut(duration: 0.12) : .easeOut(duration: 0.12).delay(0.15), value: over)
            }
        }
        .frame(height: 22)
        .padding(.horizontal, SidebarMetrics.inset).padding(.top, SidebarMetrics.groupTop)
        .onHover(perform: hover)
    }
}
