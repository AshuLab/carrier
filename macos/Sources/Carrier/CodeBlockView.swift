import CarrierCore
import SwiftUI

/// A fenced block of an agent's message: the language by name (or the file it is from) over the code, coloured by what each piece is. A diff
/// tints its added and removed lines, a shell session greys its prompts, and Copy, which shows when the pointer is over the block, takes
/// what can be pasted. Numbers show from five lines, a block of more than 25 folds under Show more lines, and long lines scroll sideways
/// or wrap, as the monospace settings say.
struct CodeBlockView: View {
    let language: String?
    var file: String?
    let code: String
    /// From which line the block folds, and how many lines a fold must hide to be worth its button (a message's block spares itself a
    /// fold of a few lines; a tool's output folds where the person's Output length setting says).
    var foldAfter = 25
    var spare = 4

    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false
    @State private var expanded = false
    @State private var width: CGFloat = 0

    private static let numbersFrom = 5

    /// Long lines wrap or scroll sideways as the monospace settings say.
    private var wrapped: Bool { MonospaceStyle.shared.settings.wrapLongLines }
    private var resolved: String? { resolvedCodeLanguage(language, code: code) }
    private var lines: [String] { code.components(separatedBy: "\n") }
    /// A fold hiding two lines is not worth a button.
    private var foldable: Bool { lines.count > foldAfter + spare }
    private var folds: Bool { foldable && expanded == false }
    private var shownLines: [String] { folds ? Array(lines.prefix(foldAfter)) : lines }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView(.horizontal) { content }
                .scrollDisabled(wrapped)
            if foldable { foldButton }
        }
        // the header and the fold are tints inside the shape; glass draws the edge, so there is no border to meet the corners badly
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .glassEffect(.regular.tint(scheme == .dark ? Color.black.opacity(0.3) : nil), in: .rect(cornerRadius: 12))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { hovering = inside } }
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(spacing: 8) {
            if let file {
                Text(file).font(.scaled(11.5, weight: .medium)).lineLimit(1).truncationMode(.head)
                Text(codeLanguageName(language, resolved: resolved)).font(.scaled(11)).foregroundStyle(.tertiary)
            } else {
                Text(codeLanguageName(language, resolved: resolved)).font(.scaled(11.5)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            CodeCopyButton(text: codeCopyText(code, language: resolved), visible: hovering)
        }
        .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 4)
        .background(Color.primary.opacity(0.045))
    }

    @ViewBuilder private var content: some View {
        if resolved == "diff" { diff } else { highlighted }
    }

    @ViewBuilder private var highlighted: some View {
        if wrapped, lines.count >= Self.numbersFrom {
            wrappedNumbered
        } else {
            HStack(alignment: .top, spacing: 12) {
                if lines.count >= Self.numbersFrom {
                    Text((1...shownLines.count).map(String.init).joined(separator: "\n"))
                        .foregroundStyle(.tertiary).multilineTextAlignment(.trailing).textSelection(.disabled).accessibilityHidden(true)
                }
                Text(attributed(codeTokens(shownLines.joined(separator: "\n"), language: resolved)))
            }
            .codeFont(11.5)
            .textSelection(.enabled)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .fixedSize(horizontal: wrapped == false, vertical: true)
            .frame(maxWidth: wrapped ? .infinity : nil, alignment: .leading)
        }
    }

    /// Wrapped lines under numbers: one text over a row a line, so a drag selects across lines as in any text and a number stays beside the
    /// first row of its line however many rows the line takes. The rows are there only for their size (their text is hidden, and wraps as the
    /// text over them does) and carry the numbers.
    private var wrappedNumbered: some View {
        layered(attributed(codeTokens(shownLines.joined(separator: "\n"), language: resolved)), rows: shownLines, numbered: true)
    }

    /// The text of a block over a row per line: `numbered` draws the line numbers in the rows, `tint` and `bar` a row's background and the
    /// bar at its left edge, by row (a diff's added and removed lines).
    private func layered(
        _ text: AttributedString, rows: [String], numbered: Bool, tint: [Color] = [], bar: [Color?] = []
    ) -> some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .top, spacing: 12) {
                    if numbered {
                        ZStack(alignment: .trailing) {
                            Text("\(rows.count)").hidden()
                            Text("\(index + 1)").foregroundStyle(.tertiary)
                        }
                        .textSelection(.disabled).accessibilityHidden(true)
                    }
                    Text(row.isEmpty ? " " : row).hidden().accessibilityHidden(true).textSelection(.disabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 14)
                .frame(minWidth: wrapped ? 0 : width, maxWidth: .infinity, alignment: .leading)
                .background(index < tint.count ? tint[index] : .clear)
                .overlay(alignment: .leading) { if index < bar.count, let color = bar[index] { Rectangle().fill(color).frame(width: 2) } }
            }
        }
        .overlay(alignment: .topLeading) {
            HStack(alignment: .top, spacing: 12) {
                if numbered { Text("\(rows.count)").hidden().accessibilityHidden(true) }
                Text(text).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
        }
        .codeFont(11.5)
        .textSelection(.enabled)
        .padding(.vertical, 10)
        .fixedSize(horizontal: wrapped == false, vertical: true)
    }

    /// The air between the lines that a text puts itself and rows do not: a block keeps one line height wrapped or not.
    private var rowSpacing: CGFloat {
        let mono = MonospaceStyle.shared.settings
        return mono.lineHeight.extraSpacing(forSize: mono.font(11.5).pointSize)
    }

    private var diff: some View {
        let kinds = diffLines(code)
        var text = AttributedString()
        for (index, line) in shownLines.enumerated() {
            var piece = AttributedString(line + (index == shownLines.count - 1 ? "" : "\n"))
            switch kinds[index] {
            case .hunk: piece.foregroundColor = Color.blue.opacity(0.85)
            case .meta: piece.foregroundColor = .secondary
            default: break
            }
            text.append(piece)
        }
        return layered(text, rows: shownLines, numbered: false, tint: kinds.map(tint), bar: kinds.map(bar))
    }

    private var foldButton: some View {
        Button { withAnimation(.smooth(duration: 0.2)) { expanded.toggle() } } label: {
            Text(expanded ? "Show less" : "Show \(lines.count - foldAfter) more \(lines.count - foldAfter == 1 ? "line" : "lines")")
                .font(.scaled(11.5)).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 7).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.primary.opacity(0.04))
        .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5) }
    }

    private func tint(_ kind: DiffLineKind) -> Color {
        switch kind {
        case .added: Color.green.opacity(0.14)
        case .removed: Color.red.opacity(0.14)
        default: .clear
        }
    }

    private func bar(_ kind: DiffLineKind) -> Color? {
        switch kind {
        case .added: .green
        case .removed: .red
        default: nil
        }
    }

    private func attributed(_ tokens: [CodeToken]) -> AttributedString {
        var out = AttributedString()
        for token in tokens {
            var piece = AttributedString(token.text)
            if let color = CodeColors.color(token.kind, dark: scheme == .dark) { piece.foregroundColor = color }
            out.append(piece)
        }
        return out
    }
}

