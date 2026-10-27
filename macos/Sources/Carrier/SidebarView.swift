import CarrierCore
import SwiftUI

/// The sidebar's list: the Home row, the group-by switch, the epics in groups; the Carrier card and Settings at the bottom.
struct SidebarView: View {
    let snapshot: PanelSnapshot?
    let state: ConnectionState?
    let sessions: Sessions
    @Binding var selection: Selection
    @Binding var groupBy: GroupBy
    @Binding var collapse: SidebarCollapse
    @State private var sessionsOpen = true

    var body: some View {
        let list = Binding<Selection?>(get: { selection }, set: { if let next = $0 { selection = next } })
        List(selection: list) {
            Label("Home", systemImage: "house").tag(Selection.home)
            SessionsRows(sessions: sessions, open: $sessionsOpen)
            if snapshot != nil {
                // how the sections below are grouped: there is nothing to group while Carrier is not answering
                UnderlineTabs(
                    items: [
                        .init(id: GroupBy.status, title: "Status", icon: "rectangle.3.group"),
                        .init(id: GroupBy.repo, title: "Repository", icon: "shippingbox"),
                    ],
                    selection: $groupBy, fill: true
                )
                .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 10, trailing: 0))
                .listRowSeparator(.hidden)
                .selectionDisabled()
            }
            if let snapshot {
                let groups = sidebarGroups(snapshot, by: groupBy)
                ForEach(groups.indices, id: \.self) { index in
                    let group = groups[index]
                    let expanded = Binding(
                        get: { !collapse.isCollapsed(group, by: groupBy) }, set: { _ in collapse.toggle(group, by: groupBy) }
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
            VStack(spacing: 2) {
                CarrierCard(state: state, selected: selection == .carrier) { selection = .carrier }.padding(.bottom, 6)
                SidebarFooterRow(title: "Settings", icon: "gearshape", selected: selection == .settings) { selection = .settings }
            }
            .padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 10)
            // opaque enough that the list scrolls under it without showing through
            .background(.regularMaterial)
            .overlay(alignment: .top) { Divider() }
        }
    }
}

/// The Carrier card at the sidebar's foot: the engine's state as a pill, its slots as bars and what is waiting as counters, on a
/// plain grey fill. Choosing it shows the Carrier home. Hovering it shows when the next check is, the uptime and the rate limit.
private struct CarrierCard: View {
    let state: ConnectionState?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let card = carrierCardState(state)
        let snapshot: PanelSnapshot? = if case .running(let snapshot)? = state { snapshot } else { nil }
        VStack(alignment: .leading, spacing: 8) {
            Text(card.title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Capsule().fill(Self.tint(card.kind).opacity(0.18)))
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
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(selected ? 0.2 : 0.1)))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture(perform: action)
        .help(snapshot.map(Self.hover) ?? "")
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, action)
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
