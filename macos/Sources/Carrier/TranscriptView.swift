import AppKit
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
            EmptyStateView(state: .noActivity).frame(minHeight: 170).sessionRow()
        case .items(let items):
            ForEach(items) {
                TranscriptItemView(item: $0, outputs: $outputs).padding(.horizontal, 12)
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
            Group {
                if let json = jsonMessage(text) { JSONMessageView(message: json) } else { MarkdownView(text: text) }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.12)))
        case .note(_, let text):
            Text(text).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
        case .error(_, let text):
            Text(text).font(.callout).foregroundStyle(.red).textSelection(.enabled)
        case .tool(let id, let card):
            // only what changes files is a card; the rest is a line of the log
            if card.kind == .edit {
                ToolCardView(card: card)
            } else if card.isSkill {
                SkillRowView(card: card)
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
        case .tool(_, let card): card.isSkill ? 2 : isLogLine ? 0 : 6
        }
    }

    /// A call that does not edit: it is drawn as a line, with no air of its own (its height is the pitch of a run).
    var isLogLine: Bool {
        if case .tool(_, let card) = self { return card.kind != .edit }
        return false
    }
}

/// The right-hand columns every call row reserves, so a title is cut at the same place whether or not they show: duration 44
/// (right aligned), status 14, chevron 10, 8 apart. A nil `chevron` leaves its slot empty.
struct CallColumns: View {
    let duration: String?
    var failed = false
    let status: ToolStatus
    var chevron: (visible: Bool, open: Bool)?

    var body: some View {
        HStack(spacing: 8) {
            Text(duration ?? "").font(.system(size: 11)).monospacedDigit().foregroundStyle(failed ? AnyShapeStyle(.red) : AnyShapeStyle(.tertiary)).lineLimit(1)
                .frame(width: 44, alignment: .trailing)
            Group {
                if status != .ok { ToolStatusView(status: status).font(.system(size: 14)) }
            }
            .frame(width: 14, height: 14)
            Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
                .rotationEffect(.degrees(chevron?.open == true ? 90 : 0)).opacity(chevron?.visible == true ? 1 : 0)
                .frame(width: 10)
        }
    }
}

/// A call that does not change files, as a quiet line of 26 pt: a bare glyph, what it starts with, and its duration when it
/// matters. Nothing says it worked; a failure is red and keeps its chevron.
struct CallLineView: View {
    let card: TranscriptCard
    let open: Bool
    /// Hovered or focused.
    let active: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: card.kind.icon).font(.system(size: 11)).foregroundStyle(card.status == .error ? .red : .secondary)
                .frame(width: 16, height: 16)
            HStack(spacing: 4) {
                Text(card.title).font(.system(size: 12, design: .monospaced)).lineLimit(1)
                    .truncationMode(card.kind == .shell ? .tail : .middle)
                if card.moreCommands > 0 {
                    Text("+\(card.moreCommands)").font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1).fixedSize()
                        .help("\(card.moreCommands) more commands in this call")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            CallColumns(
                duration: card.showsDuration(active: active) ? card.duration : nil, failed: card.status == .error, status: card.status,
                chevron: (card.showsChevron(active: active, open: open), open)
            )
        }
        .frame(height: 26)
        .background(Color.primary.opacity(active ? 0.05 : 0))
        .contentShape(Rectangle())
    }
}

/// A call line that opens: a click, or Return or Space with the keyboard on it, shows the whole command and what it printed on a
/// flat grey block under the line; a call that failed starts open.
struct ToolLineView: View {
    let card: TranscriptCard
    let outputOpen: Bool
    let toggleOutput: () -> Void
    @State private var hovered = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CallLineView(card: card, open: outputOpen, active: hovered || focused)
                .onHover { hovered = $0 }
                .focusable().focused($focused)
                .onKeyPress(keys: [.return, .space]) { _ in
                    guard card.hasDetails else { return .ignored }
                    toggleOutput()
                    return .handled
                }
                .onTapGesture { if card.hasDetails { toggleOutput() } }
                .help(card.arg)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel([card.title, card.status == .error ? "failed" : card.status == .pending ? "running" : nil, card.duration]
                    .compactMap { $0 }.joined(separator: ", "))
            if outputOpen, card.hasDetails {
                TerminalBlockView(card: card).padding(.top, 2).padding(.leading, 24).padding(.bottom, 8)
            }
        }
    }
}

