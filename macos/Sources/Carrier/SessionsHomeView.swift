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
    @AppStorage(SidebarStore.pinnedKey) private var pinnedStored = ""
    @FocusState private var searching: Bool
    @FocusState private var listFocused: Bool
    /// The row the arrow keys are on, by id; Return opens it.
    @State private var highlighted: String?

    var body: some View {
        let page = sessionsPage(sessions.rows, by: sort, query: query ?? "", filter: filter, pinned: pinnedIds(pinnedStored))
        let searched = (query ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        VStack(spacing: 0) {
            if ChatHostStarter.shared.restartAdvised {
                Label {
                    VStack(alignment: .leading) {
                        Text(chatHostRestartNotice.title).bold()
                        Text(chatHostRestartNotice.line).foregroundStyle(.secondary)
                    }
                } icon: { Image(systemName: "arrow.clockwise") }
                    .padding(.horizontal, 20).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
            }
            sessionsContent(page: page, searched: searched)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toolbar { toolbar }
    }

    @ViewBuilder private func sessionsContent(page: SessionsPage, searched: Bool) -> some View {
        Group {
            if let notice = chatHostNotice(missing: ChatHostStarter.shared.missing) {
                EmptyStateView(icon: "exclamationmark.triangle", title: notice.title, line: notice.line)
            } else if let empty = page.emptyState {
                VStack(alignment: .leading, spacing: 0) {
                    if filter.chips.isEmpty == false { chips.padding(.horizontal, 20).padding(.vertical, 8) }
                    EmptyStateView(state: empty, action: empty == .noSessionsMatch ? ("Clear filters", clear) : nil)
                }
            } else {
                // the scroll view is the page, so the list runs up under the toolbar as Carrier's does and the bar is the system's
                let ids = page.groups.flatMap { $0.rows.map(\.id) }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            if filter.chips.isEmpty == false { chips.padding(.horizontal, 8).padding(.bottom, 8) }
                            ForEach(page.groups, id: \.title) { group in
                                if searched == false { groupHeader(group) }
                                ForEach(group.rows, id: \.id) { row in
                                    SessionHomeRow(
                                        row: row, showsWorkspace: searched || sort != .workspace, highlighted: highlighted == row.id && listFocused,
                                        filterWorkspace: { filter.workspaces.insert($0) }
                                    ) { select(row.id) }
                                    .id(row.id)
                                }
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                    }
                    // Up and Down move through the rows and Return opens the one they are on
                    .focusable().focused($listFocused).focusEffectDisabled()
                    .onKeyPress(.downArrow) { move(1, in: ids, proxy) }
                    .onKeyPress(.upArrow) { move(-1, in: ids, proxy) }
                    .onAppear { listFocused = true }
                    .onKeyPress(.return) {
                        guard let highlighted, ids.contains(highlighted) else { return .ignored }
                        select(highlighted)
                        return .handled
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func move(_ step: Int, in ids: [String], _ proxy: ScrollViewProxy) -> KeyPress.Result {
        guard ids.isEmpty == false else { return .ignored }
        let current = highlighted.flatMap(ids.firstIndex(of:))
        let next = current.map { min(max($0 + step, 0), ids.count - 1) } ?? (step > 0 ? 0 : ids.count - 1)
        highlighted = ids[next]
        proxy.scrollTo(ids[next])
        return .handled
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
                .help("New session")
        }
    }

    @ViewBuilder private var searchItem: some View {
        if query != nil {
            HStack(spacing: 8) {
                // a fixed box, so the magnifier sits on the field's centre line and clear of the pill's rounded edge
                Image(systemName: "magnifyingglass").font(.body).foregroundStyle(.secondary).frame(width: 18, height: 18).accessibilityHidden(true)
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
            .padding(.horizontal, 8).frame(width: 220)
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
                        .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(Color.themeAccent))
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
                        Image(systemName: "xmark").font(.scaled(8, weight: .bold))
                    }
                    .font(.caption.weight(.medium)).foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 3).background(Capsule().fill(Color.themeAccent))
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

extension SessionSort {
    var title: String {
        switch self {
        case .workspace: "Workspace"
        case .age: "Age"
        case .status: "Status"
        }
    }
}

/// A wide row of the Sessions home: the project's icon (the session's state is on it, as in the sidebar), the title with the workspace as a tag
/// outside the workspace order, what the agent last wrote under it (or what the session waits for), and a line of where it works, how many turns
/// it took and the model. On the right the age and the providers; under the pointer they give way to Pin and Archive. A session that waits for
/// the person is orange; an archived match is dimmed and tagged.
private struct SessionHomeRow: View {
    private let timeChanges = TimeFormatChanges()
    let row: SessionRow
    let showsWorkspace: Bool
    let highlighted: Bool
    let filterWorkspace: (String) -> Void
    let open: () -> Void
    @State private var hovered = false
    @Environment(SessionActions.self) private var actions
    @AppStorage(SidebarStore.pinnedKey) private var pinnedStored = ""

    private var pinned: Bool { pinnedIds(pinnedStored).contains(row.id) }

    var body: some View {
        let active = hovered || highlighted
        HStack(alignment: .top, spacing: 12) {
            ProjectIcon(name: row.workspace, colorKey: projectColorKey(row.base), halo: row.state == .working, mark: .session(row.state))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if pinned { Image(systemName: "pin.fill").font(.scaled(10)).foregroundStyle(.secondary).accessibilityLabel("Pinned") }
                    Text(row.title).font(.scaled(13, weight: .medium)).lineLimit(1).truncationMode(.tail)
                    if showsWorkspace { tag(row.workspace) }
                    if row.archived { tag("Archived") }
                }
                status
                meta
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text(timeText(row.updatedAt, now: Date())).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .accessibilityLabel(spokenAge(row.updatedAt, now: Date()))
                ProviderMarks(names: row.providers)
            }
            .opacity(active ? 0 : 1)
            .overlay(alignment: .topTrailing) { actionButtons.opacity(active ? 1 : 0).allowsHitTesting(active) }
        }
        .animation(.easeInOut(duration: 0.15), value: active)
        .opacity(row.archived ? 0.55 : 1)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(active ? Color.primary.opacity(0.07) : .clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .onHover { hovered = $0 }
        .sessionContextMenu(row, filterWorkspace: filterWorkspace)
        .help(row.title)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Open", open)
    }

    /// What the session is doing, or the last thing the agent said.
    @ViewBuilder private var status: some View {
        switch row.state {
        case .waiting: Text("Waiting for you").fontWeight(.medium).foregroundStyle(SessionRowView.attention).font(.callout)
        case .working: Text("Working…").foregroundStyle(.secondary).font(.callout)
        case .idle, .done:
            if let message = row.lastMessage {
                Text(message).foregroundStyle(.secondary).font(.callout).lineLimit(1).truncationMode(.tail)
            } else {
                Text("No reply yet").foregroundStyle(.tertiary).font(.callout)
            }
        }
    }

    /// Where it works, how many turns it took and the model of the last.
    private var meta: some View {
        HStack(spacing: 6) {
            Label(row.branch ?? "Base folder", systemImage: row.branch == nil ? "folder" : "arrow.triangle.branch")
                .labelStyle(.titleAndIcon).lineLimit(1).truncationMode(.middle)
            if row.turns > 0 { Text("·"); Text(row.turns == 1 ? "1 turn" : "\(row.turns) turns") }
            if let model = TurnSummary(model: row.model).shortModel { Text("·"); Text(model) }
        }
        .font(.caption).foregroundStyle(.tertiary).lineLimit(1)
    }

    private var actionButtons: some View {
        HStack(spacing: 4) {
            iconButton(pinned ? "pin.slash" : "pin", pinned ? "Unpin" : "Pin") {
                let ids = pinnedIds(pinnedStored)
                pinnedStored = storedPins(pinned ? ids.subtracting([row.id]) : ids.union([row.id]))
            }
            if row.archived {
                iconButton("arrow.uturn.backward", "Restore") { Task { if let refusal = await actions.restore(row.id) { tell(refusal) } } }
            } else {
                iconButton("archivebox", "Archive") { Task { if let refusal = await actions.archive(row.id) { tell(refusal) } } }
            }
        }
    }

    private func iconButton(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.scaled(12)).foregroundStyle(.secondary).frame(width: 26, height: 26)
                .background(Circle().fill(Color.secondary.opacity(0.14)))
        }
        .buttonStyle(.plain).help(title).accessibilityLabel(title)
    }

    private func tag(_ text: String) -> some View {
        Text(text).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().strokeBorder(Color.secondary.opacity(0.5)))
    }
}
