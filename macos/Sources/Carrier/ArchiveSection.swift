import CarrierCore
import SwiftUI

/// The Archive section, fixed in the sidebar's foot above Settings and outside the scrolling list, and there only while Sessions or
/// Archive is the open section: its row (the count, and on hover the magnifier, the sort and the chevron that opens and folds the list)
/// and, while `open`, the archived sessions under it, grouped by age or by workspace, with the search field above them, up to about five
/// rows before they scroll. The list slides open and shut. Choosing the row opens its list; the sessions above it stay.
struct ArchiveSection: View {
    let sessions: Sessions
    @Binding var selection: Selection
    let open: Bool
    /// The chevron: opens the list, or folds it back to the row without changing what is selected.
    let toggle: () -> Void
    /// Choosing an archived session; the shell keeps Archive open, so the list the person chose from stays.
    let choose: (String) -> Void
    /// The last ⌘F: when it asks for Archive, the search field opens and takes the keyboard.
    let searchRequest: SearchRequest?
    /// The search field's text while it is open, nil while it is closed; not remembered between launches.
    @State private var query: String?
    @State private var contentHeight: CGFloat = 0
    @FocusState private var searching: Bool
    @AppStorage(SidebarStore.archiveListSortKey) private var sort = SessionSort.age
    @State private var sortOpen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// About five rows of a session (a row is about 38 points).
    private static let listHeight: CGFloat = 5 * 38
    /// What the sort menu offers: an archived session has no state to group by.
    private static let sorts: [SessionSort] = [.workspace, .age]

    private func openSearch() {
        // nothing to search while nothing is archived
        guard archivedCount(sessions.rows) > 0 else { return }
        selection = .archive
        if query == nil { query = "" }
        searching = true
    }

    var body: some View {
        let archived = archivedCount(sessions.rows)
        VStack(spacing: 2) {
            SidebarSectionRow(
                title: "Archive", icon: "archivebox", selected: selection == .archive, keepActions: sortOpen || query != nil,
                action: { selection = .archive }, actions: {
                    if archived > 0 {
                        Text("\(archived)").font(SidebarMetrics.detail.weight(.semibold).monospacedDigit()).foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                            .accessibilityLabel("\(archived) archived")
                    }
                }, hoverActions: {
                    IconButton(
                        icon: "magnifyingglass", name: "Search archive", enabled: archived > 0, why: "Nothing archived to search", shortcut: "⌘F",
                        pressed: query != nil
                    ) {
                        if query == nil { openSearch() } else { query = nil }
                    }
                    IconButton(icon: "ellipsis", name: "Sort archive") { sortOpen.toggle() }
                        .popover(isPresented: $sortOpen, arrowEdge: .bottom) {
                            ChoiceMenu(
                                title: "Sort archive", options: Self.sorts.map { ($0.menuTitle, $0) }, selection: $sort, close: { sortOpen = false }
                            )
                        }
                    IconButton(icon: open ? "chevron.down" : "chevron.right", name: open ? "Fold archive" : "Unfold archive", action: toggle)
                }
            )
            .help("Archive")
            if open {
                VStack(spacing: 2) {
                    if query != nil {
                        // not `Binding($query)`: its getter force-unwraps and crashes once the query is nil
                        SidebarSearchField(
                            placeholder: "Search archive", text: Binding(get: { query ?? "" }, set: { query = $0 }), focus: $searching,
                            close: { query = nil }
                        )
                    }
                    let groups = archivedGroups(sessions.rows, by: sort, query: query ?? "")
                    switch SidebarListState(shown: groups.count, of: archived, query: query ?? "") {
                    case .empty: SidebarEmptyBlock(state: .nothingArchived)
                    case .noMatch(let typed): SidebarNoResults(query: typed, clear: { query = "" })
                    case .rows: list(groups)
                    }
                }
                .transition(reduceMotion ? .opacity : .reveal)
            }
        }
        // opening and folding slide the list; a pointer-driven open (the row, the chevron, ⌘F) and a shell-driven one look the same
        .animation(.smooth(duration: 0.25), value: open)
        // the field is only drawn while unfolded, so a query must not outlive it: the magnifier would look pressed with no field
        .onChange(of: open) { if open == false { query = nil } }
        .onChange(of: searchRequest) { if searchRequest?.section == .archive { openSearch() } }
    }

    private func list(_ groups: [SessionGroup]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(groups, id: \.title) { group in
                    Text(group.title).font(SidebarMetrics.group).foregroundStyle(.secondary).lineLimit(1)
                        .padding(.horizontal, SidebarMetrics.inset).padding(.top, 4)
                    ForEach(group.rows, id: \.id) { row in
                        let chosen = selection == .session(id: row.id)
                        Button {
                            choose(row.id)
                        } label: {
                            SessionRowView(row: row, showsWorkspace: true)
                                .padding(.vertical, 2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 8).fill(chosen ? Color.themeAccent.opacity(0.45) : .clear))
                                .contentShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(chosen ? .isSelected : [])
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
        }
        // as tall as its rows up to about five, then it scrolls
        .frame(height: min(contentHeight, Self.listHeight))
    }
}