/// A call to the `Skill` tool, a milestone of its own: a grey box with a white glyph and its name in medium monospaced, 28 pt
/// high, no chevron (nothing to open).
struct SkillRowView: View {
    let card: TranscriptCard
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: card.kind.icon).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                .frame(width: 16, height: 16).background(RoundedRectangle(cornerRadius: 5).fill(card.kind.color))
            Text(card.title).font(.system(size: 12, weight: .medium, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            CallColumns(duration: card.showsDuration(active: hovered) ? card.duration : nil, failed: card.status == .error, status: card.status)
        }
        .frame(height: 28)
        .background(Color.primary.opacity(hovered ? 0.05 : 0))
        .onHover { hovered = $0 }
        .help(card.arg)
    }
}

/// What an opened call shows, flat on the raised grey of the message bubble: the command on its own strip, the output (its first
/// lines, the rest behind "Show N more lines") and a footer with the line count and Copy.
struct TerminalBlockView: View {
    let card: TranscriptCard
    @State private var showAll = false

    var body: some View {
        let shown = card.visibleOutput(expanded: showAll)
        VStack(alignment: .leading, spacing: 0) {
            strip
            divider
            if shown.lines.isEmpty {
                Text("no output").font(.system(size: 11.5)).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.vertical, 9)
            } else {
                output(shown.lines).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.vertical, 8)
                    // a cut output fades out where it is cut
                    .mask {
                        if shown.hidden > 0 {
                            LinearGradient(stops: [.init(color: .black, location: 0.78), .init(color: .black.opacity(0.25), location: 1)], startPoint: .top, endPoint: .bottom)
                        } else {
                            Color.black
                        }
                    }
            }
            divider
            footer(hidden: shown.hidden)
        }
        .font(.system(size: 11.5, design: .monospaced))
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.12)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var divider: some View { Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 0.5) }

    /// Only the `Exit code N` line of a failed call is red; the rest is normal text.
    private func output(_ lines: [String]) -> Text {
        guard let failure = card.failureLine else { return Text(lines.joined(separator: "\n")) }
        let rest = lines.count > 1 ? "\n" + lines.dropFirst().joined(separator: "\n") : ""
        return Text("\(Text(failure).foregroundStyle(.red))\(rest)")
    }

    private var strip: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(card.kind == .shell ? "❯" : card.tool).fontWeight(.semibold)
            Text(card.arg).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private func footer(hidden: Int) -> some View {
        HStack(spacing: 12) {
            if let count = card.lineCount { Text(count).foregroundStyle(.tertiary) }
            if hidden > 0 || showAll {
                Button(showAll ? "Show less" : "Show \(hidden) more \(hidden == 1 ? "line" : "lines")") { showAll.toggle() }
                    .buttonStyle(.plain).foregroundStyle(Color.accentColor)
            }
            Spacer(minLength: 0)
            CopyButton(text: card.copyText)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 14).padding(.vertical, 7)
    }
}

/// How a call ended where it is marked: a disc with a white cross (red), or a spinner while it runs. The disc symbols are
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
            .font(.system(size: 11)).foregroundStyle(.secondary).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Copy the command and its output")
    }
}

/// An edit as a card, "name first": the file name, its folder dim, the counts once and nothing that says it worked. A failed edit
/// has the engine's reason under the header and no diff; a running one a spinner.
struct ToolCardView: View {
    let card: TranscriptCard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.horizontal, 10).padding(.vertical, 7).frame(minHeight: 34)
            if let reason = card.editReason {
                Text(reason).font(.system(size: 12)).foregroundStyle(.red).lineLimit(2)
                    .padding(.horizontal, 10).padding(.bottom, 8)
            }
            if let diff = card.shownDiff { DiffView(diff: diff) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: card.kind.icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 20, height: 20).background(RoundedRectangle(cornerRadius: 6).fill(card.kind.color))
            HStack(spacing: 6) {
                Text(card.editName).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                if card.editFolder.isEmpty == false {
                    Text(card.editFolder).font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
                        .lineLimit(1).truncationMode(.head)
                }
            }
            .help(card.arg).frame(maxWidth: .infinity, alignment: .leading)
            if let diff = card.shownDiff {
                HStack(spacing: 4) {
                    Text("+\(diff.added)").foregroundStyle(.green)
                    Text("−\(diff.removed)").foregroundStyle(.red)
                }
                .font(.system(size: 12, weight: .medium)).monospacedDigit()
            }
            // a tick says nothing; only a failure or a running edit is marked
            if card.status != .ok { ToolStatusView(status: card.status) }
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

/// The console's colours: its text and the lines added and removed.
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
