import SwiftUI

/// One value a select offers.
struct SelectChoice: Identifiable {
    let id: String
    let label: String
    var detail: String?
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
    var choices: [SelectChoice] = []
    var choose: (String) -> Void = { _ in }
    @State private var open = false

    private var rows: [SelectChoice] { choices.isEmpty ? [SelectChoice(id: "", label: "Default", detail: "The provider's own setting.")] : choices }
    private var chosen: SelectChoice? { rows.first { $0.id == (selected ?? "") } }

    var body: some View {
        Button { open.toggle() } label: {
            Text(showsValue ? (chosen?.label ?? title) : (selected == nil ? title : chosen?.label ?? title)).fontWeight(.medium)
                .padding(.leading, 18).padding(.trailing, 15)
                .overlay(alignment: .leading) { Image(systemName: icon).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary) }
                .overlay(alignment: .trailing) { Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary) }
                .font(.callout).lineLimit(1)
                .padding(.horizontal, 10).frame(height: controlHeight)
                .controlSurface()
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain).help(title).accessibilityLabel("\(title): \(chosen?.label ?? "Default")")
        .popover(isPresented: $open, arrowEdge: .top) { list }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.vertical, 4)
            ForEach(rows) { row in
                let ticked = row.id == (selected ?? "")
                HoverRow(action: { choose(row.id); open = false }, fill: ticked ? Color.accentColor.opacity(0.14) : nil) { _ in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.label).fontWeight(.medium)
                            if let detail = row.detail { Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                        }
                        Spacer(minLength: 8)
                        if ticked { Image(systemName: "checkmark").foregroundStyle(Color.accentColor).accessibilityLabel("Chosen") }
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
        .padding(8).frame(width: 260)
    }
}
