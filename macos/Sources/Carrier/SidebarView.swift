import CarrierCore
import SwiftUI

/// The sidebar's list: Overview with the pill and the group-by menu, the epics in groups, Settings and About at the bottom.
struct SidebarView: View {
    let snapshot: PanelSnapshot?
    @Binding var selection: Selection
    @Binding var groupBy: GroupBy
    let onAbout: () -> Void

    var body: some View {
        let list = Binding<Selection?>(get: { selection }, set: { if let next = $0 { selection = next } })
        List(selection: list) {
            HStack(spacing: 8) {
                Label("Overview", systemImage: "square.grid.2x2")
                Spacer(minLength: 4)
                if let snapshot { PillView(pill: sidebarPill(snapshot)) }
                Menu {
                    Picker("Group by", selection: $groupBy) {
                        Text("Status").tag(GroupBy.status)
                        Text("Repository").tag(GroupBy.repo)
                    }
                    .pickerStyle(.inline)
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Group by")
            }
            .tag(Selection.overview)
            if let snapshot {
                ForEach(sidebarGroups(snapshot, by: groupBy), id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.rows, id: \.selection) { SidebarRowView(row: $0).tag($0.selection) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 220, ideal: 268, max: 320)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 2) {
                SidebarFooterRow(title: "Settings", icon: "gearshape", selected: selection == .settings) { selection = .settings }
                SidebarFooterRow(title: "About", icon: "info.circle", selected: false, action: onAbout)
            }
            .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 10)
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

struct PillView: View {
    let pill: SidebarPill

    var body: some View {
        let color: Color = switch pill.tone {
        case .green: .green
        case .orange: .orange
        case .gray: .gray
        }
        Text(pill.text).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.22)))
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
