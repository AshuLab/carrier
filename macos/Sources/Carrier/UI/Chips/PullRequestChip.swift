import CarrierCore
import SwiftUI

/// "PR #736" with a dot for its state and an arrow when it opens GitHub; a link when it has a `link`.
struct PullRequestChip: View {
    let number: Int
    let dot: Color?
    let link: URL?

    var body: some View {
        if let link {
            Link(destination: link) { label }.buttonStyle(.plain).help(link.absoluteString)
        } else {
            label
        }
    }

    private var label: some View {
        HStack(spacing: 5) {
            if let dot { Circle().fill(dot).frame(width: 7, height: 7) }
            Text("PR #\(number)").monospacedDigit()
            if link != nil { Glyph(.arrowUpRight, size: 9).foregroundStyle(.tertiary) }
        }
        .font(.scaled(12)).foregroundStyle(.secondary).lineLimit(1).fixedSize()
    }
}
