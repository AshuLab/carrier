import CarrierCore
import SwiftUI

/// The sidebar's list: the Home row, Sessions, Archive, then Carrier with the epics in groups under it; Settings at the bottom. The five
/// are sidebar sections: the view draws their fill, so the list's own selection only ever marks a session or an epic.
struct SidebarView: View {
    let snapshot: PanelSnapshot?
    let state: ConnectionState?
    let sessions: Sessions
    @Binding var selection: Selection
    /// Which of Sessions and Carrier is unfolded, nil when both are folded.
    @Binding var open: OpenSection?
    @Binding var groupBy: GroupBy
    @Binding var collapse: SidebarCollapse
    /// The last ⌘F, for the open section to show its search.
    let searchRequest: SearchRequest?
    /// Carrier's search: not remembered between launches.
    @State private var searching = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        let list = Binding<Selection?>(get: { selection }, set: { if let next = $0 { selection = next } })
        List(selection: list) {
            SidebarSectionRow(title: "Home", icon: "house", selected: selection == .home, action: { selection = .home }).help("Home (⌘1)")
            SessionsRows(
                sessions: sessions, selected: selection == .sessions, select: { selection = .sessions },
                open: Binding(get: { open == .sessions }, set: { open = $0 ? .sessions : nil }), searchRequest: searchRequest
            )
            // its own row, outside Sessions, so folding Sessions does not hide it
            let archived = archivedCount(sessions.rows)
            SidebarSectionRow(title: "Archive", icon: "archivebox", selected: selection == .archive, action: { selection = .archive }, actions: {
                Text("\(archived)").font(.callout.monospacedDigit()).foregroundStyle(.secondary).accessibilityLabel("\(archived) archived")
            })
            CarrierRow(state: state, selected: selection == .carrier, unfolded: open == .carrier, select: { selection = .carrier }, groupBy: $groupBy, searching: $searching)
            if let snapshot, open == .carrier {
                // a row of its own, not selectable, so a click in the field does not select the card
                if searching {
                    TextField("Search epics", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .focused($searchFocused)
                        .onKeyPress(.escape) {
                            searching = false
                            return .handled
                        }
                        .selectionDisabled()
                        .flatSidebarRow()
                }
                let queried = query.trimmingCharacters(in: .whitespaces).isEmpty == false
                let groups = sidebarGroups(snapshot, by: groupBy, query: query)
                if groups.isEmpty && queried {
                    Text("No epics match").foregroundStyle(.secondary).selectionDisabled().flatSidebarRow()
                }
                ForEach(groups.indices, id: \.self) { index in
                    let group = groups[index]
                    let expanded = Binding(
                        get: { !collapse.isCollapsed(group, by: groupBy, query: query) },
                        // while a query is typed every group is open, so there is nothing to toggle
                        set: { _ in if queried == false { collapse.toggle(group, by: groupBy) } }
                    )
                    Section(isExpanded: expanded) {
                        ForEach(group.rows, id: \.selection) { SidebarRowView(row: $0).tag($0.selection).flatSidebarRow() }
                    } header: {
                        Text(group.title).textCase(.uppercase).flatSidebarRow()
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .onChange(of: searching) { if searching { searchFocused = true } else { query = "" } }
        .onChange(of: searchRequest) {
            if searchRequest?.section == .carrier && snapshot != nil && open == .carrier {
                searching = true
                searchFocused = true
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 268, max: 320)
        .safeAreaInset(edge: .bottom) {
            SidebarSectionRow(title: "Settings", icon: "gearshape", selected: selection == .settings, action: { selection = .settings })
                .padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 8)
                // opaque enough that the list scrolls under it without showing through
                .background(.regularMaterial)
                .overlay(alignment: .top) { Divider() }
        }
    }
}

/// The Carrier section: its name and the engine's state as a pill with the search and the grouping menu, its slots as bars and what
/// is waiting as counters under them; the epics follow it. Choosing it shows the Carrier home. Hovering it shows when the next check
/// is, the uptime and the rate limit.
private struct CarrierRow: View {
    let state: ConnectionState?
    let selected: Bool
    /// Folded, the row is its state, slots and counters; unfolded, it also has the search and the grouping menu, and the epics follow.
    let unfolded: Bool
    let select: () -> Void
    @Binding var groupBy: GroupBy
    /// Whether the search field is open under the row; the list owns the field.
    @Binding var searching: Bool
    @State private var groupMenu = false

    var body: some View {
        let card = carrierCardState(state)
        let snapshot: PanelSnapshot? = if case .running(let snapshot)? = state { snapshot } else { nil }
        // the hover: running says when the next check is, uptime and rate limit; an incompatible engine says why
        let detail: String? = if let snapshot { Self.hover(snapshot) } else if case .incompatible? = state { state?.menuLine } else { nil }
        SidebarSectionRow(title: "Carrier", icon: "paperplane", selected: selected, action: select, actions: {
            Text(card.title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Capsule().fill(Self.tint(card.kind).opacity(0.18)))
            // the epics exist only while Carrier answers, so there is nothing to search or group before
            if snapshot != nil && unfolded {
                IconButton(icon: "magnifyingglass", name: searching ? "Close epic search" : "Search epics", shortcut: "⌘F", pressed: searching) {
                    searching.toggle()
                }
                IconButton(icon: "ellipsis", name: "Group epics by") { groupMenu = true }
                    .popover(isPresented: $groupMenu, arrowEdge: .trailing) {
                        ChoiceMenu(
                            title: "Group by", options: [("Status", GroupBy.status), ("Repository", .repo)], selection: $groupBy,
                            close: { groupMenu = false }
                        )
                    }
            }
        }, below: {
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
        })
        .help(([detail, "Carrier (⌘3)"].compactMap { $0 }).joined(separator: "\n"))
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

/// A 22-point plain button with an accessible name and a tooltip; `why` is the tooltip and the hint while it is disabled. In a list
/// row it runs its action and does not select the row.
struct IconButton: View {
    let icon: String
    let name: String
    var enabled = true
    var why: String?
    /// Shown after the name in the tooltip.
    var shortcut: String?
    /// Drawn while what the button opened is open.
    var pressed = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon).frame(width: 22, height: 22).contentShape(Rectangle())
                .background(RoundedRectangle(cornerRadius: 5).fill(pressed ? Color.primary.opacity(0.15) : .clear))
        }
        .buttonStyle(.plain)
        .disabled(enabled == false)
        .help(enabled ? name + (shortcut.map { " (\($0))" } ?? "") : why ?? name)
        .accessibilityLabel(name)
        .accessibilityHint(enabled ? "" : why ?? "")
        .accessibilityAddTraits(pressed ? .isSelected : [])
    }
}

/// A popover of choices, one ticked; choosing one closes it.
struct ChoiceMenu<Value: Hashable>: View {
    let title: String
    let options: [(title: String, value: Value)]
    @Binding var selection: Value
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.bottom, 2)
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                Button {
                    selection = option.value
                    close()
                } label: {
                    HStack {
                        Text(option.title)
                        Spacer(minLength: 0)
                        if selection == option.value { Image(systemName: "checkmark") }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option.value ? .isSelected : [])
            }
        }
        .padding(8)
        .frame(width: 160)
    }
}

