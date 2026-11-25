import CarrierCore
import SwiftUI

/// Lines of code or output as the monospace settings draw them: wrapped, or whole and scrolling sideways; with a column of line numbers
/// when asked. The font is the caller's (`codeFont`), so the lines take whatever it sets. `redFirst` draws the first line red.
public struct MonoLines: View {
    let lines: [String]
    var redFirst = false
    /// Whether lines wrap or scroll sideways, and whether they are numbered.
    let monospace: MonospaceSettings

    public init(lines: [String], redFirst: Bool = false, monospace: MonospaceSettings) { self.lines = lines; self.redFirst = redFirst; self.monospace = monospace }

    public var body: some View {
        if monospace.wrapLongLines {
            rows
        } else {
            ScrollView(.horizontal) { rows.fixedSize(horizontal: true, vertical: false) }
        }
    }

    @ViewBuilder private var rows: some View {
        if monospace.lineNumbers {
            VStack(alignment: .leading, spacing: Tokens.Space.none) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    HStack(alignment: .top, spacing: Tokens.Space.s12) {
                        // the widest number sizes the column
                        ZStack(alignment: .trailing) {
                            Text("\(lines.count)").hidden()
                            Text("\(index + 1)")
                        }
                        .opacity(0.4).textSelection(.disabled)
                        if redFirst && index == 0 { Text(line).foregroundStyle(.red) } else { Text(line.isEmpty ? " " : line) }
                    }
                }
            }
        } else if redFirst, let first = lines.first {
            let rest = lines.count > 1 ? "\n" + lines.dropFirst().joined(separator: "\n") : ""
            Text("\(Text(first).foregroundStyle(.red))\(rest)")
        } else {
            Text(lines.joined(separator: "\n"))
        }
    }
}
