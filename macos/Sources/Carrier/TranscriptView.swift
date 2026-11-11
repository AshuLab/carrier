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
    @AppStorage(AppPreferences.toolOutputKey) private var mode = AppPreferences.defaultToolOutput

    var body: some View {
        switch content {
        case .loading:
            LoadingRow().sessionRow()
        case .items(let items) where items.isEmpty:
            EmptyStateView(state: .noActivity).frame(minHeight: 170).sessionRow()
        case .items(let items):
            ForEach(visibleFlow(items, mode: mode)) { FlowItemView(flow: $0, outputs: $outputs, groups: $groups, slices: $slices).sessionRow() }
        case .tail(let lines):
            MonoLines(lines: lines.isEmpty ? ["No output yet"] : lines)
                .codeFont(12).foregroundStyle(.secondary)
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
        .font(.scaled(12))
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

/// A text with links: the pointing hand over each one, and the chip lighter under the pointer. `Text` says nothing of where a run was drawn
/// (a text renderer is never called for selectable text), so the links are placed by laying the same text out again with TextKit at the
/// width the view has: same font, same line spacing, same breaks. ponytail: a font or a break that TextKit sets a little differently from
/// SwiftUI moves a link's hit area by a few points; an NSTextView would be exact if that is ever noticed.
private struct LinkedText: View {
    let text: AttributedString
    @Environment(\.colorScheme) private var scheme
    @State private var places: [(link: Int, rect: CGRect)] = []
    @State private var hovered: Int?
    @State private var overLink = false

    var body: some View {
        Text(lit)
            .lineSpacing(4)
            .contentTransition(.interpolate)
            .animation(.easeOut(duration: 0.15), value: hovered)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { places = Self.place(links: text, width: $0) }
            .onChange(of: text) { places = [] }
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    let hit = places.first { $0.rect.contains(point) }?.link
                    set(hit)
                case .ended: set(nil)
                }
            }
            .onDisappear { set(nil) }
    }

    /// The text with the link under the pointer in a stronger tint.
    private var lit: AttributedString {
        guard let hovered else { return text }
        var out = text
        var index = 0
        for run in text.runs where run.link != nil {
            if index == hovered { out[run.range].backgroundColor = Color.themeAccent.opacity(scheme == .dark ? 0.45 : 0.3) }
            index += 1
        }
        return out
    }

    private func set(_ link: Int?) {
        hovered = link
        guard (link != nil) != overLink else { return }
        overLink = link != nil
        if overLink { NSCursor.pointingHand.push() } else { NSCursor.pop() }
    }

    /// The rectangles each link takes (one per line it spans), numbered in the order the links come, in the text's own coordinates.
    private static func place(links text: AttributedString, width: CGFloat) -> [(link: Int, rect: CGRect)] {
        guard width > 0 else { return [] }
        let base = NSFont.scaled(13)
        let ns = NSMutableAttributedString()
        var ranges: [NSRange] = []
        for run in text.runs {
            let piece = String(text[run.range].characters)
            var font = base
            if run.font != nil {
                font = NSFont.scaled(6) // the short empty line
            } else if let intent = run.inlinePresentationIntent {
                if intent.contains(.code) { font = NSFont.scaledMono(13) }
                if intent.contains(.stronglyEmphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
                if intent.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
            }
            if run.link != nil { ranges.append(NSRange(location: ns.length, length: piece.utf16.count)) }
            ns.append(NSAttributedString(string: piece, attributes: [.font: font]))
        }
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        ns.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: ns.length))
        let storage = NSTextStorage(attributedString: ns)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        var found: [(link: Int, rect: CGRect)] = []
        for (index, range) in ranges.enumerated() {
            let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            layout.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container) { rect, _ in
                found.append((index, rect))
            }
        }
        return found
    }
}

