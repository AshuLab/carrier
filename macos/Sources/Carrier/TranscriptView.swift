import AppKit
import CarrierCore
import SwiftUI

/// The rows of an open session under its pinned header: messages in bubbles, notes and errors as plain lines, each tool call as a
/// card. They are the content of a `Section` of the Agent output tab's lazy stack, so only the rows on screen are built.
struct TranscriptRows: View {
    let content: TranscriptBody
    @Binding var outputs: OutputFolds
    @Binding var groups: GroupFolds
    @Binding var slices: SliceFolds

    var body: some View {
        switch content {
        case .loading:
            LoadingRow().sessionRow()
        case .items(let items) where items.isEmpty:
            EmptyStateView(state: .noActivity).frame(minHeight: 170).sessionRow()
        case .items(let items):
            ForEach(items) { FlowItemView(flow: $0, outputs: $outputs, groups: $groups, slices: $slices).sessionRow() }
        case .tail(let lines):
            Text(lines.isEmpty ? "No output yet" : lines.joined(separator: "\n"))
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                .textSelection(.enabled).padding(12).sessionRow()
        }
    }
}

/// What a session or the tab shows while its events have not arrived: a spinner and one word, in the place of the rows.
struct LoadingRow: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Loading…").foregroundStyle(.secondary)
        }
        .font(.callout)
        .frame(maxWidth: .infinity, minHeight: 64)
        .accessibilityElement(children: .combine)
    }
}

/// One entry of the log with its margins: a line, a group of calls or a slice row. A slice's own rows are drawn with it too.
struct FlowItemView: View {
    let flow: FlowItem
    @Binding var outputs: OutputFolds
    @Binding var groups: GroupFolds
    @Binding var slices: SliceFolds