extension View {
    /// A row of the sidebar's list with the same small margin on both sides, so the fills of the section rows and of the rows under
    /// them line up and the list under a section has no margin of its own.
    func flatSidebarRow() -> some View {
        listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
    }
}

/// A sidebar section ([glossary](../../docs/glossary.md)): an icon of 15 points, a title and its actions, and under them whatever the
/// section shows of itself (Carrier's slots). No fill at rest, a faint grey on hover and a light neutral grey when selected, drawn here
/// and not by the list, so it covers this row and never what unfolds under it. A click anywhere on it, but on its actions, runs `action`.
struct SidebarSectionRow<Actions: View, Below: View>: View {
    let title: String
    let icon: String
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let actions: Actions
    @ViewBuilder let below: Below
    @State private var hovered = false
    @Environment(\.colorScheme) private var scheme

    init(
        title: String, icon: String, selected: Bool, action: @escaping () -> Void, @ViewBuilder actions: () -> Actions = { EmptyView() },
        @ViewBuilder below: () -> Below = { EmptyView() }
    ) {
        self.title = title
        self.icon = icon
        self.selected = selected
        self.action = action
        self.actions = actions()
        self.below = below()
    }

    var body: some View {
        // the greys of the exploration: 10% (12% dark) selected, 3% (5% dark) hovered
        let dark = scheme == .dark
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon).resizable().scaledToFit().frame(width: 15, height: 15)
                    .foregroundStyle(selected ? .primary : .secondary)
                Text(title).fontWeight(.medium)
                Spacer(minLength: 0)
                actions
            }
            .frame(minHeight: 20)
            below
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(.primary.opacity(selected ? (dark ? 0.12 : 0.1) : hovered ? (dark ? 0.05 : 0.03) : 0)))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture(perform: action)
        .onHover { hovered = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .listRowBackground(Color.clear)
        .flatSidebarRow()
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
        .padding(.horizontal, 2).padding(.vertical, 4)
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
