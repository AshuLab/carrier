import CarrierCore
import SwiftUI

/// A table of pipes, in the glass of the code blocks: a header row, a hairline between the rows, and columns sized to their text, the
/// wide ones sharing what is left when the table does not fit the message (their cells wrap).
struct MarkdownTableView: View {
    let table: MarkdownTable
    @State private var hovering = false
    @State private var copied = false
    @AppStorage(Preference.chatTextSize) private var size

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
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
        .overlay(alignment: .topTrailing) { copyMenu.opacity(hovering || copied ? 1 : 0).padding(Tokens.Space.s5) }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .contextMenu { copyButtons }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Tokens.Space.s3)
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
        // 12.5 of the 13 a message has, so a table keeps its place beside the text at any size
        let points = ChatText.clamped(CGFloat(size)) * 12.5 / 13
        let align: Alignment = switch table.aligns[column] {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
        return Text(text).font(.chat(points, weight: header ? .semibold : nil)).lineSpacing(points * 2 / 12.5)
            .multilineTextAlignment(table.aligns[column] == .trailing ? .trailing : table.aligns[column] == .center ? .center : .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: align)
            .padding(.horizontal, Tokens.Space.s12).padding(.vertical, Tokens.Space.s8)
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
