import CarrierCore
import SwiftUI

/// The Sessions section and, while `open`, the sessions under it in the chosen order (or its empty state). Rows of the sidebar's
/// list: each session is tagged with a `Selection` and the section is drawn and selected by its own row; the buttons in them do not select. The magnifier opens a search
/// field under the row.
struct SessionsRows: View {
    let sessions: Sessions
    let selected: Bool
    /// Chooses Sessions, which unfolds it.
    let select: () -> Void
    @Binding var open: Bool
    /// The last ⌘F: when it asks for Sessions, the search field opens and takes the keyboard.
    let searchRequest: SearchRequest?
    @State private var sort = SidebarStore().sessionSort
    @State private var sortOpen = false
    /// The search field's text while it is open, nil while it is closed; not remembered between launches.
    @State private var query: String?
    @FocusState private var searching: Bool

    private func openSearch() {
        // nothing to search while there are no open sessions
        guard sessions.open > 0 else { return }
        open = true
        if query == nil { query = "" }
        searching = true
    }

    var body: some View {
        SidebarSectionRow(title: "Sessions", icon: "bubble.left.and.bubble.right", selected: selected, action: select, actions: {
            if sessions.open > 0 {
                Text("\(sessions.open)").font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    .accessibilityLabel(sessions.openLabel)
            }
            IconButton(
                icon: "magnifyingglass", name: "Search sessions", enabled: sessions.open > 0, why: "No sessions to search", shortcut: "⌘F",
                pressed: query != nil
            ) {
                if query == nil { openSearch() } else { query = nil }
            }
            IconButton(icon: "ellipsis", name: "Sort sessions") { sortOpen.toggle() }
                .popover(isPresented: $sortOpen, arrowEdge: .bottom) {
                    ChoiceMenu(
                        title: "Sort sessions", options: SessionSort.allCases.map { ($0.title, $0) },
                        selection: Binding(get: { sort }, set: { sort = $0; SidebarStore().sessionSort = $0 }), close: { sortOpen = false }
                    )
                }
            IconButton(icon: "plus", name: "New session", enabled: sessions.canStart, why: Sessions.cannotStartReason) {}
        })
        .help("Sessions (⌘2)")
        // the field is only drawn while unfolded, so a query must not outlive it: the magnifier would look pressed with no field
        .onChange(of: open) { if open == false { query = nil } }
        .onChange(of: searchRequest) { if searchRequest?.section == .sessions { openSearch() } }
        if open {
            if let text = Binding($query) {
                SidebarSearchField(placeholder: "Search sessions", text: text, focus: $searching, close: { query = nil })
            }
            let groups = sessionGroups(sessions.rows, by: sort, query: query ?? "", now: Date(), calendar: .current)
            switch SidebarListState(shown: groups.count, of: sessions.open, query: query ?? "") {
            case .empty:
                let empty = EmptyState.noSessions
                SidebarEmptyBlock(icon: empty.icon, title: empty.title, line: empty.line) {
                    Button("New session") {}.disabled(sessions.canStart == false).help(sessions.canStart ? "New session" : Sessions.cannotStartReason)
                }
            case .noMatch(let typed): SidebarNoResults(query: typed, clear: { query = "" })
            case .rows: EmptyView()
            }
            ForEach(groups, id: \.title) { group in
                if sort == .workspace {
                    WorkspaceHeader(title: group.title, canStart: sessions.canStart)
                } else {
                    Text(group.title).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1).selectionDisabled().flatSidebarRow()
                }
                ForEach(group.rows, id: \.id) {
                    SessionRowView(row: $0, showsWorkspace: sort != .workspace).tag(Selection.session(id: $0.id)).flatSidebarRow()
                }
            }
        }
    }
}

private extension SessionSort {
    var title: String {
        switch self {
        case .workspace: "By workspace"
        case .age: "By age"
        case .status: "By status"
        }
    }
}

/// A workspace's name, with a + that appears on hover.
private struct WorkspaceHeader: View {
    let title: String
    let canStart: Bool
    @State private var hovered = false

    var body: some View {
        HStack {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 0)
            IconButton(icon: "plus", name: "New session in \(title)", enabled: canStart, why: Sessions.cannotStartReason) {}
                .opacity(hovered ? 1 : 0)
        }
        .onHover { hovered = $0 }
        .selectionDisabled()
        .flatSidebarRow()
    }
}

private struct SessionRowView: View {
    let row: SessionRow
    /// Outside the workspace order the group is not the workspace, so the second line says it.
    let showsWorkspace: Bool
    private static let spokenAge: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    var body: some View {
        HStack(spacing: 10) {
            SessionGlyph(state: row.state)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.system(size: 12)).lineLimit(1).truncationMode(.tail)
                Text(showsWorkspace ? "\(row.workspace) · \(row.agent)" : row.agent).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            // "5m" reads aloud as "5 m": say it in words
            Text(sessionAge(row.updatedAt, now: Date())).font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                .accessibilityLabel(Self.spokenAge.localizedString(for: min(row.updatedAt, Date()), relativeTo: Date()))
        }
        .padding(.horizontal, 2).padding(.vertical, 2)
        .help(row.title)
    }
}

/// A spinner while working, an orange mark while it waits for the person, a hollow circle when idle and a green check when done.
private struct SessionGlyph: View {
    let state: SessionState

    var body: some View {
        glyph.frame(width: 20, height: 20).accessibilityLabel(label)
    }

    @ViewBuilder private var glyph: some View {
        switch state {
        case .working: SpinningRing(diameter: 14, lineWidth: 2, color: .systemBlue)
        case .waiting: Disc(color: .orange, mark: "!")
        case .idle: Circle().strokeBorder(Color.gray, lineWidth: 2).frame(width: 14, height: 14)
        case .done: Disc(color: .green, mark: "✓")
        }
    }

    private var label: String {
        switch state {
        case .working: "Working"
        case .waiting: "Waiting for you"
        case .idle: "Idle"
        case .done: "Done"
        }
    }
}
