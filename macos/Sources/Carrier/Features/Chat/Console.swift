import AppKit
import CarrierCore
import SwiftUI

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
