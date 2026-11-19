import CarrierCore
import SwiftUI

/// The speech models of the Dictation page, in the columns of the design (`dictation-settings-spec.html`): a radio on the downloaded rows, the
/// name over its recognizer and its licence (a link to the model's card), the size, the languages, how the text appears and the action of the
/// row's state. What each row shows and offers is `speechModelRows`; this only draws it.
struct SpeechModelsTable: View {
    /// The widths of the columns, the same in the header and in every row; Model takes what is left.
    fileprivate enum Column {
        static let radio: CGFloat = 18, size: CGFloat = 58, languages: CGFloat = 138, text: CGFloat = 96, action: CGFloat = 164
    }

    let rows: [SpeechModelRow]
    let choose: (String) -> Void
    let download: (String) -> Void
    let cancel: (String) -> Void
    let delete: (String) -> Void

    /// Below this width the columns do not leave the name room: each row is its name, what it says of the model under it, and its action.
    private static let narrow: CGFloat = 640
    @State private var width = CGFloat.infinity

    var body: some View {
        let compact = width < Self.narrow
        VStack(spacing: 0) {
            if compact == false { header }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 || compact == false { SettingsDivider() }
                SpeechModelRowView(row: row, compact: compact, choose: choose, download: download, cancel: cancel, delete: delete)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                // a height too: a color with none takes all the row has, and in a form that is a tall blank over the header
                Color.clear.frame(width: Column.radio, height: 1)
                Text("Model").frame(maxWidth: .infinity, alignment: .leading)
                Text("Size").frame(width: Column.size, alignment: .leading)
                Text("Languages").frame(width: Column.languages, alignment: .leading)
                Text("Text appears").frame(width: Column.text, alignment: .leading)
                Color.clear.frame(width: Column.action, height: 1)
            }
            .sectionLabel().padding(.vertical, 10)
            .accessibilityHidden(true)
        }
    }
}

private struct SpeechModelRowView: View {
    let row: SpeechModelRow
    let compact: Bool
    let choose: (String) -> Void
    let download: (String) -> Void
    let cancel: (String) -> Void
    let delete: (String) -> Void

    private var nameAndLicence: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(row.name).font(.scaled(13).weight(.medium)).lineLimit(2)
            HStack(spacing: 0) {
                Text("\(row.recognizer) · ").foregroundStyle(.secondary)
                // underlined: the accent alone does not say it is a link when it is pale or gray
                Link(destination: row.card) { Text(row.licence).underline() }.tint(Color.themeAccent).help("Open the card of \(row.name)")
            }
            .font(.scaled(11))
        }
    }

    var body: some View {
        Group { if compact { narrow } else { wide } }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .onTapGesture { if row.radio != nil { choose(row.id) } }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(row.label)
            .accessibilityAddTraits(row.radio == true ? .isSelected : [])
    }

    /// The row of a narrow window: the size, the languages and how the text appears go under the name, the action stays at the end.
    private var narrow: some View {
        HStack(alignment: .top, spacing: 8) {
            radio.frame(width: SpeechModelsTable.Column.radio)
            VStack(alignment: .leading, spacing: 6) {
                nameAndLicence
                FlowLayout(spacing: 8) {
                    Text(row.size).font(.scaled(12)).monospacedDigit()
                    Text(row.detectsLanguage ? "\(row.languages) · Detects the language" : row.languages).font(.scaled(12)).foregroundStyle(.secondary)
                    StatusChip(text: row.text, tint: row.live ? Color.themeAccent : .secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            action.fixedSize()
        }
    }

    private var wide: some View {
        HStack(spacing: 8) {
            radio.frame(width: SpeechModelsTable.Column.radio)
            nameAndLicence
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.size).font(.scaled(12)).monospacedDigit().frame(width: SpeechModelsTable.Column.size, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.languages).font(.scaled(12))
                if row.detectsLanguage { Text("Detects the language").font(.scaled(11)).foregroundStyle(.secondary) }
            }
            .frame(width: SpeechModelsTable.Column.languages, alignment: .leading)
            StatusChip(text: row.text, tint: row.live ? Color.themeAccent : .secondary).frame(width: SpeechModelsTable.Column.text, alignment: .leading)
            action.frame(width: SpeechModelsTable.Column.action, alignment: .trailing)
        }
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
            Button { download(row.id) } label: { Label("Download · \(size)", systemImage: "arrow.down.circle").lineLimit(1).fixedSize() }.buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
        case .downloading(let percent):
            HStack(spacing: 6) {
                ProgressView(value: Double(percent), total: 100).tint(Color.themeAccent)
                Text("\(percent)%").font(.scaled(11)).foregroundStyle(.secondary).monospacedDigit()
                IconButton(icon: "xmark", name: "Cancel the download of \(row.name)") { cancel(row.id) }
            }
        case .failed(let cause):
            VStack(alignment: .trailing, spacing: 2) {
                Label(cause, systemImage: "exclamationmark.triangle.fill").font(.scaled(11)).foregroundStyle(.orange).multilineTextAlignment(.trailing)
                Button { download(row.id) } label: { Label("Retry", systemImage: "arrow.clockwise") }.buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
            }
        case .delete:
            IconButton(icon: "trash", name: "Delete \(row.name)") { delete(row.id) }
        case .none:
            // a frame on an EmptyView collapses, and the whole row would slide a column to the right
            Color.clear.frame(height: 1)
        }
    }
}
