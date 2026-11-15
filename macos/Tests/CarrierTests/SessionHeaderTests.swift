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

// The row is the same height at every width of the centre column, in every state, open or folded: the hairlines give way, the text does not wrap.
@MainActor @Test(arguments: [CGFloat(480), 560, 900])
func aRowKeepsItsHeightAtEveryWidth(width: CGFloat) throws {
    for state in [SessionSection.State.running, .stopped, .done] {
        for open in [true, false] {
            #expect(try size(section(state), open: open, width: width).height == (try size(section(state), open: open, width: 900).height))
        }
    }
}

// A profile adds nothing to the height: its name takes the tool's place on the first line, and the second line is there either way.
@MainActor @Test func aProfileDoesNotChangeTheHeight() throws {
    var plain = section(.done)
    plain.model = "claude-sonnet-5-5"
    var named = plain
    named.profile = "acme-author"
    named.account = "pro"
    named.effort = "high"
    #expect(try size(named, width: 560).height == (try size(plain, width: 560).height))
}

// A failed session's row is taller by the reason, at most two lines for the longest detail the engine sends (300 characters), and the
// same at every width.
@MainActor @Test func aFailedRowGrowsByTheReasonAndNoMore() throws {
    var failed = section(.stopped)
    failed.failure = "usage_limit: " + String(repeating: "resets 12:40pm ", count: 20).prefix(287)
    let plain = try size(section(.stopped), width: 560).height
    let tall = try size(failed, width: 560).height
    #expect(tall > plain)
    // two lines of 12 pt text at scale 2, with the line's own spacing
    #expect(tall - plain <= 2 * 2 * 20)
    for width in [CGFloat(480), 900] {
        #expect(try size(failed, width: width).height <= tall)
    }
}