/// A table of pipes, in the glass of the code blocks: a header row, a hairline between the rows, and columns sized to their text, the
/// wide ones sharing what is left when the table does not fit the message (their cells wrap).
private struct MarkdownTableView: View {
    let table: MarkdownTable
    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        let columns = table.header.count
        TableLayout(columns: columns) {
            ForEach(0..<columns, id: \.self) { cell(table.header[$0], column: $0, header: true, first: true) }
            ForEach(Array(table.rows.enumerated()), id: \.offset) { row, cells in
                ForEach(0..<columns, id: \.self) { cell(cells[$0], column: $0, header: false, first: false) }
            }
        }
        // the card is as wide as its table, not as the message
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.045)))
        .glassEffect(.regular.tint(scheme == .dark ? Color.black.opacity(0.3) : nil), in: .rect(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topTrailing) { copyMenu.opacity(hovering || copied ? 1 : 0).padding(5) }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .contextMenu { copyButtons }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
    }

    /// Copy over the table's corner, shown while the pointer is over it: as tabs for a spreadsheet, or as the pipes it was written with.
    private var copyMenu: some View {
        Menu { copyButtons } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.scaled(11, weight: .medium)).foregroundStyle(copied ? Color.green : .secondary)
                .frame(width: 24, height: 22)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .background(Capsule().fill(.regularMaterial))
        .help("Copy the table").accessibilityLabel("Copy the table")
    }

    @ViewBuilder private var copyButtons: some View {
        Button("Copy for a spreadsheet") { copy(table.tsv) }
        Button("Copy as Markdown") { copy(table.markdown) }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.3))
            copied = false
        }
    }

    private func cell(_ text: AttributedString, column: Int, header: Bool, first: Bool) -> some View {
        let align: Alignment = switch table.aligns[column] {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
        return Text(text).font(.scaled(12.5, weight: header ? .semibold : nil)).lineSpacing(2)
            .multilineTextAlignment(table.aligns[column] == .trailing ? .trailing : table.aligns[column] == .center ? .center : .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: align)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(header ? Color.primary.opacity(0.06) : .clear)
            // a hairline over every row but the header
            .overlay(alignment: .top) { if header == false { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5) } }
    }
}

/// Lays out a table's cells, `columns` to a row: each column as wide as its widest cell when the table fits the width it is offered;
/// when it does not, the columns that fit an equal share keep their width and the others split what is left in proportion to their text;
/// each row as tall as its tallest cell, and every cell filling its row.
private struct TableLayout: Layout {
    let columns: Int

    private func widths(_ subviews: Subviews, within width: CGFloat) -> [CGFloat] {
        let natural = (0..<columns).map { column in
            stride(from: column, to: subviews.count, by: columns).map { subviews[$0].sizeThatFits(.unspecified).width }.max() ?? 0
        }
        guard natural.reduce(0, +) > width else { return natural }
        var widths = natural
        var open = Array(0..<columns)
        var remaining = width
        while let fits = open.first(where: { natural[$0] <= remaining / CGFloat(open.count) }) {
            remaining -= natural[fits]
            open.removeAll { $0 == fits }
        }
        let wanted = open.reduce(CGFloat(0)) { $0 + natural[$1] }
        for column in open { widths[column] = max(48, remaining * natural[column] / wanted) }
        return widths
    }

    private func heights(_ subviews: Subviews, widths: [CGFloat]) -> [CGFloat] {
        (0..<(subviews.count / columns)).map { row in
            (0..<columns).map { subviews[row * columns + $0].sizeThatFits(ProposedViewSize(width: widths[$0], height: nil)).height }.max() ?? 0
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard columns > 0, subviews.isEmpty == false else { return .zero }
        let columnWidths = widths(subviews, within: proposal.width ?? .infinity)
        return CGSize(width: columnWidths.reduce(0, +), height: heights(subviews, widths: columnWidths).reduce(0, +))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard columns > 0, subviews.isEmpty == false else { return }
        let columnWidths = widths(subviews, within: bounds.width)
        var y = bounds.minY
        for (row, height) in heights(subviews, widths: columnWidths).enumerated() {
            var x = bounds.minX
            for column in 0..<columns {
                subviews[row * columns + column].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(width: columnWidths[column], height: height))
                x += columnWidths[column]
            }
            y += height
        }
    }
}

