import AppKit
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

/// An agent's text laid out by block: lines with room between them, bullets that hang, a gap for a blank line.
struct MarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(markdownBlocks(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .line(let line):
                    Text(line).lineSpacing(3)
                case .bullet(let level, let line):
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("•").foregroundStyle(.secondary)
                        Text(line).lineSpacing(3)
                    }
                    .padding(.leading, CGFloat(level) * 16)
                case .gap:
                    Color.clear.frame(height: 5)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}

struct TranscriptItemView: View {
    let item: TranscriptItem
    @Binding var outputs: OutputFolds

    var body: some View {
        switch item {
        case .message(_, let text):
            MarkdownView(text: text)
                .padding(.horizontal, 12).padding(.vertical, 10)
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

/// A call that does not change files, as one line: its small icon, what it starts with, how long it took and whether it worked.
/// A click opens the whole command and what it printed on a console block under the line; a call that failed starts open.
struct ToolLineView: View {
    let card: TranscriptCard
    let outputOpen: Bool
    let toggleOutput: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: card.kind.icon).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 16, height: 16).background(RoundedRectangle(cornerRadius: 5).fill(card.kind.color))
                Text(card.title).font(.system(size: 12, design: .monospaced)).lineLimit(1)
                    .truncationMode(card.kind == .shell ? .tail : .middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let duration = card.duration { Text(duration).font(.caption).foregroundStyle(.tertiary).lineLimit(1) }
                status
                if card.hasDetails {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(outputOpen ? 90 : 0))
                }
            }
            .font(.system(size: 12))
            .contentShape(Rectangle())
            .onTapGesture { if card.hasDetails { toggleOutput() } }
            .help(card.arg)
            if outputOpen, card.hasDetails {
                TerminalBlockView(card: card).padding(.top, 6)
            }
        }
        .padding(.vertical, 2)
    }

    private var status: some View { ToolStatusView(status: card.status) }
}

/// What an opened call shows, on dark glass: the command on its own strip with how it ended, the output (its first lines, the
/// rest behind "Show N more lines") and a footer with the line count and Copy.
struct TerminalBlockView: View {
    let card: TranscriptCard
    @State private var showAll = false

    private static let corner: CGFloat = 16
    private static let glass = Color(red: 0.05, green: 0.05, blue: 0.063).opacity(0.7)

    var body: some View {
        let shown = card.visibleOutput(expanded: showAll)
        VStack(alignment: .leading, spacing: 0) {
            strip
            if shown.lines.isEmpty == false {
                Text(shown.lines.joined(separator: "\n")).textSelection(.enabled)
                    .foregroundStyle(card.status == .error ? ConsoleColor.removed : ConsoleColor.text)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.vertical, 9)
                    // a cut output fades out where it is cut
                    .mask {
                        if shown.hidden > 0 {
                            LinearGradient(stops: [.init(color: .black, location: 0.78), .init(color: .black.opacity(0.25), location: 1)], startPoint: .top, endPoint: .bottom)
                        } else {
                            Color.black
                        }
                    }
            }
            Rectangle().fill(ConsoleColor.text.opacity(0.12)).frame(height: 0.5)
            footer(hidden: shown.hidden)
        }
        .font(.system(size: 11.5, design: .monospaced))
        // the strip is square: cut it to the glass's corners
        .clipShape(RoundedRectangle(cornerRadius: Self.corner))
        .glassEffect(.regular.tint(Self.glass), in: RoundedRectangle(cornerRadius: Self.corner))
    }

    private var strip: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(card.kind == .shell ? "❯" : card.tool).fontWeight(.semibold).foregroundStyle(ConsoleColor.added)
            Text(card.arg).textSelection(.enabled).foregroundStyle(ConsoleColor.command)
                .frame(maxWidth: .infinity, alignment: .leading)
            outcome
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(Color.white.opacity(0.05))
    }

    /// "✓ 1.7 s" in green, "✕ 906 ms" in red; a spinner while the call runs.
    @ViewBuilder private var outcome: some View {
        if card.status == .pending {
            ProgressView().controlSize(.mini)
        } else {
            let failed = card.status == .error
            let color = failed ? ConsoleColor.removed : ConsoleColor.added
            Text([failed ? "✕" : "✓", card.duration].compactMap { $0 }.joined(separator: " "))
                .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(color)
                .padding(.horizontal, 8).padding(.vertical, 2).background(Capsule().fill(color.opacity(0.17)))
        }
    }

    private func footer(hidden: Int) -> some View {
        HStack(spacing: 12) {
            Text(card.output.isEmpty ? "no output" : "\(card.output.count) \(card.output.count == 1 ? "line" : "lines")")
                .foregroundStyle(ConsoleColor.text.opacity(0.5))
            if hidden > 0 || showAll {
                Button(showAll ? "Show less" : "Show \(hidden) more \(hidden == 1 ? "line" : "lines")") { showAll.toggle() }
                    .buttonStyle(.plain).foregroundStyle(Color(red: 0.42, green: 0.64, blue: 1))
            }
            Spacer(minLength: 0)
            CopyButton(text: card.copyText)
        }
        .font(.system(size: 11))
        .padding(.leading, 14).padding(.trailing, 10).padding(.vertical, 9)
    }
}

/// How a call ended: a disc with a white tick (green) or a white cross (red), or a spinner while it runs. The disc symbols are
/// drawn in two colours: with one, the mark would be see-through and show the dark row behind it.
struct ToolStatusView: View {
    let status: ToolStatus

    var body: some View {
        if let icon = status.icon {
            Image(systemName: icon).symbolRenderingMode(.palette).foregroundStyle(.white, status == .error ? Color.red : .green)
        } else {
            ProgressView().controlSize(.mini)
        }
    }
}

/// The console's footer button: copies what the block shows and says so for a moment.
struct CopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            // the icon and the word keep their size when they swap, so the button does not move
            HStack(spacing: 5) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc").frame(width: 12, height: 14)
                Text(copied ? "Copied" : "Copy").frame(width: 40, alignment: .leading)
            }
            .font(.system(size: 11)).foregroundStyle(ConsoleColor.text.opacity(0.7)).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Copy the command and its output")
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

    private var status: some View { ToolStatusView(status: card.status) }
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

/// The console's colours: its text, a command, and the lines added and removed.
enum ConsoleColor {
    static let text = Color(red: 0.84, green: 0.84, blue: 0.86)
    /// The command line above what it printed.
    static let command = Color(red: 0.6, green: 0.63, blue: 1)
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
