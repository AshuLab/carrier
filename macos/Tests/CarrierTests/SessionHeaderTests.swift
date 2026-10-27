@testable import CarrierCore
import SwiftUI
import Testing
@testable import Carrier

private func section(_ state: SessionSection.State, counts: SessionCounts? = SessionCounts(calls: 8, edits: 2, added: 42, removed: 8, tests: 1, errors: 2)) -> SessionSection {
    SessionSection(
        id: "a", state: state, agent: "Claude", initial: "C", role: "Fixer", place: "Round 2", counts: counts,
        timeLabel: state == .stopped ? nil : "3m 05s", openByDefault: true
    )
}

@MainActor private func size(_ section: SessionSection, open: Bool = true, width: CGFloat) throws -> CGSize {
    let renderer = ImageRenderer(content: SessionHeaderView(section: section, open: open).frame(width: width))
    renderer.scale = 2
    let image = try #require(renderer.cgImage)
    return CGSize(width: image.width, height: image.height)
}

// A header is one row whatever the session's state or the width of the centre column, with or without a counts line.
@MainActor @Test(arguments: [CGFloat(340), 560, 900])
func aHeaderKeepsItsHeightInEveryStateAndFolded(width: CGFloat) throws {
    let height = try size(section(.done), width: width).height
    for state in [SessionSection.State.running, .stopped, .done] {
        #expect(try size(section(state), width: width).height == height)
        #expect(try size(section(state), open: false, width: width).height == height)
    }
    #expect(try size(section(.done, counts: nil), width: width).height == height)
}

// A failed session's header is taller by the line of its failure, at most two for the longest detail the engine sends (300
// characters), and the same folded or open and at every width.
@MainActor @Test func aFailedHeaderGrowsByTheFailureLineAndNoMore() throws {
    var failed = section(.stopped)
    failed.failure = "usage_limit: " + String(repeating: "resets 12:40pm ", count: 20).prefix(287)
    let plain = try size(section(.stopped), width: 340).height
    let tall = try size(failed, width: 340).height
    #expect(tall > plain)
    for width in [CGFloat(340), 560, 900] {
        #expect(try size(failed, width: width).height <= tall)
        #expect(try size(failed, open: false, width: width).height == (try size(failed, width: width).height))
    }
}
