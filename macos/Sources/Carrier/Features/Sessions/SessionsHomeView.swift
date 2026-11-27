import CarrierCore
import CarrierUI
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
    @AppStorage(Preference.sidebarPinned) private var pinnedStored
    @FocusState private var searching: Bool
    @FocusState private var listFocused: Bool
    /// The row the arrow keys are on, by id; Return opens it.
    @State private var highlighted: String?

    var body: some View {
        let page = sessionsPage(sessions.rows, by: sort, query: query ?? "", filter: filter, pinned: pinnedIds(pinnedStored))
        let searched = (query ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        VStack(spacing: Tokens.Space.none) {
            if ChatHostStarter.shared.restartAdvised {
                ProblemNotice(title: chatHostRestartNotice().title, detail: chatHostRestartNotice().line, symbol: .refresh)
                    .padding(.horizontal, Tokens.Space.s20).padding(.vertical, Tokens.Space.s8)
            }
            sessionsContent(page: page, searched: searched)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toolbar { toolbar }
    }

    @ViewBuilder private func sessionsContent(page: SessionsPage, searched: Bool) -> some View {
        Group {
            if let notice = chatHostNotice(missing: ChatHostStarter.shared.missing) {
                EmptyStateView(icon: .warning, title: notice.title, line: notice.line).inPageScroll()
            } else if let empty = page.emptyState {
                VStack(alignment: .leading, spacing: Tokens.Space.none) {
                    if filter.chips.isEmpty == false { chips.padding(.horizontal, Tokens.Space.s20).padding(.vertical, Tokens.Space.s8) }
                    EmptyStateView(state: empty, action: empty == .noSessionsMatch ? (Copy.sessionsClearFilters(), clear) : nil)
                }
                .inPageScroll()
            } else {
                // the scroll view is the page, so the list runs up under the toolbar as Carrier's does and the bar is the system's
                let ids = page.groups.flatMap { $0.rows.map(\.id) }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: Tokens.Space.s2) {
                            if filter.chips.isEmpty == false { chips.padding(.horizontal, Tokens.Space.s8).padding(.bottom, Tokens.Space.s8) }
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
                        .padding(.horizontal, Tokens.Space.s12).padding(.vertical, Tokens.Space.s8)
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

    /// What the toolbar carries (the window's title and count are `PanelView`'s): Search and Filter in one glass pill, New session apart,
    /// as the primary action. Both are drawn here at 28 pt with the glass material on their own shape: the toolbar's own glass is taller than
    /// these labels need and cannot be made smaller.
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: Tokens.Space.none) {
                searchItem
                filterItem
            }
            .glassEffect(.regular, in: .capsule)
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) {
            AccentGlassPillButton(title: Copy.sessionsNew(), icon: .plus, action: newSession)
                .padding(.trailing, Tokens.Space.s10)
                .help(Copy.sessionsNew())
        }
        .sharedBackgroundVisibility(.hidden)
    }

    @ViewBuilder private var searchItem: some View {
        ToolbarSearchField(query: $query, placeholder: Copy.sessionsSearch(), focused: $searching)
    }

    private var filterItem: some View {
        ToolbarPillButton(title: Copy.sessionsFilter(), icon: .filter, badge: filter.count) { filterOpen.toggle() }
            .popover(isPresented: $filterOpen, arrowEdge: .bottom) {
                SessionFilterPopover(sort: $sort, filter: $filter, agents: Set(sessions.rows.map(\.agent)).sorted())
            }
    }

    private var chips: some View {
        FlowLayout(spacing: Tokens.Space.s6) {
            ForEach(filter.chips, id: \.self) { chip in
                Button { filter.remove(chip) } label: {
                    HStack(spacing: Tokens.Space.s4) {
                        Text(chip.title())
                        Glyph(.close, size: 8)
                    }
                    .font(.caption.weight(.medium)).foregroundStyle(.white)
                    .padding(.horizontal, Tokens.Space.s10).padding(.vertical, Tokens.Space.s3).background(Capsule().fill(.tint))
                }
                .buttonStyle(.plain).accessibilityLabel(Copy.sessionsRemoveFilter(name: chip.title()))
            }
            Button(Copy.sessionsClearFilters(), action: clear).buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func groupHeader(_ group: SessionGroup) -> some View {
        HStack(spacing: Tokens.Space.s6) {
            Text(group.title).font(.callout.weight(.semibold))
            Text(Copy.sessionsCount(count: group.rows.count)).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, Tokens.Space.s8).padding(.top, Tokens.Space.s14).padding(.bottom, Tokens.Space.s4)
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
        VStack(alignment: .leading, spacing: Tokens.Space.s4) {
            heading(Copy.sessionsSortBy())
            ForEach(SessionSort.allCases, id: \.self) { option in
                Button { sort = option } label: {
                    HStack {
                        Text(option.title)
                        Spacer(minLength: 0)
                        if sort == option { Glyph(.check) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityAddTraits(sort == option ? .isSelected : [])
            }
            Divider().padding(.vertical, Tokens.Space.s4)
            heading(Copy.sessionsFilterShow())
            ForEach(SessionFilter.offeredStatuses, id: \.self) { Toggle($0.title(), isOn: ticked(\.statuses, $0)) }
            if agents.isEmpty == false {
                Divider().padding(.vertical, Tokens.Space.s4)
                heading(Copy.sessionsFilterAgent())
                ForEach(agents, id: \.self) { Toggle($0, isOn: ticked(\.agents, $0)) }
            }
            if filter.count > 0 {
                Divider().padding(.vertical, Tokens.Space.s4)
                Button(Copy.sessionsClearFilters()) { filter = SessionFilter() }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(Tokens.Space.s12)
        .frame(width: 220)
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
    }
}

extension SessionSort {
    var title: String {
        switch self {
        case .workspace: Copy.sessionSortWorkspace()
        case .age: Copy.sessionSortAge()
        case .status: Copy.sessionSortStatus()
        }
    }
}

/// A wide row of the Sessions home: the project's icon (the session's state is on it, as in the sidebar: violet while it works, cyan while it waits
/// for something it started), the title with the workspace as a tag outside the workspace order, what the agent last wrote under it (or what the
/// session waits for), and a line of where it works, how many turns it took, the model and its pull request with the lines it changed. On the
/// right what the sidebar's row has in the place of the time (`SessionTimeLabel`) over the providers; under the pointer they give way to Pin and
/// Archive. An archived match is dimmed and tagged.
private struct SessionHomeRow: View {
    private let timeChanges = TimeFormatChanges()
    let row: SessionRow
    let showsWorkspace: Bool
    let highlighted: Bool
    let filterWorkspace: (String) -> Void
    let open: () -> Void
    @State private var hovered = false
    @Environment(SessionActions.self) private var actions
    @Environment(\.textScale) private var textScale
    @AppStorage(Preference.sidebarPinned) private var pinnedStored

    private var pinned: Bool { pinnedIds(pinnedStored).contains(row.id) }

    var body: some View {
        let active = hovered || highlighted
        HStack(alignment: .top, spacing: Tokens.Space.s12) {
            ProjectIcon(base: row.base, name: row.workspace, colorKey: projectColorKey(row.base), working: row.isWorking, background: row.isWorking && row.state != .working)
                .environment(\.rowActive, active)
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                HStack(spacing: Tokens.Space.s6) {
                    if pinned { Glyph(.pinFilled, size: 10, label: Copy.sessionPinned()).foregroundStyle(.secondary) }
                    Text(row.title).scaledFont(13, weight: .medium).lineLimit(1).truncationMode(.tail)
                    if showsWorkspace { RowTag(text: row.workspace) }
                    if row.archived { RowTag(text: Copy.sessionArchivedTag()) }
                }
                status
                meta
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: Tokens.Space.s6) {
                SessionTimeLabel(row: row, age: timeText(row.updatedAt, now: Date(), format: timeChanges.format)).scaledFont(12).monospacedDigit().lineLimit(1)
                ProviderMarks(names: row.providers)
            }
            .opacity(active ? 0 : 1)
        }
        // Pin and Archive take the place of the age and the providers, centred on the row's right edge
        .overlay(alignment: .trailing) { actionButtons.opacity(active ? 1 : 0).allowsHitTesting(active) }
        .animation(.easeInOut(duration: 0.15), value: active)
        .opacity(row.archived ? 0.55 : 1)
        .padding(.horizontal, Tokens.Space.s10).padding(.vertical, Tokens.Space.s8)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.card).fill(active ? Color.primary.opacity(0.07) : .clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .onHover { hovered = $0 }
        .sessionContextMenu(row, filterWorkspace: filterWorkspace, inWindow: true)
        .help(row.title)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Copy.sessionOpen(), open)
    }

    /// What the session is doing, or the last thing the agent said.
    @ViewBuilder private var status: some View {
        if let waiting = row.waitingOn() {
            Text(waiting).foregroundStyle(Color.backgroundWork).font(.callout).lineLimit(1).truncationMode(.tail)
        } else {
            switch row.state {
            case .waiting: Text(Copy.sessionWaitingForYou()).fontWeight(.medium).foregroundStyle(SessionRowView.attention).font(.callout)
            case .working: Text(Copy.sessionWorking()).foregroundStyle(Color.thought).font(.callout)
            case .idle, .done:
                if let message = row.lastMessage {
                    Text(message).foregroundStyle(.secondary).font(.callout).lineLimit(1).truncationMode(.tail)
                } else if row.reportsActivity {
                    Text(Copy.sessionNoReplyYet()).foregroundStyle(.tertiary).font(.callout)
                }
            }
        }
    }

    /// Where it works (a branch in monospace), how many turns it took, the model of the last, and its pull request with the lines it changed.
    private var meta: some View {
        HStack(spacing: Tokens.Space.s6) {
            Group {
                if let branch = row.branch {
                    Text("\(Image(inline: .gitBranch)) \(Text(branch).font(textScale.font(11, design: .monospaced)))").lineLimit(1).truncationMode(.middle)
                } else {
                    Label(Copy.sessionBaseFolder(), icon: .folder).labelStyle(.titleAndIcon).lineLimit(1)
                }
                if row.turns > 0 { Text("·"); Text(Copy.sessionTurns(count: row.turns)) }
                if let model = TurnSummary(model: row.model).shortModel { Text("·"); Text(model) }
            }
            .font(.caption).foregroundStyle(.tertiary)
            if let pullRequest = row.pullRequest { SessionPullRequestChip(pr: pullRequest).padding(.leading, Tokens.Space.s4) }
            if let diff = row.diff { DiffText(diff: diff) }
        }
        .lineLimit(1)
    }

    private var actionButtons: some View {
        HStack(spacing: Tokens.Space.s4) {
            RowIconButton(symbol: pinned ? .pinOff : .pin, title: pinned ? Copy.sessionUnpin() : Copy.sessionPin(), selected: pinned) {
                let ids = pinnedIds(pinnedStored)
                pinnedStored = storedPins(pinned ? ids.subtracting([row.id]) : ids.union([row.id]))
            }
            if row.archived {
                RowIconButton(symbol: .undo, title: Copy.sessionRestore()) { Task { if let refusal = await actions.restore(row.id) { tell(refusal) } } }
            } else {
                RowIconButton(symbol: .archive, title: Copy.sessionArchive(), why: archiveBlock(row)) { Task { if let refusal = await archiveAsking(row, actions) { tell(refusal) } } }
            }
        }
    }
}
