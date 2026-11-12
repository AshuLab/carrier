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
                Text("Model").frame(maxWidth: .infinity, alignment: .leading)
                Text("Size").frame(width: 64, alignment: .leading)
                Text("Languages").frame(width: 150, alignment: .leading)
                Text("Text appears").frame(width: 104, alignment: .leading)
                Color.clear.frame(width: 170)
            }
            .sectionLabel().padding(.vertical, 10)
            .accessibilityHidden(true)
            ForEach(rows) { row in
                SettingsDivider()
                SpeechModelRowView(row: row, choose: choose, download: download, cancel: cancel, delete: delete)
            }
        }
    }
}

private struct SpeechModelRowView: View {
    let row: SpeechModelRow
    let choose: (String) -> Void
    let download: (String) -> Void
    let cancel: (String) -> Void
    let delete: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            radio.frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.name).font(.body.weight(.medium))
                HStack(spacing: 0) {
                    Text("\(row.recognizer) · ").foregroundStyle(.secondary)
                    Link(row.licence, destination: row.card).tint(Color.themeAccent).help("Open the card of \(row.name)")
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
            action.frame(width: 170, alignment: .trailing)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .onTapGesture { if row.radio != nil { choose(row.id) } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(row.label)
        .accessibilityAddTraits(row.radio == true ? .isSelected : [])
    }

    /// Always there so the column is the same on every row: lit on the model in use, plain on a model that is on disk, dim and dead on one that is not.
    private var radio: some View {
        Button { choose(row.id) } label: {
            Image(systemName: row.radio == true ? "largecircle.fill.circle" : "circle").foregroundStyle(row.radio == true ? Color.themeAccent : .secondary)
        }
        .buttonStyle(.plain).disabled(row.radio == nil).opacity(row.radio == nil ? 0.35 : 1)
        .accessibilityLabel("Use \(row.name)")
    }

    @ViewBuilder private var action: some View {
        switch row.action {
        case .download(let size):
            Button { download(row.id) } label: { Label("Download · \(size)", systemImage: "arrow.down.circle") }.buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
        case .downloading(let percent):
            HStack(spacing: 6) {
                ProgressView(value: Double(percent), total: 100).tint(Color.themeAccent)
                Text("\(percent)%").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                IconButton(icon: "xmark", name: "Cancel the download of \(row.name)") { cancel(row.id) }
            }
        case .failed(let cause):
            VStack(alignment: .trailing, spacing: 2) {
                Label(cause, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange).multilineTextAlignment(.trailing)
                Button { download(row.id) } label: { Label("Retry", systemImage: "arrow.clockwise") }.buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
            }
        case .delete:
            IconButton(icon: "trash", name: "Delete \(row.name)") { delete(row.id) }
        case .none:
            // a frame on an EmptyView collapses, and the whole row would slide a column to the right
            Color.clear
        }
    }
}
