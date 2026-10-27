import CarrierCore
import SwiftUI

/// The sidebar's list: the Home row, Sessions, then the Carrier card with the epics in groups under it; Settings at the bottom.
struct SidebarView: View {
    let snapshot: PanelSnapshot?
    let state: ConnectionState?
    let sessions: Sessions
    @Binding var selection: Selection
    /// Which of Sessions and the Carrier card is unfolded, nil when both are folded.
    @Binding var open: OpenSection?
    @Binding var groupBy: GroupBy
    @Binding var collapse: SidebarCollapse
    /// The last ⌘F, for the open section to show its search.
    let searchRequest: SearchRequest?
    /// The card's search: not remembered between launches.
    @State private var searching = false
    @State private var query = ""

    var body: some View {
        let list = Binding<Selection?>(get: { selection }, set: { if let next = $0 { selection = next } })
        List(selection: list) {
            Label("Home", systemImage: "house").tag(Selection.home).help("Home (⌘1)")
            SessionsRows(sessions: sessions, open: Binding(get: { open == .sessions }, set: { open = $0 ? .sessions : nil }), searchRequest: searchRequest)
            // its own row, outside Sessions, so folding Sessions does not hide it
            let archived = archivedCount(sessions.rows)
            HStack {
                Label("Archive", systemImage: "archivebox")
                Spacer(minLength: 0)
                Text("\(archived)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Archive, \(archived)")
            .tag(Selection.archive)
            CarrierCard(state: state, selected: selection == .carrier, unfolded: open == .carrier, searchRequest: searchRequest, groupBy: $groupBy, searching: $searching, query: $query)
                .tag(Selection.carrier)
                // the list does not call its setter when the selected row is clicked again, so a folded card opens from here, beside the list's own click
                // selected, the card's fill is clear, which the tap would not hit: give it a shape
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded { open = .carrier })
                .listRowBackground(Color.clear)
            if let snapshot, open == .carrier {
                let groups = sidebarGroups(snapshot, by: groupBy, query: query)
                if groups.isEmpty && query.isEmpty == false {
                    Text("No epics match").foregroundStyle(.secondary).selectionDisabled()
                }
                ForEach(groups.indices, id: \.self) { index in
                    let group = groups[index]
                    let expanded = Binding(
                        get: { !collapse.isCollapsed(group, by: groupBy, query: query) },
                        // while a query is typed every group is open, so there is nothing to toggle
                        set: { _ in if query.isEmpty { collapse.toggle(group, by: groupBy) } }
                    )
                    Section(isExpanded: expanded) {
                        ForEach(group.rows, id: \.selection) { SidebarRowView(row: $0).tag($0.selection) }
                    } header: {
                        Text(group.title).textCase(.uppercase)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 220, ideal: 268, max: 320)
        .safeAreaInset(edge: .bottom) {
            SidebarFooterRow(title: "Settings", icon: "gearshape", selected: selection == .settings) { selection = .settings }
                .padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 10)
                // opaque enough that the list scrolls under it without showing through
                .background(.regularMaterial)
                .overlay(alignment: .top) { Divider() }
        }
    }
}

/// The Carrier card, a row of the list: the engine's state as a pill with the search and the grouping menu, its slots as bars and
/// what is waiting as counters, on a plain grey fill; the epics follow it. Choosing it shows the Carrier home. Hovering it shows when
/// the next check is, the uptime and the rate limit.
private struct CarrierCard: View {
    let state: ConnectionState?
    let selected: Bool
    /// Folded, the card is its state, slots and counters; unfolded, it also has the search and the grouping menu, and the epics follow.
    let unfolded: Bool
    /// The last ⌘F: when it asks for the card, the search field opens and takes the keyboard.
    let searchRequest: SearchRequest?
    @Binding var groupBy: GroupBy
    @Binding var searching: Bool
    @Binding var query: String
    @State private var groupMenu = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        let card = carrierCardState(state)
        let snapshot: PanelSnapshot? = if case .running(let snapshot)? = state { snapshot } else { nil }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(card.title)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(Self.tint(card.kind).opacity(0.18)))
                Spacer(minLength: 0)
                // the epics exist only while Carrier answers, so there is nothing to search or group before
                if snapshot != nil && unfolded {
                    IconButton(icon: "magnifyingglass", name: searching ? "Close epic search" : "Search epics", shortcut: "⌘F") {
                        searching.toggle()
                        if searching { searchFocused = true } else { query = "" }
                    }
                    IconButton(icon: "ellipsis", name: "Group epics by") { groupMenu = true }
                        .popover(isPresented: $groupMenu, arrowEdge: .trailing) { GroupByMenu(groupBy: $groupBy, close: { groupMenu = false }) }
                }
            }
            if searching && unfolded {
                TextField("Search epics", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .onKeyPress(.escape) {
                        searching = false
                        query = ""
                        return .handled
                    }
                    .accessibilityLabel("Search epics")
            }
            if let slots = card.slots {
                VStack(alignment: .leading, spacing: 4) {
                    SegmentedProgress(done: slots.busy, total: slots.total, tint: Self.tint(card.kind))
                    Text("\(slots.busy) of \(slots.total) slots busy").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(slots.busy) of \(slots.total) slots busy")
            }
            if card.kind == .stopped {
                Text("Start Carrier to run epics").font(.caption).foregroundStyle(.secondary)
            } else if let snapshot {
                let counters = carrierCounters(snapshot)
                FlowLayout(spacing: 10) {
                    if counters.needsYou > 0 { Counter(count: counters.needsYou, word: "needs you", color: .orange) }
                    Counter(count: counters.running, word: "running", color: .green)
                    Counter(count: counters.next, word: "next", color: .gray)
                    Counter(count: counters.ready, word: "ready", color: .blue)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        // the list draws its own pill under a chosen row, so the grey is only for the card at rest
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(selected ? 0 : 0.1)))
        .help(([snapshot.map(Self.hover), "Carrier (⌘3)"].compactMap { $0 }).joined(separator: "\n"))
        .onChange(of: searchRequest) {
            if searchRequest?.section == .carrier && snapshot != nil && unfolded {
                searching = true
                searchFocused = true
            }
        }
    }

    private static func tint(_ kind: CarrierCardState.Kind) -> Color {
        switch kind {
        case .running: .green
        case .paused, .problem: .orange
        case .stopped, .connecting: .gray
        }
    }

    private static func hover(_ snapshot: PanelSnapshot) -> String {
        let box = carrierBox(snapshot)
        return ([box.uptime] + box.rows.map { "\($0.label): \($0.value)" }).joined(separator: " · ")
    }

    /// A dot and a word; the number is part of the word, so it reads aloud as "2 running".
    private struct Counter: View {
        let count: Int
        let word: String
        let color: Color

        var body: some View {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 6, height: 6).accessibilityHidden(true)
                Text("\(count) \(word)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }
}

/// A 22-point plain button with an accessible name and a tooltip. In a list row it runs its action and does not select the row.
private struct IconButton: View {
    let icon: String
    let name: String
    var shortcut: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon).frame(width: 22, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(name + (shortcut.map { " (\($0))" } ?? ""))
        .accessibilityLabel(name)
    }
}

/// The popover of the three dots: how the epics are grouped, one ticked.
private struct GroupByMenu: View {
    @Binding var groupBy: GroupBy
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Group by").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.bottom, 2)
            choice("Status", .status)
            choice("Repository", .repo)
        }
        .padding(8)
        .frame(width: 160)
    }