    var body: some View {
        switch flow {
        case .item(let item):
            // a log line keeps its margin inside its hover, which runs edge to edge; the rest has it outside
            TranscriptItemView(item: item, outputs: $outputs).padding(.horizontal, item.isLogLine ? 0 : LogMetrics.iconColumn).padding(.vertical, flow.verticalMargin)
        case .group(let id, let calls):
            ToolGroupView(id: id, calls: calls, groups: $groups, outputs: $outputs).padding(.vertical, flow.verticalMargin)
        case .slice(let lane):
            LaneSectionView(lane: lane, outputs: $outputs, groups: $groups, slices: $slices)
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
                case .code(let language, let code):
                    CodeBlockView(language: language, code: code)
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

extension FlowItem {
    /// A group header has none, like a call line: its height is the pitch.
    var verticalMargin: CGFloat {
        switch self {
        case .item(let item): item.verticalMargin
        case .group, .slice: 0
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

/// The disclosure chevron of every row that opens. It turns in 0.12 s, or just jumps under Reduce Motion.
struct LogChevron: View {
    let open: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
            .rotationEffect(.degrees(open ? 90 : 0))
            .animation(LogMetrics.chevronTurn(reduceMotion: reduceMotion).map { .easeOut(duration: $0) }, value: open)
            .frame(width: LogMetrics.chevronColumn)
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
        HStack(spacing: LogMetrics.gap) {
            Text(duration ?? "").font(.system(size: 11)).monospacedDigit().foregroundStyle(failed ? AnyShapeStyle(.red) : AnyShapeStyle(.tertiary)).lineLimit(1)
                .frame(width: LogMetrics.durationColumn, alignment: .trailing)
            Group {
                if status != .ok { ToolStatusView(status: status).font(.system(size: 14)) }
            }
            .frame(width: LogMetrics.statusColumn, height: LogMetrics.statusColumn)
            LogChevron(open: chevron?.open == true).opacity(chevron?.visible == true ? 1 : 0)
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
        HStack(spacing: LogMetrics.gap) {
            Image(systemName: card.kind.icon).font(.system(size: 11)).foregroundStyle(card.status == .error ? .red : .secondary)
                .frame(width: LogMetrics.iconWidth, height: LogMetrics.iconWidth)
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
        .padding(.horizontal, LogMetrics.iconColumn)
        .frame(height: LogMetrics.callLine)
        .rowHover(active)
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
                .accessibilityLabel(callAccessibilityLabel(card, open: outputOpen))
                .accessibilityAddTraits(card.hasDetails ? .isButton : [])
                .accessibilityAction { if card.hasDetails { toggleOutput() } }
            if outputOpen, card.hasDetails {
                TerminalBlockView(card: card).padding(.top, 2).padding(.horizontal, LogMetrics.iconColumn).padding(.bottom, 8)
            }
        }
    }
}

/// A run of successful calls folded into one row of 28 pt: a chevron, what the calls were, their summed duration in a call's
/// column, and the status and chevron slots reserved and empty. Open, the calls hang 18 pt in behind a 1.5 pt rule under the
/// chevron's centre, so their icons start under the label.
struct ToolGroupView: View {
    let id: Int
    let calls: [TranscriptItem]
    @Binding var groups: GroupFolds
    @Binding var outputs: OutputFolds

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { groups.toggle(id) } label: {
                ToolGroupHeader(calls: calls, open: groups.isOpen(id))
            }
            .buttonStyle(.plain)
            if groups.isOpen(id) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(calls) { TranscriptItemView(item: $0, outputs: $outputs) }
                }
                .thread(indent: LogMetrics.groupIndent, rule: LogMetrics.groupRule, tint: .secondary)
            }
        }
    }
}

struct ToolGroupHeader: View {
    let calls: [TranscriptItem]
    let open: Bool
    @State private var hovered = false

    private var label: String { callGroupLabel(calls) }
    private var duration: String? { callGroupDuration(calls) }

    var body: some View {
        HStack(spacing: LogMetrics.gap) {
            LogChevron(open: open)
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            // the columns of a call, the status and chevron slots empty
            CallColumns(duration: duration, status: .ok)
        }
        // the row's margin is inside the hover, which runs edge to edge: with so little room, square corners at the edge look right
        .padding(.horizontal, LogMetrics.iconColumn)
        .frame(height: LogMetrics.groupLine)
        .rowHover(hovered)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(callGroupAccessibilityLabel(calls, open: open))
        .accessibilityHint(callGroupAccessibilityHint(open: open))
    }
}

/// A call to the `Skill` tool, a milestone of its own: a grey box with a white glyph and its name in medium monospaced, 28 pt
/// high, no chevron (nothing to open).
struct SkillRowView: View {
    let card: TranscriptCard
    @State private var hovered = false

    var body: some View {
        HStack(spacing: LogMetrics.gap) {
            Image(systemName: card.kind.icon).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                .frame(width: LogMetrics.iconWidth, height: LogMetrics.iconWidth).background(RoundedRectangle(cornerRadius: 5).fill(card.kind.color))
            Text(card.title).font(.system(size: 12, weight: .medium, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            CallColumns(duration: card.showsDuration(active: hovered) ? card.duration : nil, failed: card.status == .error, status: card.status)
        }
        .padding(.horizontal, LogMetrics.iconColumn)
        .frame(height: LogMetrics.skillRow)
        .rowHover(hovered)
        .onHover { hovered = $0 }
        .help(card.arg)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(callAccessibilityLabel(card))
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

/// How a call that did not simply work is marked: a red disc with a white cross, or a spinner while it runs (still under Reduce
/// Motion). The disc is drawn in two colours: with one, the mark would be see-through. VoiceOver skips both: the row's label says it.
struct ToolStatusView: View {
    let status: ToolStatus

    var body: some View {
        Group {
            if status == .pending {
                SpinningRing(diameter: 12, lineWidth: 1.5, color: .secondaryLabelColor)
            } else if status == .error, let icon = status.icon {
                Image(systemName: icon).symbolRenderingMode(.palette).foregroundStyle(.white, Color.red)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The console's footer button: copies what the block shows and says so for a moment.
struct CopyButton: View {
    let text: String
    var help = "Copy the command and its output"
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
        .help(help)
    }
}

/// An edit as a card, "name first": the file name, its folder dim, the counts once and nothing that says it worked. A failed edit
/// has the engine's reason under the header and no diff; a running one a spinner.
struct ToolCardView: View {
    let card: TranscriptCard
    @State private var showAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.horizontal, 10).padding(.vertical, 7).frame(minHeight: 34)
            if let reason = card.editReason {
                Text(reason).font(.system(size: 12)).foregroundStyle(.red).lineLimit(2)
                    .padding(.horizontal, 10).padding(.bottom, 8)
            }
            if let diff = card.shownDiff { DiffView(rows: diff.rows, showAll: $showAll) }
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
                if card.isNewFile {
                    Text("new").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.green)
                        .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(Color.green.opacity(0.16)))
                }
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
    /// The colour of the icon box of a milestone: blue for an edit, grey for a skill. The calls have a bare glyph.
    var color: Color {
        switch self {
        case .edit: .blue
        case .read, .search, .shell, .other: Color(white: 0.43)
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
/// only the text; a hunk row is a quiet separator carrying git's range. A long diff is cut at `collapsedDiffRows`; the footer opens
/// the rest. `cut` is a last line saying the engine cut the diff. Text and footer are inset 14, like the opened call.
struct DiffView: View {
    let rows: [DiffRow]
    @Binding var showAll: Bool
    var cut: String? = nil

    var body: some View {
        let shown = visibleDiffRows(rows, expanded: showAll)
        Console {
            ForEach(Array(shown.rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 6) {
                    Text(sign(row.sign))
                    Text(row.text).textSelection(.enabled).lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(color(row.sign))
                .padding(.horizontal, 14)
                .padding(.vertical, row.sign == .hunk ? 2 : 0)
                .background(row.sign == .hunk ? Color.white.opacity(0.05) : color(row.sign).opacity(row.sign == .context ? 0 : 0.14))
            }
            if rows.count > collapsedDiffRows {
                Button(showAll ? "Show less" : "Show \(shown.hidden) more \(shown.hidden == 1 ? "line" : "lines")") { showAll.toggle() }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 14).padding(.top, 7).padding(.bottom, 1)
            }
            if let cut {
                Text(cut).font(.system(size: 11)).foregroundStyle(ConsoleColor.text.opacity(0.6))
                    .padding(.horizontal, 14).padding(.top, 7).padding(.bottom, 1)
            }
        }
    }

    private func sign(_ sign: DiffSign) -> String {
        switch sign {
        case .added: "+"
        case .removed: "−"
        case .context, .hunk: " "
        }
    }

    private func color(_ sign: DiffSign) -> Color {
        switch sign {
        case .added: ConsoleColor.added
        case .removed: ConsoleColor.removed
        case .context: ConsoleColor.text
        case .hunk: ConsoleColor.text.opacity(0.55)
        }
    }
}

// MARK: - The thread of a slice or a group

private struct RuleReachKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }

extension EnvironmentValues {
    /// How far a row's hover fill runs left of the row, to meet the rule of the thread it hangs from.
    fileprivate var ruleReach: CGFloat {
        get { self[RuleReachKey.self] }
        set { self[RuleReachKey.self] = newValue }
    }
}

private struct RowHover: ViewModifier {
    let active: Bool
    @Environment(\.ruleReach) private var reach

    func body(content: Content) -> some View {
        content.background { Rectangle().fill(Color.primary.opacity(active ? 0.05 : 0)).padding(.leading, -reach) }
    }
}

private struct ThreadRule: ViewModifier {
    let indent: CGFloat
    let rule: CGFloat
    let tint: Color
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .padding(.leading, indent)
            .environment(\.ruleReach, indent - rule - LogMetrics.ruleWidth / 2)
            .overlay(alignment: .leading) {
                Capsule().fill(hovered ? tint.opacity(0.7) : Color.secondary.opacity(0.25)).frame(width: LogMetrics.ruleWidth)
                    .padding(.leading, rule - LogMetrics.ruleWidth / 2)
            }
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
    }
}

extension View {
    /// The fill of a hovered row of the log; inside a thread it reaches the rule.
    func rowHover(_ active: Bool) -> some View { modifier(RowHover(active: active)) }

    /// Hangs the rows `indent` pt in behind a rule at `rule`: rounded, soft, and tinted while any row of the thread is hovered.
    func thread(indent: CGFloat, rule: CGFloat, tint: Color) -> some View { modifier(ThreadRule(indent: indent, rule: rule, tint: tint)) }
}
