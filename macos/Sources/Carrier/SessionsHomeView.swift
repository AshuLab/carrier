import CarrierCore
import SwiftUI

/// The centre when the Sessions row is selected: the toolbar's Search and Filter group and New session, the chips
/// of the applied filters and the sessions grouped as the sort says (docs/specs/sessions-in-the-app.md, "Sessions home"). What it shows
/// is `sessionsPage`; the search and the filter are not remembered between visits, the sort is (it is the sidebar's).
struct SessionsHomeView: View {
    let sessions: Sessions
    @Binding var sort: SessionSort
    let newSession: () -> Void
    let select: (String) -> Void
    /// The search field's text while it is open, nil while it is closed.
    @State private var query: String?
    @State private var filter = SessionFilter()
    @State private var filterOpen = false
    @FocusState private var searching: Bool

    var body: some View {
        let page = sessionsPage(sessions.rows, by: sort, query: query ?? "", filter: filter)
        let searched = (query ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        Group {
            if let empty = page.emptyState {
                VStack(alignment: .leading, spacing: 0) {
                    if filter.chips.isEmpty == false { chips.padding(.horizontal, 20).padding(.vertical, 8) }
                    EmptyStateView(state: empty, action: empty == .noSessionsMatch ? ("Clear filters", clear) : nil)
                }
            } else {
                // the scroll view is the page, so the list runs up under the toolbar as Carrier's does and the bar is the system's
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if filter.chips.isEmpty == false { chips.padding(.horizontal, 8).padding(.bottom, 8) }
                        ForEach(page.groups, id: \.title) { group in
                            if searched == false { groupHeader(group) }
                            ForEach(group.rows, id: \.id) { row in
                                SessionHomeRow(row: row, showsWorkspace: searched || sort != .workspace) { select(row.id) }
                            }
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toolbar { toolbar }
    }

    /// Search and the filters back to nothing.
    private func clear() {
        query = nil
        filter = SessionFilter()
    }

    /// What the toolbar carries (the window's title and count are `PanelView`'s): Search and Filter in one pill, New session apart,
    /// as the primary action.
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            searchItem
            filterItem
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) {
            Button(action: newSession) { Label("New session", systemImage: "plus").labelStyle(.titleAndIcon) }
                .buttonStyle(.glassProminent)
                .disabled(sessions.canStart == false)
                .help(sessions.cannotStartReason ?? "New session")
        }
    }

    @ViewBuilder private var searchItem: some View {
        if query != nil {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                // not `Binding($query)`: its getter force-unwraps and crashes once the query is nil
                TextField("Search sessions", text: Binding(get: { query ?? "" }, set: { query = $0 }))
                    .textFieldStyle(.plain)
                    .focused($searching)
                    .onKeyPress(.escape) {
                        query = nil
                        return .handled
                    }
                Button { query = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).help("Close search (Esc)").accessibilityLabel("Close search")
            }
            .frame(width: 200)
        } else {
            Button {
                query = ""
                searching = true
            } label: { Label("Search", systemImage: "magnifyingglass").labelStyle(.titleAndIcon) }
        }
    }

    private var filterItem: some View {
        Button { filterOpen.toggle() } label: {
            HStack(spacing: 6) {
                Label("Filter", systemImage: "line.3.horizontal.decrease").labelStyle(.titleAndIcon)
                if filter.count > 0 {
                    Text("\(filter.count)").font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(Color.accentColor))
                        .accessibilityLabel("\(filter.count) filters applied")
                }
            }
        }
        .popover(isPresented: $filterOpen, arrowEdge: .bottom) {
            SessionFilterPopover(sort: $sort, filter: $filter, agents: Set(sessions.rows.map(\.agent)).sorted())
        }
    }

    private var chips: some View {
        FlowLayout(spacing: 6) {
            ForEach(filter.chips, id: \.self) { chip in
                Button { filter.remove(chip) } label: {
                    HStack(spacing: 4) {
                        Text(chip.title)
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    }
                    .font(.caption.weight(.medium)).foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 3).background(Capsule().fill(Color.accentColor))
                }
                .buttonStyle(.plain).accessibilityLabel("Remove filter \(chip.title)")
            }
            Button("Clear filters", action: clear).buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func groupHeader(_ group: SessionGroup) -> some View {
        HStack(spacing: 6) {
            Text(group.title).font(.callout.weight(.semibold))
            Text(group.rows.count == 1 ? "1 session" : "\(group.rows.count) sessions").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8).padding(.top, 14).padding(.bottom, 4)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The sort and what to show by status and by agent; nothing ticked in a kind shows everything of it.
private struct SessionFilterPopover: View {
    @Binding var sort: SessionSort
    @Binding var filter: SessionFilter
    let agents: [String]

    private func ticked<Value: Hashable>(_ set: WritableKeyPath<SessionFilter, Set<Value>>, _ value: Value) -> Binding<Bool> {
        Binding(
            get: { filter[keyPath: set].contains(value) },
            set: { on in
                if on { filter[keyPath: set].insert(value) } else { filter[keyPath: set].remove(value) }
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            heading("Sort by")
            ForEach(SessionSort.allCases, id: \.self) { option in
                Button { sort = option } label: {
                    HStack {
                        Text(option.title)
                        Spacer(minLength: 0)
                        if sort == option { Image(systemName: "checkmark") }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityAddTraits(sort == option ? .isSelected : [])
            }
            Divider().padding(.vertical, 4)
            heading("Show")
            ForEach(SessionFilter.offeredStatuses, id: \.self) { Toggle($0.title, isOn: ticked(\.statuses, $0)) }
            if agents.isEmpty == false {
                Divider().padding(.vertical, 4)
                heading("Agent")
                ForEach(agents, id: \.self) { Toggle($0, isOn: ticked(\.agents, $0)) }
            }
            if filter.count > 0 {
                Divider().padding(.vertical, 4)
                Button("Clear filters") { filter = SessionFilter() }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 220)
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
    }
}

private extension SessionSort {
    var title: String {
        switch self {
        case .workspace: "Workspace"
        case .age: "Age"
        case .status: "Status"
        }
    }
}

/// A wide row: state glyph, title (with the workspace as a tag outside the workspace order) and under it the agent and the branch of
/// a worktree session; on the right the Archived tag, for an archived match that is dimmed, and the age. A session that waits for
/// the person is orange.
private struct SessionHomeRow: View {
    let row: SessionRow
    let showsWorkspace: Bool
    let open: () -> Void
    @State private var hovered = false
    private static let spokenAge: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                SessionGlyph(state: row.state)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(row.title).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.tail)
                            .foregroundStyle(row.state == .waiting ? Color.orange : .primary)
                        if showsWorkspace { tag(row.workspace) }
                    }
                    HStack(spacing: 6) {
                        Text(row.agent)
                        if let branch = row.branch { Text(branch).foregroundStyle(.blue) }
                    }
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                if row.archived { tag("Archived") }
                Text(sessionAge(row.updatedAt, now: Date())).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .accessibilityLabel(Self.spokenAge.localizedString(for: min(row.updatedAt, Date()), relativeTo: Date()))
            }
            .opacity(row.archived ? 0.55 : 1)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10).fill(hovered ? Color.primary.opacity(0.07) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .contextMenu { SessionMenuItems(row: row) }
        .help(row.title)
    }

    private func tag(_ text: String) -> some View {
        Text(text).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().strokeBorder(Color.secondary.opacity(0.5)))
    }
}
