import CarrierCore
import SwiftUI

/// The rows of an open session under its pinned header: messages in bubbles, notes and errors as plain lines, each tool call as a
/// card. They are the content of a `Section` of the Agent output tab's lazy stack, so only the rows on screen are built.
struct TranscriptRows: View {
    let content: TranscriptBody
    @Binding var outputs: OutputFolds
    /// How far in the rows start: a subagent's are one step in from its session's.
    var indent: CGFloat = 0

    var body: some View {
        switch content {
        case .items(let items) where items.isEmpty:
            EmptyStateView(state: .noActivity).frame(minHeight: 170).sessionRow()
        case .items(let items):
            ForEach(items) {
                TranscriptItemView(item: $0, outputs: $outputs).padding(.leading, indent).padding(.horizontal, 12)
                    .padding(.vertical, $0.verticalMargin).sessionRow()
            }
        case .tail(let lines):
            Text(lines.isEmpty ? "No output yet" : lines.joined(separator: "\n"))
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                .textSelection(.enabled).padding(12).sessionRow()
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
            // only what changes files is a card; the rest is a line of the log
            if card.kind == .edit {
                ToolCardView(card: card, outputOpen: outputs.isOpen(id, card)) { outputs.toggle(id, card) }
            } else {
                ToolLineView(card: card, outputOpen: outputs.isOpen(id, card)) { outputs.toggle(id, card) }
            }
        }
    }
}

extension TranscriptItem {
    /// The air above and below a row: what the agent says needs the most, a card some, a line of the log the least, since
    /// the lines come in runs.
    var verticalMargin: CGFloat {
        switch self {
        case .message: 8
        case .note, .error: 6
        case .tool: isLogLine ? 4 : 6
        }
    }

    /// A call that does not edit: it is drawn as a line, close to the next one.
    var isLogLine: Bool {
        if case .tool(_, let card) = self { return card.kind != .edit }
        return false
    }
}

/// A call that does not change files, as one quiet line: its small icon, what it ran or read, what came out of it. The output, when
/// opened (or when the call failed), is a console block under the line.
struct ToolLineView: View {
    let card: TranscriptCard
    let outputOpen: Bool
    let toggleOutput: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: card.kind.icon).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 16, height: 16).background(RoundedRectangle(cornerRadius: 5).fill(card.kind.color))
                Text(card.arg).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if card.summary.isEmpty == false { Text(card.summary).foregroundStyle(.secondary).lineLimit(1) }
                if let duration = card.duration { Text(duration).font(.caption).foregroundStyle(.tertiary).lineLimit(1) }
                status
                if card.output.isEmpty == false {
                    Button(outputOpen ? "hide" : "output", action: toggleOutput).buttonStyle(.link).font(.caption)
                        .help("\(card.output.count) \(card.output.count == 1 ? "line" : "lines")")
                }
            }
            .font(.system(size: 12))
            .help(card.tool)
            if outputOpen, card.output.isEmpty == false {
                Console {
                    Text(card.output.joined(separator: "\n")).textSelection(.enabled)
                        .foregroundStyle(card.status == .error ? ConsoleColor.removed : ConsoleColor.text)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var status: some View {
        if let icon = card.status.icon {
            Image(systemName: icon).foregroundStyle(card.status == .error ? Color.red : .green)
        } else {
            ProgressView().controlSize(.mini)
        }
    }
}

/// A tool call as a card: its line on top and, under it, what it did on a dark console block across the card's width: the lines
/// an edit changed, or what a command printed once its output is opened.
struct ToolCardView: View {
    let card: TranscriptCard
    let outputOpen: Bool
    let toggleOutput: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.horizontal, 10).padding(.vertical, 6)
            if let diff = card.diff { DiffView(diff: diff) }
            if outputOpen, card.output.isEmpty == false {
                Console {
                    Text(card.output.joined(separator: "\n")).textSelection(.enabled)
                        .foregroundStyle(card.status == .error ? ConsoleColor.removed : ConsoleColor.text)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12)
                }
            }
        }
        .background(Color.secondary.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: card.kind.icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 20, height: 20).background(RoundedRectangle(cornerRadius: 6).fill(card.kind.color))
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
            if card.output.isEmpty == false {
                Button(outputOpen ? "hide" : "output", action: toggleOutput).buttonStyle(.link).font(.caption)
                    .help("\(card.output.count) \(card.output.count == 1 ? "line" : "lines")")
            }
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
}

extension ToolKind {
    /// The colour of its icon: reads and searches purple, edits blue, commands grey.
    var color: Color {
        switch self {
        case .read, .search: Color(red: 0.56, green: 0.36, blue: 0.85)
        case .edit: .blue
        case .shell, .other: Color(white: 0.43)
        }
    }
}

/// The console's colours: its text, and the lines added and removed.
enum ConsoleColor {
    static let text = Color(red: 0.84, green: 0.84, blue: 0.86)
    static let added = Color(red: 0.49, green: 0.91, blue: 0.53)
    static let removed = Color(red: 1, green: 0.48, blue: 0.45)
}

/// The dark block of a console, the same in light and dark: monospaced, near black, a little air above and below.
struct Console<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .font(.system(size: 11.5, design: .monospaced))
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.05, green: 0.05, blue: 0.063))
    }
}

/// An edit's lines on the console block, added in green and removed in red, the sign in a column of its own so a selection copies
/// only the text.
struct DiffView: View {
    let diff: CardDiff

    var body: some View {
        Console {
            ForEach(Array(diff.rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 6) {
                    Text(sign(row.sign))
                    Text(row.text).textSelection(.enabled).lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(color(row.sign))
                .padding(.horizontal, 12)
                .background(color(row.sign).opacity(row.sign == .context ? 0 : 0.14))
            }
        }
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
        case .added: ConsoleColor.added
        case .removed: ConsoleColor.removed
        case .context: ConsoleColor.text
        }
    }
}