/// An agent's text: its lines and bullets run together as one text, so a drag selects across them (separate texts select only within
/// themselves), and a fenced code block is a view of its own between two of those, which a selection does not cross. ponytail: a bullet
/// that wraps goes back to the margin and does not hang under its text; an NSTextView with paragraph styles would hang it and select
/// across the code blocks too, if that is missed.
struct MarkdownView: View {
    let text: String
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    private enum Segment {
        case text(AttributedString)
        case code(String?, String?, String)
        case table(MarkdownTable)
        case quote(AttributedString)
        case rule
    }

    /// Inline code, and a link, as a chip: the theme's accent for the text over a stronger tint of it, with a little air at both ends (a non-breaking
    /// space inside the tint), so a name in a sentence stands out of it.
    private func chipped(_ line: AttributedString) -> AttributedString {
        let ink = dark ? Color.themeAccent.mix(with: .white, by: 0.3) : Color.themeAccent.mix(with: .black, by: 0.25)
        var out = AttributedString()
        for run in line.runs {
            var piece = AttributedString(line[run.range])
            if let link = run.link {
                // a link is the same chip as inline code, ending in an arrow that says it leaves the app; a bare address is cut to its host and tail
                let shown = String(line[run.range].characters)
                if shown == link.absoluteString { piece = AttributedString(linkLabel(link), attributes: piece.runs.first?.attributes ?? AttributeContainer()) }
                piece = AttributedString("\u{00A0}") + piece + AttributedString("\u{00A0}\u{2197}\u{FE0E}\u{00A0}")
                piece.foregroundColor = ink
                piece.backgroundColor = Color.themeAccent.opacity(dark ? 0.26 : 0.16)
                piece.link = link
            } else if run.inlinePresentationIntent?.contains(.code) == true {
                piece = AttributedString("\u{00A0}") + piece + AttributedString("\u{00A0}")
                piece.foregroundColor = ink
                piece.backgroundColor = Color.themeAccent.opacity(dark ? 0.26 : 0.16)
            }
            out.append(piece)
        }
        return out
    }

    private var segments: [Segment] {
        var segments: [Segment] = []
        var run: AttributedString?
        func add(_ piece: AttributedString) {
            if var open = run { open.append(AttributedString("\n")); open.append(piece); run = open } else { run = piece }
        }
        for block in markdownBlocks(text) {
            switch block {
            case .line(let line): add(chipped(line))
            case .bullet(let level, let line):
                var bullet = AttributedString(String(repeating: "\u{2003}\u{2003}", count: level) + "•\u{2002}")
                bullet.foregroundColor = .secondary
                bullet.append(chipped(line))
                add(bullet)
            case .numbered(let level, let number, let line):
                var marker = AttributedString(String(repeating: "\u{2003}\u{2003}", count: level) + "\(number).\u{2002}")
                marker.foregroundColor = .secondary
                marker.append(chipped(line))
                add(marker)
            case .quote(let quoted):
                if let run { segments.append(.text(run)) }
                run = nil
                segments.append(.quote(chipped(quoted)))
            case .rule:
                if let run { segments.append(.text(run)) }
                run = nil
                segments.append(.rule)
            case .gap:
                // an empty line a little shorter than a text one
                var gap = AttributedString(" ")
                gap.font = .scaled(6)
                add(gap)
            case .code(let language, let file, let code):
                if let run { segments.append(.text(run)) }
                run = nil
                segments.append(.code(language, file, code))
            case .table(var table):
                if let run { segments.append(.text(run)) }
                run = nil
                table.header = table.header.map(chipped)
                table.rows = table.rows.map { $0.map(chipped) }
                segments.append(.table(table))
            }
        }
        if let run { segments.append(.text(run)) }
        return segments
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let text):
                    // only a text with a link needs to know where its links are drawn (for the hand); the rest stays plain
                    if text.runs.contains(where: { $0.link != nil }) { LinkedText(text: text) } else { Text(text).lineSpacing(4) }
                case .code(let language, let file, let code): CodeBlockView(language: language, file: file, code: code)
                case .table(let table): MarkdownTableView(table: table)
                case .quote(let quoted):
                    HStack(alignment: .top, spacing: 10) {
                        Capsule().fill(Color.secondary.opacity(0.4)).frame(width: 3)
                        Text(quoted).lineSpacing(4).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .fixedSize(horizontal: false, vertical: true).padding(.vertical, 2)
                case .rule: Divider().padding(.vertical, 6)
                }
            }
        }
        .font(.scaled(13))
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}