/// The colours of the pieces of code: a palette for each look, readable on the block's tint.
private enum CodeColors {
    static func color(_ kind: CodeTokenKind, dark: Bool) -> Color? {
        switch kind {
        case .plain: nil
        case .prompt: .secondary.opacity(0.7)
        case .keyword: dark ? rgb(0xC792EA) : rgb(0x8250DF)
        case .string: dark ? rgb(0xA8E08A) : rgb(0x1A7F37)
        case .number: dark ? rgb(0xF2A65A) : rgb(0xB35900)
        case .comment: dark ? rgb(0x8A83A8) : rgb(0x6E7781)
        case .function: dark ? rgb(0x7CC4FF) : rgb(0x0969DA)
        case .type: dark ? rgb(0xFFD479) : rgb(0x9A6700)
        }
    }

    private static func rgb(_ hex: UInt32) -> Color {
        Color(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// The block's copy button: an icon that shows with the pointer over the block, and a green check for a moment once it copied.
private struct CodeCopyButton: View {
    let text: String
    let visible: Bool
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
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.scaled(11, weight: copied ? .semibold : .regular)).foregroundStyle(copied ? Color.green : Color.secondary)
                .frame(width: 26, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Copy the code").accessibilityLabel("Copy the code")
        .opacity(visible || copied ? 1 : 0)
    }
}
