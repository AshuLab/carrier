import AppKit
import CarrierCore
import SwiftUI

/// The rows of an open session under its row: the agent's messages, notes and errors as the chat draws them, and each run of its
/// calls as the chat's work card (`ChatToolGroupView`), so the epic and a session read the same. They are the content of a `Section` of the
/// Agent output tab's lazy stack, so only the rows on screen are built. `flipped` is what the person opened or folded, by id, for every card
/// of the tab (the lazy stack recreates rows, so a row does not keep it itself).
struct TranscriptRows: View {
    let content: TranscriptBody
    @Binding var flipped: Set<String>
    @AppStorage(AppPreferences.toolOutputKey) private var mode = AppPreferences.defaultToolOutput
    @AppStorage(AppPreferences.showsReasoningKey) private var showsReasoning = AppPreferences.defaultShowsReasoning

    var body: some View {
        switch content {
        case .loading:
            LoadingRow().sessionRow()
        case .items(let items) where items.isEmpty:
            EmptyStateView(state: .noActivity).frame(minHeight: 170).sessionRow()
        case .items(let items):
            ForEach(visibleFlow(items, mode: mode, showsReasoning: showsReasoning)) { FlowItemView(flow: $0, flipped: $flipped).sessionRow() }
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

/// One entry of the log with its margins: the agent's message, a note, an error, a skill, a run of calls as the chat's work card or a slice
/// row (a subagent's own steps are in its view).
struct FlowItemView: View {
    let flow: FlowItem
    @Binding var flipped: Set<String>
    @AppStorage(AppPreferences.toolOutputKey) private var mode = AppPreferences.defaultToolOutput
    @AppStorage(AppPreferences.opensFailedCallsKey) private var opensFailed = AppPreferences.defaultOpensFailedCalls

    var body: some View {
        switch flow {
        case .message(_, let text):
            Group {
                if let json = jsonMessage(text) { JSONMessageView(message: json) } else { MarkdownView(text: text) }
            }
            .padding(.horizontal, LogMetrics.iconColumn).padding(.vertical, 8)
        case .note(_, let text):
            if let published = publishedNote(text) {
                PublishedNoteRow(note: published)
            } else {
                Text(text).font(.scaled(12)).foregroundStyle(.secondary).textSelection(.enabled)
                    .padding(.horizontal, LogMetrics.iconColumn).padding(.vertical, 6)
            }
        case .error(_, let text):
            BannerView(banner: failedTurnBanner(agent: "", error: text), copyDetails: true, retry: nil)
                .padding(.horizontal, LogMetrics.iconColumn).padding(.vertical, 6)
        case .skill(_, let call):
            SkillRowView(call: call).padding(.horizontal, LogMetrics.iconColumn).padding(.vertical, 4)
        case .tools(let id, let group, let live):
            // the rows of the subagents the run launched (a subagent view's own groups have them; the epic's have none)
            VStack(alignment: .leading, spacing: 6) {
                ChatToolGroupView(id: "t\(id)", group: group, live: live, startsOpen: mode == .expanded || (opensFailed && group.failed > 0), flipped: $flipped)
                ForEach(group.subagents) { SubagentRowView(subagent: $0) }
            }
            .padding(.horizontal, LogMetrics.iconColumn).padding(.vertical, 4)
        case .slice(let lane):
            SliceCardView(lane: lane)
                .padding(.horizontal, LogMetrics.iconColumn).padding(.vertical, 4)
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
    @AppStorage(AppPreferences.chatTextSizeKey) private var size = Double(ChatText.defaultSize)
    @AppStorage(AppPreferences.chatLineSpacingKey) private var spacing = AppPreferences.defaultChatLineSpacing

    var body: some View {
        Text(lit)
            // no `contentTransition(.interpolate)` here: interpolating a text whose runs have a background (the chips) leaves ghost rectangles of
            // them over the other lines while the lit link fades, so the chip changes at once
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { places = Self.place(links: text, width: $0, size: ChatText.clamped(CGFloat(size)), spacing: spacing) }
            .onChange(of: text) { places = [] }
            .onChange(of: size) { places = [] }
            .onChange(of: spacing) { places = [] }
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
    private static func place(links text: AttributedString, width: CGFloat, size: CGFloat, spacing: ChatLineSpacing) -> [(link: Int, rect: CGRect)] {
        guard width > 0 else { return [] }
        let base = NSFont.chat(size)
        let ns = NSMutableAttributedString()
        var ranges: [NSRange] = []
        for run in text.runs {
            let piece = String(text[run.range].characters)
            var font = base
            if run.font != nil {
                font = .chat(size * 6 / 13) // the short empty line
            } else if let intent = run.inlinePresentationIntent {
                if intent.contains(.code) { font = .chat(size, mono: true) }
                if intent.contains(.stronglyEmphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
                if intent.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
            }
            if run.link != nil { ranges.append(NSRange(location: ns.length, length: piece.utf16.count)) }
            ns.append(NSAttributedString(string: piece, attributes: [.font: font]))
        }
        let style = NSMutableParagraphStyle()
        style.lineSpacing = spacing.extra(forSize: size)
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
        .workCard()
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
            Glyph(copied ? .check : .copy, size: 11).foregroundStyle(copied ? Color.green : .secondary)
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
    @AppStorage(AppPreferences.chatTextSizeKey) private var size = Double(ChatText.defaultSize)
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
        // kept low on purpose: a message full of names and links is a lot of colour, so the tint is faint and the text only a little lighter than the accent
        let ink = dark ? Color.themeAccent.mix(with: .white, by: 0.12) : Color.themeAccent.mix(with: .black, by: 0.12)
        let tint = Color.themeAccent.opacity(dark ? 0.13 : 0.09)
        var out = AttributedString()
        for run in line.runs {
            var piece = AttributedString(line[run.range])
            if let link = run.link {
                // a link is the same chip as inline code, ending in an arrow that says it leaves the app; a bare address is shown whole
                piece = AttributedString("\u{00A0}") + piece + AttributedString("\u{00A0}\u{2197}\u{FE0E}\u{00A0}")
                piece.foregroundColor = ink
                piece.backgroundColor = tint
                piece.link = link
            } else if run.inlinePresentationIntent?.contains(.code) == true {
                piece = AttributedString("\u{00A0}") + piece + AttributedString("\u{00A0}")
                piece.foregroundColor = ink
                piece.backgroundColor = tint
            }
            out.append(piece)
        }
        return out
    }

    private var segments: [Segment] {
        let signpost = Signposts.render.beginInterval("markdown", id: Signposts.render.makeSignpostID())
        defer { Signposts.render.endInterval("markdown", signpost, "\(text.utf8.count) bytes") }
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
                gap.font = .chat(ChatText.clamped(CGFloat(size)) * 6 / 13)
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
                    if text.runs.contains(where: { $0.link != nil }) { LinkedText(text: text) } else { Text(text) }
                case .code(let language, let file, let code): CodeBlockView(language: language, file: file, code: code)
                case .table(let table): MarkdownTableView(table: table)
                case .quote(let quoted):
                    HStack(alignment: .top, spacing: 10) {
                        Capsule().fill(Color.secondary.opacity(0.4)).frame(width: 3)
                        Text(quoted).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .fixedSize(horizontal: false, vertical: true).padding(.vertical, 2)
                case .rule: Divider().padding(.vertical, 6)
                }
            }
        }
        .chatText()
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}

/// The disclosure chevron of every row that opens. It turns in 0.12 s, or just jumps under Reduce Motion.
struct LogChevron: View {
    let open: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Glyph(.chevronRight, size: 9).foregroundStyle(.tertiary)
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

/// A code change the agent published ("created 946 (the-branch)"): a quiet line with the verb, the pull request as a link and the
/// branch cut in the middle, its whole name in the tooltip.
struct PublishedNoteRow: View {
    let note: PublishedNote
    @Environment(\.epicRepo) private var repo

    var body: some View {
        HStack(spacing: 6) {
            Glyph(.gitPullRequest, size: 10).foregroundStyle(.tertiary)
            Text(note.verb).foregroundStyle(.secondary)
            if let number = note.number {
                PullRequestChip(number: number, dot: nil, url: repo.map { "https://github.com/\($0)/pull/\(number)" })
            } else {
                Text(note.identifier).foregroundStyle(.secondary)
            }
            if let branch = note.branch {
                Text(branch).codeFont(11).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle).help(branch)
            }
            Spacer(minLength: 0)
        }
        .font(.scaled(12)).lineLimit(1)
        .padding(.horizontal, LogMetrics.iconColumn).padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

/// A call to the `Skill` tool, a milestone of its own: one line of the work card's family (its tile, "Skill", the skill's name, how long
/// it took), with nothing to open.
struct SkillRowView: View {
    let call: ToolCall

    private var failed: Bool { call.status == .failed }

    var body: some View {
        HStack(spacing: LogMetrics.gap) {
            Glyph(call.kind.icon, size: 9, bold: true).foregroundStyle(.white)
                .frame(width: LogMetrics.iconWidth, height: LogMetrics.iconWidth).background(RoundedRectangle(cornerRadius: 5).fill(call.kind.color))
            Text("Skill").fontWeight(.semibold).foregroundStyle(failed ? Color.red : .primary)
            Text(call.arg).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            if failed { Text("failed").foregroundStyle(.red) } else if let ms = call.durationMs { Text(formatCallDuration(ms)).foregroundStyle(.tertiary).monospacedDigit() }
        }
        .font(.scaled(12.5)).lineLimit(1)
        .padding(.horizontal, 10).frame(height: LogMetrics.skillRow)
        .workCard()
        .help(call.arg)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(callAccessibilityLabel(call))
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
                Glyph(icon, size: 12).foregroundStyle(Color.red)
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
                Glyph(copied ? .check : .copy).frame(width: 12, height: 14)
                Text(copied ? "Copied" : "Copy").frame(width: 40, alignment: .leading)
            }
            .font(.scaled(11)).foregroundStyle(.secondary).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

extension ToolKind {
    /// The colour of the icon box of a milestone: blue for an edit, grey for a skill. The calls have a bare glyph.
    var color: Color {
        switch self {
        case .edit: .blue
        case .read, .search, .shell, .other, .mcp: Color(white: 0.43)
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
            LazyVStack(alignment: .leading, spacing: 0) {
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
