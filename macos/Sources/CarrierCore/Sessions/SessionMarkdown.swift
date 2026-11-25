import Foundation

/// The text with each web address in it as a link; only http and https survive `browserURL`.
public func linkedText(_ text: String) -> AttributedString { withWebLinks(AttributedString(text)) }

/// `text` with its web addresses as links, and any other link it already had (a Markdown one) taken away: the agent writes
/// this text, so only http and https may open.
private func withWebLinks(_ text: AttributedString) -> AttributedString {
    var linked = text
    for run in text.runs {
        if let link = run.link, browserURL(link.absoluteString) == nil { linked[run.range].link = nil }
    }
    let plain = String(text.characters)
    let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    for match in detector?.matches(in: plain, range: NSRange(plain.startIndex..., in: plain)) ?? [] {
        guard let url = match.url, let link = browserURL(url.absoluteString), let range = Range(match.range, in: plain),
              let start = AttributedString.Index(range.lowerBound, within: linked), let end = AttributedString.Index(range.upperBound, within: linked)
        else { continue }
        linked[start..<end].link = link
    }
    return linked
}

/// A line of an agent's message as the view lays it out.
public enum MarkdownBlock: Equatable {
    case line(AttributedString)
    /// A `- ` list item; `level` is how many steps of two spaces it is indented.
    case bullet(level: Int, AttributedString)
    /// A fenced block: `language` is what follows the opening fence, nil when nothing does, and `file` the path the fence gives
    /// ("ts src/a.ts"). Its text is kept as written.
    case code(language: String?, file: String? = nil, String)
    /// A blank line, once however many there were.
    case gap
    /// A `1. ` list item, with the number it was written with.
    case numbered(level: Int, number: Int, AttributedString)
    /// Lines that start with `>`, together as one block (its lines joined by newlines).
    case quote(AttributedString)
    /// A line of only `---`, `***` or `___`.
    case rule
    /// A table of pipes (`| a | b |` over `|---|---|`): its header, a row of cells per line after it, and how each column aligns.
    case table(MarkdownTable)
}

public struct MarkdownTable: Equatable {
    public enum Align: Equatable { case leading, center, trailing }
    public var header: [AttributedString]
    public var aligns: [Align]
    /// Every row has as many cells as the header: short ones are completed, long ones cut.
    public var rows: [[AttributedString]]

    private var plain: [[String]] { ([header] + rows).map { $0.map { String($0.characters) } } }

