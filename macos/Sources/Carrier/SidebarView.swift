import CarrierCore
import SwiftUI

/// The sidebar's list: Overview with the pill and the group-by menu, the epics in groups, Settings and About at the bottom.
struct SidebarView: View {
    let snapshot: PanelSnapshot?
    let state: ConnectionState?
    @Binding var selection: Selection
    @Binding var groupBy: GroupBy
    let onAbout: () -> Void

    var body: some View {
        let list = Binding<Selection?>(get: { selection }, set: { if let next = $0 { selection = next } })
        List(selection: list) {
            Label("Overview", systemImage: "square.grid.2x2").tag(Selection.overview)
            // how the sections below are grouped, always in view
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
            if let snapshot {
                let groups = sidebarGroups(snapshot, by: groupBy)
                ForEach(groups.indices, id: \.self) { index in
                    Section {
                        ForEach(groups[index].rows, id: \.selection) { SidebarRowView(row: $0).tag($0.selection) }
                    } header: {
                        Text(groups[index].title).textCase(.uppercase)
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
                SidebarFooterRow(title: "About", icon: "info.circle", selected: false, action: onAbout)
            }
            .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 10)
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
        HStack(spacing: 8) {
            StateGlyph(state: row.state)
            VStack(alignment: .leading, spacing: 1) {
                SidebarRowTitle(name: row.name, issue: row.issue)
                Text(row.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
            }
        }
        .help(row.tooltip)
    }
}

/// The name cuts with an ellipsis; the number never does: it has layout priority.
struct SidebarRowTitle: View {
    let name: String
    let issue: Int

    var body: some View {
        HStack(spacing: 5) {
            Text(name).fontWeight(.semibold).lineLimit(1).truncationMode(.tail)
            Text("#\(issue)").foregroundStyle(.secondary).monospacedDigit().lineLimit(1).fixedSize().layoutPriority(1)
        }
    }
}
