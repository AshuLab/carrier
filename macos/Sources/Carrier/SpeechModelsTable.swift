import CarrierCore
import SwiftUI

/// The speech models of the Dictation page, in the columns of the design (`dictation-settings-spec.html`): a radio on the downloaded rows, the
/// name over its recognizer and its licence (a link to the model's card), the size, the languages, how the text appears and the action of the
/// row's state. What each row shows and offers is `speechModelRows`; this only draws it.
struct SpeechModelsTable: View {
    /// The widths of the columns, the same in the header and in every row; Model takes what is left.
    fileprivate enum Column {
        static let radio: CGFloat = 20, size: CGFloat = 64, languages: CGFloat = 150, text: CGFloat = 104, action: CGFloat = 170
    }

    let rows: [SpeechModelRow]
    let choose: (String) -> Void
    let download: (String) -> Void
    let cancel: (String) -> Void
    let delete: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Color.clear.frame(width: Column.radio)
                Text("Model").frame(maxWidth: .infinity, alignment: .leading)
                Text("Size").frame(width: Column.size, alignment: .leading)
                Text("Languages").frame(width: Column.languages, alignment: .leading)
                Text("Text appears").frame(width: Column.text, alignment: .leading)
                Color.clear.frame(width: Column.action)
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
            radio.frame(width: SpeechModelsTable.Column.radio)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.name).font(.body.weight(.medium))
                HStack(spacing: 0) {
                    Text("\(row.recognizer) · ").foregroundStyle(.secondary)
                    // underlined: the accent alone does not say it is a link when it is pale or gray
                    Link(destination: row.card) { Text(row.licence).underline() }.tint(Color.themeAccent).help("Open the card of \(row.name)")
                }
                .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.size).font(.callout).monospacedDigit().frame(width: SpeechModelsTable.Column.size, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.languages).font(.callout)
                if row.detectsLanguage { Text("Detects the language").font(.caption).foregroundStyle(.secondary) }
            }
            .frame(width: SpeechModelsTable.Column.languages, alignment: .leading)
            StatusChip(text: row.text, tint: row.live ? Color.themeAccent : .secondary).frame(width: SpeechModelsTable.Column.text, alignment: .leading)
            action.frame(width: SpeechModelsTable.Column.action, alignment: .trailing)
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
        .accessibilityAddTraits(row.radio == true ? .isSelected : [])
        .accessibilityValue(row.radio == true ? "in use" : "")
        // a model that is not on disk has nothing to choose yet: its row says so ("not downloaded") and its action is Download
        .accessibilityHidden(row.radio == nil)
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
