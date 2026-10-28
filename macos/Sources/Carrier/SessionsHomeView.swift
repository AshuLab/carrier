import CarrierCore
import SwiftUI

/// The centre when the Sessions row is selected: the title and count, one glass group with Search and Filter, New session, the chips
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
        VStack(alignment: .leading, spacing: 0) {
            header(page)
            if filter.chips.isEmpty == false { chips.padding(.horizontal, 20).padding(.bottom, 8) }
            if let empty = page.emptyState {
                EmptyStateView(state: empty, action: empty == .noSessionsMatch ? ("Clear filters", clear) : nil)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(page.groups, id: \.title) { group in
                            if searched == false { groupHeader(group) }
                            ForEach(group.rows, id: \.id) { row in
                                SessionHomeRow(row: row, showsWorkspace: searched || sort != .workspace) { select(row.id) }
                            }
                        }
                    }
                    .padding(.horizontal, 12).padding(.bottom, 16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Search and the filters back to nothing.
    private func clear() {
        query = nil
        filter = SessionFilter()
    }

    private func header(_ page: SessionsPage) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Sessions").font(.title2.weight(.semibold))
                if page.subtitle.isEmpty == false { Text(page.subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            .fixedSize()
            HStack(spacing: 0) {
                searchHalf
                Divider().frame(height: 16)
                filterHalf
            }
            .glassEffect(.regular, in: .capsule)
            Spacer(minLength: 0)
            Button(action: newSession) { Label("New session", systemImage: "plus") }
                .buttonStyle(.glassProminent).buttonBorderShape(.capsule)
                .disabled(sessions.canStart == false)
                .help(sessions.cannotStartReason ?? "New session")
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    @ViewBuilder private var searchHalf: some View {
        if let text = Binding($query) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search sessions", text: text)
                    .textFieldStyle(.plain)
                    .focused($searching)
                    .onKeyPress(.escape) {
                        query = nil
                        return .handled
                    }
                Button { query = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).help("Close search (Esc)").accessibilityLabel("Close search")
            }
            .padding(.horizontal, 12).padding(.vertical, 6).frame(width: 220)
        } else {
            Button {
                query = ""
                searching = true
            } label: { Label("Search", systemImage: "magnifyingglass").padding(.horizontal, 12).padding(.vertical, 6).contentShape(Rectangle()) }
                .buttonStyle(.plain)
        }
    }

    private var filterHalf: some View {
        Button { filterOpen.toggle() } label: {
            HStack(spacing: 6) {
                Label("Filter", systemImage: "line.3.horizontal.decrease")
                if filter.count > 0 {
                    Text("\(filter.count)").font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(Color.accentColor))
                        .accessibilityLabel("\(filter.count) filters applied")
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        .help(row.title)
    }

    private func tag(_ text: String) -> some View {
        Text(text).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().strokeBorder(Color.secondary.opacity(0.5)))
    }
}
