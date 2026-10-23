@testable import CarrierCore
import SwiftUI
import Testing
@testable import Carrier

private func lane(_ state: SubagentState = .finished, lane: Int? = 1) -> LaneSection {
    LaneSection(
        id: "a", startId: 1, title: "Socket client", sliceTitle: "Socket client", state: state, duration: 180_000, startedAt: 0, endedAt: state == .running ? nil : 180_000,
        resumes: 0, timeLabel: state == .running ? "since 14:02" : "14:02–14:05",
        counts: SessionCounts(calls: 4), items: [], slice: 653, laneNumber: lane, pullRequest: "PR #670 merged"
    )
}

@MainActor private func height(_ lane: LaneSection, open: Bool) throws -> Int {
    let renderer = ImageRenderer(content: LaneHeaderView(lane: lane, open: open).frame(width: 480))
    renderer.scale = 2
    return try #require(renderer.cgImage).height
}

// A slice's row is two lines, 28 + at least 18 + 6 below, with no surface; the same height folded or open, running, finished or
// failed, with or without a lane or a pull request.
@MainActor @Test func aLaneHeaderKeepsItsHeight() throws {
    let base = try height(lane(), open: true)
    #expect(base >= 2 * (28 + 18 + 6))
    #expect(try height(lane(), open: false) == base)
    for state in [SubagentState.running, .failed] { #expect(try height(lane(state), open: true) == base) }
    #expect(try height(lane(lane: nil), open: true) == base)
    // a slice with no number is titled by its description
    var untitled = lane()
    untitled.slice = nil
    #expect(try height(untitled, open: true) == base)
    // just started: no pills, only "starting…"
    var starting = lane(.running)
    (starting.items, starting.counts, starting.timeLabel) = ([], SessionCounts(), nil)
    #expect(try height(starting, open: true) == base)
    var bare = lane()
    bare.pullRequest = "no PR yet"
    #expect(try height(bare, open: true) == base)
    // resumed, or with no times at all
    var again = lane()
    again.resumes = 2
    #expect(try height(again, open: true) == base)
    var untimed = lane(.failed)
    (untimed.timeLabel, untimed.duration) = (nil, nil)
    #expect(try height(untimed, open: true) == base)
}

// At a narrow width the row keeps its height: the pills fall back to icon and number rather than wrap or cut off.
@MainActor @Test func aNarrowLaneHeaderKeepsItsHeightWithEveryPill() throws {
    let busy = LaneSection(
        id: "a", startId: 1, title: "Socket client", sliceTitle: "Socket client", state: .finished, duration: 180_000, startedAt: 0, endedAt: 180_000,
        resumes: 2, timeLabel: "14:02–14:05",
        counts: SessionCounts(calls: 12, edits: 3, added: 42, removed: 8, tests: 2, errors: 1), items: [], slice: 653, laneNumber: 1, pullRequest: "PR #670 merged"
    )
    func height(_ lane: LaneSection, width: CGFloat) throws -> Int {
        let renderer = ImageRenderer(content: LaneHeaderView(lane: lane, open: true).frame(width: width))
        renderer.scale = 2
        return try #require(renderer.cgImage).height
    }
    let base = try height(lane(), width: 480)
    #expect(try height(busy, width: 480) == base)
    #expect(try height(busy, width: 300) == base)
    #expect(try height(lane(), width: 300) == base)
    #expect(try height(lane(lane: nil), width: 300) == base)
}

// The "Earlier sessions" row is the same height closed or open, whatever the count.
@MainActor @Test func theEarlierSessionsRowKeepsItsHeight() throws {
    func height(count: Int, open: Bool) throws -> Int {
        let renderer = ImageRenderer(content: EarlierSessionsRow(count: count, open: open).frame(width: 480))
        renderer.scale = 2
        return try #require(renderer.cgImage).height
    }
    let closed = try height(count: 1, open: false)
    #expect(closed > 0)
    #expect(try height(count: 1, open: true) == closed)
    #expect(try height(count: 120, open: false) == closed)
}

private func shell(_ id: Int, _ tool: String = "Bash") -> TranscriptItem {
    .tool(id: id, TranscriptCard(tool: tool, kind: ToolKind(tool: tool), arg: "pnpm test", summary: "", status: .ok, duration: "1.0 s", durationMs: 1000))
}

// A group's row is 28 pt folded or open, with a duration or none, at any width.
@MainActor @Test func aGroupRowKeepsItsHeight() throws {
    func height(_ calls: [TranscriptItem], open: Bool, width: CGFloat = 480) throws -> Int {
        let renderer = ImageRenderer(content: ToolGroupHeader(calls: calls, open: open).frame(width: width))
        renderer.scale = 2
        return try #require(renderer.cgImage).height
    }
    let mixed = [shell(1), shell(2), shell(3), shell(4, "Read")]
    let base = try height(mixed, open: false)
    #expect(base == 56)
    #expect(try height(mixed, open: true) == base)
    #expect(try height([shell(1), shell(2)], open: false) == base)
    #expect(try height(mixed + (5...9).map { shell($0, "Grep") } + [shell(10, "WebFetch")], open: false, width: 200) == base)
}
