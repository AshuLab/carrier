@testable import CarrierCore
import SwiftUI
import Testing
@testable import Carrier

private func lane(_ state: SubagentState = .finished, lane: Int? = 1) -> LaneSection {
    LaneSection(
        id: "a", startId: 1, title: "Socket client", sliceTitle: "Socket client", state: state, duration: 180_000, startedAt: 0, endedAt: state == .running ? nil : 180_000,
        resumes: 0, timeLabel: state == .running ? "since 14:02" : "14:02–14:05",
        counts: SessionCounts(calls: 4), items: [], slice: 653, laneNumber: lane, pullRequest: "PR #670 merged", prNumber: 670, prState: "merged"
    )
}

@MainActor private func height(_ lanes: [LaneSection], width: CGFloat = 480) throws -> Int {
    let card = SliceCardView(lane: lanes[0])
    let renderer = ImageRenderer(content: card.frame(width: width))
    renderer.scale = 2
    return try #require(renderer.cgImage).height
}

// A closed slice is one row of two lines; the card is as tall done or failed, with or without a number or a pull request.
@MainActor @Test func aSliceCardKeepsItsHeightWhateverTheStateOfItsRow() throws {
    let base = try height([lane()])
    #expect(base >= 2 * (18 + 20))
    #expect(try height([lane(.failed)]) == base)
    var untitled = lane()
    untitled.slice = nil
    #expect(try height([untitled]) == base)
    var bare = lane()
    (bare.prNumber, bare.prState) = (nil, nil)
    #expect(try height([bare]) == base)
    var untimed = lane()
    (untimed.timeLabel, untimed.duration) = (nil, nil)
    #expect(try height([untimed]) == base)
}

// At a narrow width the row keeps one line for its title and its numbers: the chip and the chevron never push the title out.
@MainActor @Test func aNarrowSliceCardStillDrawsEveryRow() throws {
    let busy = LaneSection(
        id: "a", startId: 1, title: "Socket client", sliceTitle: "Socket client", state: .finished, duration: 180_000, startedAt: 0, endedAt: 180_000,
        resumes: 2, timeLabel: "14:02–14:05",
        counts: SessionCounts(calls: 12, edits: 3, added: 42, removed: 8, tests: 2, errors: 1), items: [], slice: 653, laneNumber: 1, pullRequest: "PR #670 merged",
        prNumber: 670, prState: "merged"
    )
    #expect(try height([busy], width: 300) >= (try height([lane()], width: 480)))
    #expect(try height([lane()], width: 300) >= (try height([lane()], width: 480)))
    var stepping = lane(.running)
    stepping.lastStep = "Bash"
    #expect(try height([stepping], width: 300) >= (try height([lane()], width: 480)))
}

// The findings card is its 30 pt line and a divider and a row for each finding; a fixed one and one with no id or link are as tall as any
// other when the text is one line, and a card with no findings is the line alone.
@MainActor @Test func aFindingsCardIsItsLineAndOneRowPerFinding() throws {
    func card(_ rows: [FindingRow]) -> FindingsCard {
        FindingsCard(round: 1, verdict: .changesRequested, title: "Changes requested", summary: "", rows: rows, prNumber: 743, prURL: nil)
    }
    func row(id: String? = "b1", mark: FindingMark? = .new, url: String? = "https://example.test/1") -> FindingRow {
        FindingRow(kind: .blocker, id: id, text: "One line", mark: mark, approximate: false, url: url)
    }
    func height(_ card: FindingsCard) throws -> Int {
        let renderer = ImageRenderer(content: FindingsCardView(card: card, reviewer: nil, verification: nil, evidenceOpen: false, toggleEvidence: {}).frame(width: 480))
        renderer.scale = 2
        return try #require(renderer.cgImage).height
    }
    let line = try height(card([]))
    #expect(line == 60)
    let one = try height(card([row()]))
    #expect(one > line)
    #expect(try height(card([row(mark: .fixed)])) == one)
    #expect(try height(card([row(mark: .carried)])) == one)
    #expect(try height(card([row(id: nil, mark: nil, url: nil)])) <= one)
    #expect(try height(card([row(), row()])) == one + (one - line))
}

// An approval folds its suggestions behind one 32 pt line; with the verification the card has a 30 pt foot, and open, the evidence.
@MainActor @Test func anApprovedReviewFoldsItsSuggestionsAndTheVerificationIsItsFoot() throws {
    let card = FindingsCard(
        round: 2, verdict: .ready, title: "Ready", summary: "0 blockers · 2 suggestions",
        rows: [FindingRow(kind: .suggestion, id: "a", text: "One line", mark: nil, approximate: false, url: nil)], prNumber: nil, prURL: nil
    )
    func height(verification: ResultCard.CI?, open: Bool = false) throws -> Int {
        let view = FindingsCardView(card: card, reviewer: "tassadar-agent", verification: verification, evidenceOpen: open, toggleEvidence: {})
        let renderer = ImageRenderer(content: view.frame(width: 480))
        renderer.scale = 2
        return try #require(renderer.cgImage).height
    }
    let folded = try height(verification: nil)
    let ci = ResultCard.CI(verdict: "passed", evidence: "pnpm test: 12 passed")
    #expect(try height(verification: ci) == folded + 2 * 30 + 2)
    #expect(try height(verification: ci, open: true) > folded + 2 * 30)
}
