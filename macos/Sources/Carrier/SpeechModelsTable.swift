import CarrierCore
import SwiftUI

/// The speech models of the Dictation page, in the columns of the design (`dictation-settings-spec.html`): a radio on the downloaded rows, the
/// name over its recognizer and its licence (a link to the model's card), the size, the languages, how the text appears and the action of the
/// row's state. What each row shows and offers is `speechModelRows`; this only draws it.
struct SpeechModelsTable: View {
    let rows: [SpeechModelRow]
    let choose: (String) -> Void
    let download: (String) -> Void
    let cancel: (String) -> Void
    let delete: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Color.clear.frame(width: 20)
                Text("MODEL").frame(maxWidth: .infinity, alignment: .leading)
                Text("SIZE").frame(width: 64, alignment: .leading)
                Text("LANGUAGES").frame(width: 150, alignment: .leading)
                Text("TEXT APPEARS").frame(width: 104, alignment: .leading)
                Color.clear.frame(width: 158)
            }
            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 8)
            .accessibilityHidden(true)
            ForEach(rows) { row in
                Divider()
                SpeechModelRowView(row: row, choose: choose, download: download, cancel: cancel, delete: delete)
            }
        }
        .padding(.bottom, 4)
    }
}

private struct SpeechModelRowView: View {
    let row: SpeechModelRow
    let choose: (String) -> Void
    let download: (String) -> Void
    let cancel: (String) -> Void
    let delete: (String) -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            radio.frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.name).font(.body.weight(.medium))
                HStack(spacing: 0) {
                    Text("\(row.recognizer) · ").foregroundStyle(.secondary)
                    Link(row.licence, destination: row.card).help("Open the card of \(row.name)")
                }
                .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.size).font(.callout).monospacedDigit().frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.languages).font(.callout)
                if row.detectsLanguage { Text("Detects the language").font(.caption).foregroundStyle(.secondary) }
            }
            .frame(width: 150, alignment: .leading)
            StatusChip(text: row.text, tint: row.text == "Live" ? Color.themeAccent : .secondary).frame(width: 104, alignment: .leading)
            action.frame(width: 158, alignment: .trailing)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(fill))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { if row.radio != nil { choose(row.id) } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(row.label)
        .accessibilityAddTraits(row.radio == true ? .isSelected : [])
    }

    private var fill: Color {
        row.radio == true ? Color.themeAccent.opacity(0.22) : hovering && row.radio != nil ? Color.secondary.opacity(0.14) : .clear
    }

    @ViewBuilder private var radio: some View {
        if let chosen = row.radio {
            Button { choose(row.id) } label: {
                Image(systemName: chosen ? "largecircle.fill.circle" : "circle").foregroundStyle(chosen ? Color.themeAccent : .secondary)
            }
            .buttonStyle(.plain).accessibilityLabel("Use \(row.name)")
        }
    }

    @ViewBuilder private var action: some View {
        switch row.action {
        case .download(let size):
            Button("Download · \(size)") { download(row.id) }.buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
        case .downloading(let percent):
            HStack(spacing: 6) {
                ProgressView(value: Double(percent), total: 100).tint(Color.themeAccent)
                Text("\(percent)%").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Button { cancel(row.id) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).help("Cancel").accessibilityLabel("Cancel the download of \(row.name)")
            }
        case .failed(let cause):
            VStack(alignment: .trailing, spacing: 2) {
                Text(cause).font(.caption).foregroundStyle(.red).multilineTextAlignment(.trailing)
                Button("Retry") { download(row.id) }.buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
            }
        case .delete:
            Button { delete(row.id) } label: { Image(systemName: "trash").foregroundStyle(.secondary) }
                .buttonStyle(.plain).help("Delete").accessibilityLabel("Delete \(row.name)")
        case .none:
            EmptyView()
        }
    }
}
