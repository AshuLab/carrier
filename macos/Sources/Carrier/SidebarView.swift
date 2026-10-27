import CarrierCore
import SwiftUI

/// The sidebar's list: Home and Carrier rows, the group-by switch, the epics in groups, Settings at the bottom.
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
            Label("Carrier", systemImage: "square.grid.2x2").tag(Selection.carrier)
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
                SidebarStatus(state: state).padding(.bottom, 6)
                SidebarFooterRow(title: "Settings", icon: "gearshape", selected: selection == .settings) { selection = .settings }
            }
            .padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 10)
            // opaque enough that the list scrolls under it without showing through
            .background(.regularMaterial)
            .overlay(alignment: .top) { Divider() }
        }
    }
}

/// Whether Carrier runs, when it checks GitHub next and how many of its slots are busy: a card at the foot of the sidebar, so it
/// is in view on every screen. Hovering it shows how long it has been up and the rate limit.
private struct SidebarStatus: View {
    let state: ConnectionState?

    var body: some View {
        let status = sidebarStatus(state)
        HStack(spacing: 10) {
            Circle().fill(status.color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(status.title).fontWeight(.medium)
                if let detail = status.detail { Text(detail).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
            if let slots = status.slots {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(slots.text).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    SegmentedProgress(done: slots.busy, total: slots.total, tint: slots.color).frame(width: 40)
                }
                .help("\(slots.busy) of \(slots.total) slots in use")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.1)))
        .help(status.help)
        .accessibilityElement(children: .combine)
    }

    private typealias Slots = (text: String, busy: Int, total: Int, color: Color)

    private func sidebarStatus(_ state: ConnectionState?) -> (title: String, detail: String?, color: Color, help: String, slots: Slots?) {
        switch state {
        case .running(let snapshot)?:
            let box = carrierBox(snapshot)
            let help = ([box.uptime] + box.rows.dropFirst().map { "\($0.label): \($0.value)" }).joined(separator: " · ")
            let pill = sidebarPill(snapshot)
            let tone: Color = switch pill.tone {
            case .green: .green
            case .orange: .orange
            case .gray: .gray
            }
            let slots: Slots = (pill.text, snapshot.slots.busy, snapshot.slots.total, tone)
            if snapshot.paused { return ("Intake paused", nil, .orange, help, slots) }
            return ("Carrier running", nextCheckLine(snapshot), snapshot.problem == nil ? .green : .orange, help, slots)
        case .stopped?: return ("Carrier stopped", nil, .gray, "", nil)
        case .incompatible?: return (state?.menuLine ?? "", nil, .orange, "", nil)
        case nil: return ("Connecting…", nil, .gray, "", nil)
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