    /// Tab-separated, one line per row: what a spreadsheet takes when pasted.
    public var tsv: String {
        plain.map { $0.map { $0.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ") }.joined(separator: "\t") }.joined(separator: "\n")
    }

    /// As the pipes it was written with, the alignments in its separator line.
    public var markdown: String {
        func line(_ cells: [String]) -> String { "| " + cells.map { $0.replacingOccurrences(of: "|", with: "\\|") }.joined(separator: " | ") + " |" }
        let marks = aligns.map { align -> String in
            switch align {
            case .leading: "---"
            case .center: ":---:"
            case .trailing: "---:"
            }
        }
        return ([line(plain[0]), line(marks)] + plain.dropFirst().map(line)).joined(separator: "\n")
    }
}

/// The cells of a table line, without the pipes at its ends; `\|` is a pipe inside a cell.
private func tableCells(_ line: Substring) -> [String] {
    var text = line.trimmingCharacters(in: .whitespaces)
    if text.hasPrefix("|") { text.removeFirst() }
    if text.hasSuffix("|"), text.hasSuffix("\\|") == false { text.removeLast() }
    return text.replacingOccurrences(of: "\\|", with: "\u{0}").split(separator: "|", omittingEmptySubsequences: false)
        .map { $0.replacingOccurrences(of: "\u{0}", with: "|").trimmingCharacters(in: .whitespaces) }
}

/// The alignments a table's separator line says (`|---|:--:|--:|`), nil when the line is not a separator.
private func tableAligns(_ line: Substring) -> [MarkdownTable.Align]? {
    guard line.contains("|") || line.contains("---") else { return nil }
    var aligns: [MarkdownTable.Align] = []
    for cell in tableCells(line.drop { $0 == " " }) {
        let core = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        guard core.isEmpty == false, core.allSatisfy({ $0 == "-" }) else { return nil }
        aligns.append(cell.hasPrefix(":") && cell.hasSuffix(":") ? .center : cell.hasSuffix(":") ? .trailing : .leading)
    }
    return aligns.isEmpty ? nil : aligns
}

/// An agent's message as Markdown, a block per line: bold, italics, code and links inside the line, `- ` lists as bullets and
/// `#` headings as bold lines, which the inline parser leaves alone, and fenced code as a block of its own (one left open, as in a
/// message still being written, runs to the end), `1. ` lists, `>` quotes, rules and tables of pipes. ponytail: no nested blocks (a
/// list inside a quote is a quote line); a block parser if agents start writing those.
public func markdownBlocks(_ text: String) -> [MarkdownBlock] {
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    func inline(_ line: String) -> AttributedString {
        withWebLinks((try? AttributedString(markdown: line, options: options)) ?? AttributedString(line))
    }
    var blocks: [MarkdownBlock] = []
    var fence: (language: String?, file: String?, lines: [String])?
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    var index = 0
    while index < lines.count {
        let line = lines[index]
        index += 1
        let trimmed = line.drop { $0 == " " }
        let indent = line.count - trimmed.count
        if trimmed.hasPrefix("```") {
            if let open = fence {
                blocks.append(.code(language: open.language, file: open.file, open.lines.joined(separator: "\n")))
                fence = nil
            } else {
                let info = fenceInfo(String(trimmed.drop { $0 == "`" }))
                fence = (info.language, info.file, [])
            }
            continue
        }
        if fence != nil {
            fence?.lines.append(String(line))
            continue
        }
        if trimmed.allSatisfy(\.isWhitespace) {
            if blocks.isEmpty == false, blocks.last != .gap { blocks.append(.gap) }
        } else if trimmed.hasPrefix("|"), index < lines.count, let aligns = tableAligns(lines[index]), case let header = tableCells(trimmed), header.count == aligns.count {
            // the rows run while the lines have a pipe; a table still being written has the rows it has so far
            var rows: [[AttributedString]] = []
            index += 1
            while index < lines.count, lines[index].contains("|"), lines[index].allSatisfy(\.isWhitespace) == false {
                let cells = tableCells(lines[index].drop { $0 == " " })
                rows.append((0..<header.count).map { inline($0 < cells.count ? cells[$0] : "") })
                index += 1
            }
            blocks.append(.table(MarkdownTable(header: header.map { inline($0) }, aligns: aligns, rows: rows)))
        } else if trimmed.count >= 3, trimmed.allSatisfy({ "-*_ ".contains($0) }), Set(trimmed.filter { $0 != " " }).count == 1, trimmed.first != " " {
            blocks.append(.rule)
        } else if trimmed.hasPrefix(">") {
            let quoted = inline(String(trimmed.dropFirst().drop { $0 == " " }))
            if case .quote(var open)? = blocks.last {
                open.append(AttributedString("\n"))
                open.append(quoted)
                blocks[blocks.count - 1] = .quote(open)
            } else {
                blocks.append(.quote(quoted))
            }
        } else if case let digits = trimmed.prefix(while: \.isNumber), digits.isEmpty == false, digits.count <= 9, let number = Int(digits),
                  case let rest = trimmed.dropFirst(digits.count), rest.hasPrefix(". ") || rest.hasPrefix(") ") {
            blocks.append(.numbered(level: indent / 2, number: number, inline(String(rest.dropFirst(2)))))
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            blocks.append(.bullet(level: indent / 2, inline(String(trimmed.dropFirst(2)))))
        } else if trimmed.hasPrefix("#"), case let title = trimmed.drop(while: { $0 == "#" }).drop(while: { $0 == " " }), title.isEmpty == false {
            blocks.append(.line(inline("**\(title)**")))
        } else {
            blocks.append(.line(inline(String(line))))
        }
    }
    if let open = fence { blocks.append(.code(language: open.language, file: open.file, open.lines.joined(separator: "\n"))) }
    if blocks.last == .gap { blocks.removeLast() }
    return blocks
}
