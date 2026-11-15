import Foundation
import Testing
@testable import CarrierCore

// 2026-01-01 14:02:00 UTC, in ms.
private let start = 1_767_276_120_000

private func lane(
    _ id: String, slice: Int? = nil, _ state: SubagentState = .finished, from: Int = 0, to: Int? = 300, lane number: Int? = nil,
    counts: SessionCounts = SessionCounts(calls: 38, edits: 11, tests: 7, errors: 1), pr: Int? = nil, prState: String? = nil
) -> LaneSection {
    LaneSection(
        id: id, startId: 1, title: "Title \(id)", sliceTitle: nil, state: state, duration: nil, startedAt: start + from * 1000, endedAt: to.map { start + $0 * 1000 },
        resumes: 0, timeLabel: to == nil ? (state == .running ? "since 14:02" : nil) : "14:02–14:07", counts: counts, items: [.note(id: 1, text: "x")],
        slice: slice, laneNumber: number, pullRequest: "no PR yet", prNumber: pr, prState: prState
    )
}

@Test func aMergedSliceIsATickedRowWithItsNumbersAndPullRequest() {
    let row = sliceCard(lane: lane("a", slice: 730, to: 300, pr: 736, prState: "merged"))
    #expect(row.mark == .done && row.openByDefault == false)
    #expect(row.quiet.map(\.text) == ["38 calls", "11 edits", "7 test runs", "1 error", "14:02–14:07"])
    #expect(row.quiet[3].kind == .error)
    #expect(row.prNumber == 736 && row.prState == .merged)
}

@Test func aWorkingSliceOpensByItselfAndItsCallsAreSoFar() {
    let row = sliceCard(lane: lane("a", slice: 730, .running, to: nil, lane: 1, counts: SessionCounts(calls: 12), pr: 736, prState: "draft"))
    #expect(row.mark == .working && row.openByDefault)
    // a working slice has no time range, its calls are so far, and the lane is a tag
    #expect(row.quiet == [SliceQuiet(text: "12 calls so far", kind: .plain), SliceQuiet(text: "Lane 1", kind: .lane)])
    #expect(row.prState == .draft)
}

@Test func aFailedSliceSaysItDidNotComplete() {
    let row = sliceCard(lane: lane("b", slice: 2, .failed, from: 10, to: nil, counts: SessionCounts(calls: 4)))
    #expect(row.mark == .failed && row.openByDefault == false)
    #expect(row.quiet == [SliceQuiet(text: "4 calls", kind: .plain), SliceQuiet(text: "did not complete", kind: .error)])
}

@Test func whatTheDataLacksIsLeftOutOfTheLine() {
    // no slice number, no pull request, no counts yet: a title and a word
    var started = lane("a", .running, to: nil, counts: SessionCounts())
    started.items = []
    let row = sliceCard(lane: started)
    #expect(row.number == nil && row.prNumber == nil && row.quiet == [SliceQuiet(text: "starting…", kind: .plain)])
    // a pull request from an engine that sends no state still has its number
    let old = sliceCard(lane: lane("b", slice: 2, pr: 9))
    #expect(old.prNumber == 9 && old.prState == .unknown)
    // no counts at all leaves just the range
    #expect(sliceCard(lane: lane("c", slice: 3, counts: SessionCounts())).quiet == [SliceQuiet(text: "14:02–14:07", kind: .plain)])
}

@Test func theRowIsSpokenWithItsStateAndPullRequest() {
    let row = sliceCard(lane: lane("a", slice: 730, pr: 736, prState: "merged"))
    #expect(row.spoken == "Slice 730, Title a, finished, 38 calls, 11 edits, 7 test runs, 1 error, 14:02–14:07, pull request 736 merged")
}
