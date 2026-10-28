import CarrierCore
import SwiftUI

/// The Archive section, fixed in the sidebar's foot above Settings and outside the scrolling list: its row with the count and the
/// magnifier and, while `open`, the archived sessions under it by age with the search field above them, up to about five rows before
/// they scroll. Choosing it moves the row up and opens its list; the list above it stays.
struct ArchiveSection: View {
    let sessions: Sessions
    @Binding var selection: Selection
    let open: Bool
    /// Choosing an archived session; the shell keeps Archive open, so the list the person chose from stays.
    let choose: (String) -> Void
    /// The last ⌘F: when it asks for Archive, the search field opens and takes the keyboard.
    let searchRequest: SearchRequest?
    /// The search field's text while it is open, nil while it is closed; not remembered between launches.
    @State private var query: String?
    @State private var contentHeight: CGFloat = 0
    @FocusState private var searching: Bool
    /// About five rows of a session (a row is about 38 points).
    private static let listHeight: CGFloat = 5 * 38

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
            SidebarSectionRow(title: "Archive", icon: "archivebox", selected: selection == .archive, action: { selection = .archive }, actions: {
                if archived > 0 {
                    Text("\(archived)").font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                        .accessibilityLabel("\(archived) archived")
                }
                IconButton(
                    icon: "magnifyingglass", name: "Search archive", enabled: archived > 0, why: "Nothing archived to search", shortcut: "⌘F",
                    pressed: query != nil
                ) {
                    if query == nil { openSearch() } else { query = nil }
                }
            })
            .help("Archive")
            if open {
                if query != nil {
                    // not `Binding($query)`: its getter force-unwraps and crashes once the query is nil
                    SidebarSearchField(
                        placeholder: "Search archive", text: Binding(get: { query ?? "" }, set: { query = $0 }), focus: $searching,
                        close: { query = nil }
                    )
                }
                let groups = archivedGroups(sessions.rows, query: query ?? "")
                switch SidebarListState(shown: groups.count, of: archived, query: query ?? "") {
                case .empty: SidebarEmptyBlock(state: .nothingArchived)
                case .noMatch(let typed): SidebarNoResults(query: typed, clear: { query = "" })
                case .rows: list(groups)
                }
            }
        }
        // the field is only drawn while unfolded, so a query must not outlive it: the magnifier would look pressed with no field
        .onChange(of: open) { if open == false { query = nil } }
        .onChange(of: searchRequest) { if searchRequest?.section == .archive { openSearch() } }
    }

    private func list(_ groups: [SessionGroup]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(groups, id: \.title) { group in
                    Text(group.title).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                        .padding(.horizontal, SidebarMetrics.inset).padding(.top, 4)
                    ForEach(group.rows, id: \.id) { row in
                        let chosen = selection == .session(id: row.id)
                        Button {
                            choose(row.id)
                        } label: {
                            SessionRowView(row: row, showsWorkspace: true)
                                .padding(.vertical, 2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 8).fill(chosen ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.45) : .clear))
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
