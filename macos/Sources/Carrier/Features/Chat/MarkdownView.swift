import CarrierCore
import SwiftUI

/// An agent's text: its lines and bullets run together as one text, so a drag selects across them (separate texts select only within
/// themselves), and a fenced code block is a view of its own between two of those, which a selection does not cross. ponytail: a bullet
/// that wraps goes back to the margin and does not hang under its text; an NSTextView with paragraph styles would hang it and select
/// across the code blocks too, if that is missed.
struct MarkdownView: View {
    let text: String
    @Environment(\.colorScheme) private var scheme
    @AppStorage(Preference.chatTextSize) private var size
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