struct TranscriptItemView: View {
    let item: TranscriptItem
    @Binding var outputs: OutputFolds
    @AppStorage(AppPreferences.toolOutputKey) private var mode = AppPreferences.defaultToolOutput
    @AppStorage(AppPreferences.opensFailedCallsKey) private var opensFailed = AppPreferences.defaultOpensFailedCalls

    var body: some View {
        switch item {
        case .message(_, let text):
            Group {
                if let json = jsonMessage(text) { JSONMessageView(message: json) } else { MarkdownView(text: text) }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.12)))
        case .note(_, let text):
            Text(text).font(.scaled(12)).foregroundStyle(.secondary).textSelection(.enabled)
        case .error(_, let text):
            Text(text).font(.scaled(12)).foregroundStyle(.red).textSelection(.enabled)
        case .tool(let id, let card):
            // only what changes files is a card; the rest is a line of the log
            if card.kind == .edit {
                ToolCardView(card: card)
            } else if card.isSkill {
                SkillRowView(card: card)
            } else {
                ToolLineView(card: card, outputOpen: outputs.isOpen(id, card, mode: mode, opensFailed: opensFailed)) {
                    outputs.toggle(id, card, mode: mode, opensFailed: opensFailed)
                }
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
        Image(systemName: "chevron.right").font(.scaled(9, weight: .bold)).foregroundStyle(.tertiary)
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
            Text(duration ?? "").font(.scaled(11)).monospacedDigit().foregroundStyle(failed ? AnyShapeStyle(.red) : AnyShapeStyle(.tertiary)).lineLimit(1)
                .frame(width: LogMetrics.durationColumn, alignment: .trailing)
            Group {
                if status != .ok { ToolStatusView(status: status).font(.scaled(14)) }
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
            Image(systemName: card.kind.icon).font(.scaled(11)).foregroundStyle(card.status == .error ? .red : .secondary)
                .frame(width: LogMetrics.iconWidth, height: LogMetrics.iconWidth)
            HStack(spacing: 4) {
                Text(card.title).codeFont(12).lineLimit(1)
                    .truncationMode(card.kind == .shell ? .tail : .middle)
                if card.moreCommands > 0 {
                    Text("+\(card.moreCommands)").font(.scaled(11)).foregroundStyle(.tertiary).lineLimit(1).fixedSize()
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
    @AppStorage(AppPreferences.toolOutputKey) private var mode = AppPreferences.defaultToolOutput

    var body: some View {
        let open = groups.isOpen(id, mode: mode)
        VStack(alignment: .leading, spacing: 0) {
            Button { groups.toggle(id) } label: {
                ToolGroupHeader(calls: calls, open: open)
            }
            .buttonStyle(.plain)
            if open {
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
            Text(label).font(.scaled(12)).foregroundStyle(.secondary).lineLimit(1)
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
            Image(systemName: card.kind.icon).font(.scaled(9, weight: .bold)).foregroundStyle(.white)
                .frame(width: LogMetrics.iconWidth, height: LogMetrics.iconWidth).background(RoundedRectangle(cornerRadius: 5).fill(card.kind.color))
            Text(card.title).codeFont(12, weight: .medium).lineLimit(1).truncationMode(.middle)
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
    @AppStorage(AppPreferences.outputLengthKey) private var length = AppPreferences.defaultOutputLength

    var body: some View {
        let shown = length.visible(card.output, expanded: showAll)
        VStack(alignment: .leading, spacing: 0) {
            strip
            divider
            if shown.lines.isEmpty {
                Text("no output").font(.scaled(11.5)).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.vertical, 9)
            } else {
                MonoLines(lines: shown.lines, redFirst: card.failureLine != nil).textSelection(.enabled)
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
        .codeFont(11.5)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.12)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var divider: some View { Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 0.5) }

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
                    .buttonStyle(.plain).foregroundStyle(Color.themeAccent)
            }
            Spacer(minLength: 0)
            CopyButton(text: card.copyText)
        }
        .font(.scaled(11))
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
            .font(.scaled(11)).foregroundStyle(.secondary).contentShape(Rectangle())
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
                Text(reason).font(.scaled(12)).foregroundStyle(.red).lineLimit(2)
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
            Image(systemName: card.kind.icon).font(.scaled(11, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 20, height: 20).background(RoundedRectangle(cornerRadius: 6).fill(card.kind.color))
            HStack(spacing: 6) {
                Text(card.editName).font(.scaled(12, weight: .semibold)).lineLimit(1)
                if card.isNewFile {
                    Text("new").font(.scaled(9.5, weight: .semibold)).foregroundStyle(.green)
                        .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(Color.green.opacity(0.16)))
                }
                if card.editFolder.isEmpty == false {
                    Text(card.editFolder).codeFont(11).foregroundStyle(.tertiary)
                        .lineLimit(1).truncationMode(.head)
                }
            }
            .help(card.arg).frame(maxWidth: .infinity, alignment: .leading)
            if let diff = card.shownDiff {
                HStack(spacing: 4) {
                    Text("+\(diff.added)").foregroundStyle(.green)
                    Text("−\(diff.removed)").foregroundStyle(.red)
                }
                .font(.scaled(12, weight: .medium)).monospacedDigit()
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
            .codeFont(11.5)
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
    var style: DiffStyle = .unified

    var body: some View {
        let shown = visibleDiffRows(rows, expanded: showAll)
        Console {
            switch style {
            case .unified:
                ForEach(Array(shown.rows.enumerated()), id: \.offset) { _, row in line(row).background(background(row)) }
            case .split:
                ForEach(Array(splitDiffPairs(shown.rows).enumerated()), id: \.offset) { _, pair in
                    if let left = pair.left, left.sign == .hunk {
                        line(left).background(background(left))
                    } else {
                        HStack(spacing: 0) {
                            half(pair.left)
                            Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1)
                            half(pair.right)
                        }
                    }
                }
            }
            if rows.count > collapsedDiffRows {
                Button(showAll ? "Show less" : "Show \(shown.hidden) more \(shown.hidden == 1 ? "line" : "lines")") { showAll.toggle() }
                    .buttonStyle(.plain).font(.scaled(11)).foregroundStyle(Color.themeAccent)
                    .padding(.horizontal, 14).padding(.top, 7).padding(.bottom, 1)
            }
            if let cut {
                Text(cut).font(.scaled(11)).foregroundStyle(ConsoleColor.text.opacity(0.6))
                    .padding(.horizontal, 14).padding(.top, 7).padding(.bottom, 1)
            }
        }
    }

    private func line(_ row: DiffRow) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(sign(row.sign))
            Text(row.text).textSelection(.enabled).lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(color(row.sign))
        .padding(.horizontal, 14)
        .padding(.vertical, row.sign == .hunk ? 2 : 0)
    }

    /// One side of a split line; a side with no match stays empty.
    private func half(_ row: DiffRow?) -> some View {
        Group {
            if let row { line(row).background(background(row)) } else { Color.clear }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func background(_ row: DiffRow) -> Color {
        row.sign == .hunk ? Color.white.opacity(0.05) : color(row.sign).opacity(row.sign == .context ? 0 : 0.14)
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
