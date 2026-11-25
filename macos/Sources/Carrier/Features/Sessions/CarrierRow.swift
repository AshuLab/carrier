import CarrierCore
import SwiftUI

/// The Carrier section: its name and the engine's state as a pill with the search and the grouping menu, and its slots as bars under
/// them, nothing else; the epics follow it. Choosing it shows the Carrier home. Hovering it shows when the next check
/// is, the uptime and the rate limit.
struct CarrierRow: View {
    @ObservedObject private var start = StartController.shared
    let state: ConnectionState?
    let selected: Bool
    /// Folded, the row is its state and slots; unfolded, it also has the search and the grouping menu, and the epics follow.
    let unfolded: Bool
    /// Without epics there is nothing to search, so the magnifier is dimmed.
    let hasEpics: Bool
    let select: () -> Void
    @Binding var groupBy: GroupBy
    /// Whether the search field is open under the row; the list owns the field.
    @Binding var searching: Bool
    @State private var groupMenu = false

    var body: some View {
        let card = carrierCardState(state, lastTotal: SidebarStore().slotsTotal)
        let snapshot: PanelSnapshot? = if case .running(let snapshot)? = state { snapshot } else { nil }
        // the hover: running says when the next check is, uptime and rate limit; an incompatible engine says why
        let detail: String? = if let snapshot { Self.hover(snapshot) } else if case .incompatible(let update)? = state { update ?? state?.menuLine } else { nil }
        SidebarSectionRow(title: "Carrier", icon: .send, selected: selected, keepActions: groupMenu || searching, action: select, actions: {
            Text(card.title)
                .sidebarFont(.detail, weight: .semibold)
                .foregroundStyle(Self.tint(card.kind))
                .padding(.horizontal, Tokens.Space.s8).padding(.vertical, Tokens.Space.s2)
                .background(Capsule().fill(Self.tint(card.kind).opacity(0.28)))
        }, hoverActions: {
            // the epics exist only while Carrier answers, so there is nothing to search or group before
            if snapshot != nil && unfolded {
                IconButton(
                    icon: .search, name: searching ? "Close epic search" : "Search epics", enabled: hasEpics, why: "No epics to search",
                    shortcut: "⌘F", pressed: searching
                ) {
                    searching.toggle()
                }
                IconButton(icon: .dots, name: "Group epics by") { groupMenu = true }
                    .popover(isPresented: $groupMenu, arrowEdge: .trailing) {
                        ChoiceMenu(
                            title: "Group by", options: GroupBy.allCases.map { ($0.title, $0) }, selection: $groupBy,
                            close: { groupMenu = false }
                        )
                    }
            }
        }, below: {
            if state == .stopped, let notice = engineNotConfiguredNotice(configExists: start.configExists) {
                // a line limit, so the height this asks for has a ceiling: measured at no width, wrapped text wants a line per word, and the
                // foot of the sidebar then asked for more than the window had and pushed the rows above and under it out of sight
                Text(notice).font(.caption).foregroundStyle(.orange).lineLimit(4).fixedSize(horizontal: false, vertical: true).help(notice)
            }
            if let slots = card.slots {
                HStack(spacing: Tokens.Space.s8) {
                    SegmentedProgress(done: slots.busy, total: slots.total, tint: Self.tint(card.kind))
                    Text("\(slots.busy)/\(slots.total)").scaledFont(11).monospacedDigit().foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(slots.busy) of \(slots.total) slots busy")
            }
        })
        .help(([detail, "Carrier (⌘3)"].compactMap { $0 }).joined(separator: "\n"))
        // remembered so a stopped engine, even after a relaunch, still draws its slots
        .onChange(of: snapshot?.slots.total, initial: true) { if let total = snapshot?.slots.total { SidebarStore().slotsTotal = total } }
    }

    private static func tint(_ kind: CarrierCardState.Kind) -> Color {
        switch kind {
        case .running: .green
        case .paused, .problem: .orange
        case .idle, .stopped, .connecting: .gray
        }
    }

    private static func hover(_ snapshot: PanelSnapshot) -> String {
        let box = carrierBox(snapshot)
        return ([box.uptime] + box.rows.map { "\($0.label): \($0.value)" }).joined(separator: " · ")
    }
}

extension GroupBy {
    var title: String { self == .status ? "Status" : "Repository" }
}

/// A popover of choices, one ticked; choosing one closes it.
struct ChoiceMenu<Value: Hashable>: View {
    let title: String
    let options: [(title: String, value: Value)]
    @Binding var selection: Value
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, Tokens.Space.s8).padding(.bottom, Tokens.Space.s2)
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                Button {
                    selection = option.value
                    close()
                } label: {
                    HStack {
                        Text(option.title)
                        Spacer(minLength: 0)
                        if selection == option.value { Glyph(.check) }
                    }
                    .padding(.horizontal, Tokens.Space.s8).padding(.vertical, Tokens.Space.s4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option.value ? .isSelected : [])
            }
        }
        .padding(Tokens.Space.s8)
        .frame(width: 160)
    }
}