    private func choice(_ title: String, _ value: GroupBy) -> some View {
        Button {
            groupBy = value
            close()
        } label: {
            HStack {
                Text(title)
                Spacer(minLength: 0)
                if groupBy == value { Image(systemName: "checkmark") }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(groupBy == value ? .isSelected : [])
    }
}

/// A row of the sidebar's foot, drawn like a list row: padded, with the whole width as its target and a fill when chosen or hovered.
private struct SidebarFooterRow: View {
    let title: String
    let icon: String
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(.primary.opacity(selected ? 0.12 : hovered ? 0.06 : 0)))
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

struct SidebarRowView: View {
    let row: SidebarRow

    var body: some View {
        HStack(spacing: 12) {
            StateGlyph(state: row.state, attention: row.attention)
            VStack(alignment: .leading, spacing: 5) {
                // two lines before the ellipsis: a title is a sentence, and the number no longer takes room from it
                Text(row.title ?? row.name).font(.system(size: 12)).lineLimit(2)
                StateAndRepo {
                    // the number comes first so that, when the state is long, the tail is what gets cut
                    Text("\(Text("#\(row.issue) · ").foregroundStyle(.secondary))\(Text(row.detail).foregroundStyle(row.attention?.color ?? .secondary))")
                        .font(.caption).monospacedDigit().lineLimit(1).truncationMode(.tail)
                    if let repo = row.repoLabel {
                        HStack(spacing: 3) {
                            GitHubMark.image.renderingMode(.template).resizable().scaledToFit().frame(width: 10, height: 10)
                            Text(repo).lineLimit(1).truncationMode(.tail)
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .help(row.tooltip)
    }
}

/// The state on the left and, when there is one, the repository on the right. The state keeps what it needs; the repository takes
/// at most half of the line and gives way first.
private struct StateAndRepo: Layout {
    /// The least space between the state and the repository.
    static let gap: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return CGSize(width: proposal.width ?? sizes.map(\.width).reduce(0, +), height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let state = subviews.first else { return }
        let stateWidth = min(state.sizeThatFits(.unspecified).width, bounds.width)
        state.place(at: bounds.origin, proposal: ProposedViewSize(width: stateWidth, height: bounds.height))
        guard subviews.count > 1 else { return }
        let repo = subviews[1]
        let repoWidth = max(0, min(repo.sizeThatFits(.unspecified).width, bounds.width / 2, bounds.width - stateWidth - Self.gap))
        repo.place(
            at: CGPoint(x: bounds.maxX - repoWidth, y: bounds.minY), proposal: ProposedViewSize(width: repoWidth, height: bounds.height)
        )
    }
}
