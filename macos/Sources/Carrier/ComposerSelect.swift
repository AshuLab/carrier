import CarrierCore
import SwiftUI

/// One value a select offers.
struct SelectChoice: Identifiable {
    let id: String
    let label: String
    var detail: String?
    /// The SF Symbol in front of it.
    var icon: String?
    /// What it stands for exactly (a model's number), as a small mark next to its name.
    var version: String?
    var enabled = true
}

/// A select of the message box: its icon and its value (or its name while the value is the provider's default), and a list of the
/// choices that opens under it with the chosen one ticked. A select with no choices of its own offers "Default" and says what it
/// will hold, so it is never a dead control.
struct ComposerSelect: View {
    let title: String
    let icon: String
    var note: String?
    var selected: String?
    /// Whether the pill says the chosen value even when it is the default one (the provider always does).
    var showsValue = false
    /// A value that cannot change here (the provider of a session that already started): no chevron, no list.
    var locked = false
    var choices: [SelectChoice] = []
    var choose: (String) -> Void = { _ in }
    @State private var open = false

    private var rows: [SelectChoice] { choices.isEmpty ? [SelectChoice(id: "", label: "Default", detail: "The provider's own setting.")] : choices }
    private var chosen: SelectChoice? { rows.first { $0.id == (selected ?? "") } }

    var body: some View {
        Button { open.toggle() } label: {
            Text(showsValue ? (chosen?.label ?? title) : (selected == nil ? title : chosen?.label ?? title)).fontWeight(.medium)
                .padding(.leading, 18).padding(.trailing, locked ? 0 : 15)
                .overlay(alignment: .leading) { Image(systemName: icon).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary) }
                .overlay(alignment: .trailing) { if locked == false { Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary) } }
                .font(.callout).lineLimit(1).truncationMode(.tail)
                .padding(.horizontal, 10).frame(height: controlHeight)
                .controlSurface()
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain).disabled(locked)
        // its own width, up to 220: asked for its ideal size the frame answers with the smaller of the two, where on its own it would grow
        .frame(maxWidth: 220).fixedSize(horizontal: true, vertical: false)
        .help(locked ? "\(title) is fixed once a session has started" : title).accessibilityLabel("\(title): \(chosen?.label ?? "Default")")
        .popover(isPresented: $open, arrowEdge: .top) { list }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: icon).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 6)
            ForEach(rows) { row in
                let ticked = row.id == (selected ?? "")
                HoverRow(action: { choose(row.id); open = false }, fill: ticked ? Color.accentColor.opacity(0.16) : nil) { _ in
                    HStack(alignment: .center, spacing: 10) {
                        if let rowIcon = row.icon {
                            Image(systemName: rowIcon)
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(ticked ? Color.accentColor : .secondary)
                                .frame(width: 26, height: 26)
                                .background(RoundedRectangle(cornerRadius: 7).fill(ticked ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12)))
                                .accessibilityHidden(true)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(row.label).fontWeight(.medium)
                                if let version = row.version {
                                    Text(version).font(.caption.monospaced()).foregroundStyle(.secondary)
                                        .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(Color.secondary.opacity(0.14)))
                                }
                            }
                            if let detail = row.detail {
                                Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 8)
                        if ticked { ChosenMark() }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                }
                .disabled(row.enabled == false)
            }
            if choices.isEmpty, let note {
                Label(note, systemImage: "info.circle").font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 4)
            }
        }
        .padding(8).frame(width: 320)
    }
}

/// One select per option an agent lists, in the order the draft has always had: the model, the reasoning, then what the agent may do
/// (permission mode, or approvals and sandbox). A function and not a view, so the selects are the row's own and the row wraps them.
@ViewBuilder func optionSelects(_ options: [ChatOption], choose: @escaping (String, String) -> Void) -> some View {
    ForEach(optionRows(options).sorted { optionRank($0.id) < optionRank($1.id) }) { row in
        ComposerSelect(
            title: row.label, icon: optionIcon(row.id), selected: row.choices.first { $0.ticked }?.id, showsValue: true,
            choices: row.choices.map { SelectChoice(id: $0.id, label: $0.label, detail: $0.detail, icon: $0.icon, version: $0.version) },
            choose: { choose(row.id, $0) }
        )
    }
}

private func optionRank(_ id: String) -> Int {
    switch id {
    case "model": 0
    case "effort": 1
    default: 2
    }
}

/// The icon of an option's select: what it is about, by the id the providers use.
private func optionIcon(_ id: String) -> String {
    switch id {
    case "model": "cpu"
    case "effort": "brain"
    case "permissionMode", "approvalPolicy", "sandbox": "lock.shield"
    default: "slider.horizontal.3"
    }
}
