import CarrierCore
import SwiftUI

/// "PR #736" with a dot for its state and an arrow when it opens GitHub; a link when it has a `link`.
public struct PullRequestChip: View {
    let number: Int
    let dot: Color?
    let link: URL?

    public init(number: Int, dot: Color?, link: URL?) { self.number = number; self.dot = dot; self.link = link }

    public var body: some View {
        if let link {
            Link(destination: link) { label }.buttonStyle(.plain).help(link.absoluteString)
        } else {
            label
        }
    }

    private var label: some View {
        HStack(spacing: Tokens.Space.s5) {
            if let dot { Circle().fill(dot).frame(width: 7, height: 7) }
            Text(Copy.piecePullRequest(number: String(number))).monospacedDigit()
            if link != nil { Glyph(.arrowUpRight, size: 9).foregroundStyle(.tertiary) }
        }
        .scaledFont(12).foregroundStyle(.secondary).lineLimit(1).fixedSize()
    }
}
