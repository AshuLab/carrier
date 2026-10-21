import CarrierCore
import SwiftUI

/// The rows of an open session under its pinned header: messages in bubbles, notes and errors as plain lines, each tool call as a
/// card. They are the content of a `Section` of the Agent output tab's lazy stack, so only the rows on screen are built.
struct TranscriptRows: View {
    let content: TranscriptBody
    @Binding var outputs: OutputFolds

    var body: some View {
        switch content {
        case .items(let items) where items.isEmpty:
            Text("No activity yet").font(.callout).foregroundStyle(.secondary).padding(12)
        case .items(let items):
            ForEach(items) { TranscriptItemView(item: $0, outputs: $outputs).padding(.horizontal, 12).padding(.bottom, 6) }
        case .tail(let lines):
            Text(lines.isEmpty ? "No output yet" : lines.joined(separator: "\n"))
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12)
        }
    }
}

struct TranscriptItemView: View {
    let item: TranscriptItem
    @Binding var outputs: OutputFolds

    var body: some View {
        switch item {
        case .message(_, let text):
            Text(text).textSelection(.enabled).lineSpacing(2)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.12)))
        case .note(_, let text):
            Text(text).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
        case .error(_, let text):
            Text(text).font(.callout).foregroundStyle(.red).textSelection(.enabled)
        case .tool(let id, let card):
            ToolCardView(card: card, outputOpen: outputs.isOpen(id, card)) { outputs.toggle(id, card) }
        }
    }
}

struct ToolCardView: View {
    let card: TranscriptCard
    let outputOpen: Bool
    let toggleOutput: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if let diff = card.diff { DiffView(diff: diff) }
            if card.output.isEmpty == false {
                Button(outputOpen ? "Hide output" : "Show output (\(card.output.count) \(card.output.count == 1 ? "line" : "lines"))", action: toggleOutput)
                    .buttonStyle(.link).font(.caption)
                if outputOpen {
                    Text(card.output.joined(separator: "\n")).font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(card.status == .error ? Color.red : .secondary)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.12)))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: card.kind.icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 20, height: 20).background(RoundedRectangle(cornerRadius: 6).fill(color))
            Text(card.tool).fontWeight(.semibold)
            Text(card.arg).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let diff = card.diff {
                Text("+\(diff.added)").foregroundStyle(.green)
                Text("−\(diff.removed)").foregroundStyle(.red)
            }
            if card.summary.isEmpty == false { Text(card.summary).foregroundStyle(.secondary).lineLimit(1) }
            if let duration = card.duration { Text(duration).font(.caption).foregroundStyle(.tertiary).lineLimit(1) }
            status
        }
        .font(.system(size: 12))
    }

    @ViewBuilder private var status: some View {
        if let icon = card.status.icon {
            Image(systemName: icon).foregroundStyle(card.status == .error ? Color.red : .green)
        } else {
            ProgressView().controlSize(.mini)
        }
    }

    private var color: Color {
        switch card.kind {
        case .read, .search: Color(red: 0.56, green: 0.36, blue: 0.85)
        case .edit: .blue
        case .shell, .other: Color(white: 0.43)
        }
    }
}

/// An edit's lines in red and green, the sign in a column of its own so a selection copies only the text.
struct DiffView: View {
    let diff: CardDiff

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(diff.rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 6) {
                    Text(sign(row.sign)).foregroundStyle(color(row.sign))
                    Text(row.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 8)
                .background(color(row.sign).opacity(row.sign == .context ? 0 : 0.14))
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func sign(_ sign: DiffSign) -> String {
        switch sign {
        case .added: "+"
        case .removed: "−"
        case .context: " "
        }
    }

    private func color(_ sign: DiffSign) -> Color {
        switch sign {
        case .added: .green
        case .removed: .red
        case .context: .secondary
        }
    }
}
