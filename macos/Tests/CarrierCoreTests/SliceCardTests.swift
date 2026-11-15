import Foundation
import Testing
@testable import CarrierCore

// 2026-01-01 14:02:00 UTC, in ms.
private let start = 1_767_276_120_000
private let utc = TimeFormat(hours: .h24, timeZone: TimeZone(identifier: "UTC")!)

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

private func waitingSlice(_ number: Int, blockedBy: [Int] = [], state: String = "waiting") -> EpicReply.Slice {
    EpicReply.Slice(number: number, title: "Slice \(number)", state: state, blockedBy: blockedBy, prNumber: nil, closedAt: nil, readAt: 0)
}

@Test func threeMergedSlicesReadAsOneTickedCardWithTheTimeItTook() {
    let card = sliceCard(lanes: [
        lane("a", slice: 730, to: 300, pr: 736, prState: "merged"), lane("b", slice: 731, from: 300, to: 600, pr: 737, prState: "merged"),
        lane("c", slice: 732, from: 600, to: 1860, pr: 738, prState: "merged"),
    ], time: utc)
    #expect(card.summary == "3 of 3 merged" && card.lead == .done && card.segments == [.done, .done, .done])
    #expect(card.time == "31m")
    #expect(card.rows.map(\.openByDefault) == [false, false, false])
    // one after the other: no lane tag
    #expect(card.rows[0].quiet.map(\.text) == ["38 calls", "11 edits", "7 test runs", "1 error", "14:02–14:07"])
    #expect(card.rows[0].quiet[3].kind == .error)
    #expect(card.rows[0].prNumber == 736 && card.rows[0].prState == .merged)
}

@Test func slicesRunningTogetherShowTheirLanesAndTheFirstOpensWhileItWorks() {
    let card = sliceCard(lanes: [
        lane("a", slice: 730, .running, to: nil, lane: 1, counts: SessionCounts(calls: 12), pr: 736, prState: "draft"),
        lane("b", slice: 731, .running, from: 60, to: nil, lane: 2, counts: SessionCounts(calls: 9)),
    ], time: utc)
    #expect(card.summary == "0 of 2 merged · 2 working" && card.lead == .working && card.time == "since 14:02")
    #expect(card.rows.map(\.openByDefault) == [true, false])
    // a working slice has no time range, its calls are so far, and the lane is a tag
    #expect(card.rows[0].quiet == [SliceQuiet(text: "12 calls so far", kind: .plain), SliceQuiet(text: "Lane 1", kind: .lane)])
    #expect(card.rows[0].prState == .draft && card.rows[1].prNumber == nil)
}

@Test func theFirstSliceIsNotOpenWhenItIsNotWorking() {
    let card = sliceCard(lanes: [lane("a", slice: 1, .finished), lane("b", slice: 2, .running, from: 10, to: nil)], time: utc)
    #expect(card.rows.map(\.openByDefault) == [false, false])
}

@Test func aFailedSliceTurnsTheCardRedAndSaysItDidNotComplete() {
    let card = sliceCard(
        lanes: [lane("a", slice: 1, pr: 5, prState: "merged"), lane("b", slice: 2, .failed, from: 10, to: nil, counts: SessionCounts(calls: 4))],
        waiting: [waitingSlice(3, blockedBy: [2])], time: utc
    )
    #expect(card.summary == "1 of 3 merged · 1 failed" && card.lead == .failed && card.segments == [.done, .failed, .waiting])
    #expect(card.rows[1].quiet == [SliceQuiet(text: "4 calls", kind: .plain), SliceQuiet(text: "did not complete", kind: .error)])
    #expect(card.time == "since 14:02")
}

@Test func aSliceNotStartedIsAWaitingRowThatNamesWhatBlocksItAndHasNothingToOpen() {
    let card = sliceCard(
        lanes: [lane("a", slice: 1, .running, to: nil)],
        waiting: [waitingSlice(4, blockedBy: [1, 2]), waitingSlice(3, state: "ready"), waitingSlice(5, state: "skipped")], time: utc
    )
    #expect(card.rows.map(\.number) == [1, 3, 4])
    #expect(card.rows[1].quiet == [SliceQuiet(text: "Ready to start", kind: .plain)] && card.rows[2].quiet == [SliceQuiet(text: "Waits for #1, #2", kind: .plain)])
    #expect(card.rows[1].canOpen == false && card.rows[0].canOpen)
}

@Test func whatTheDataLacksIsLeftOutOfTheLine() {
    // no slice number, no pull request, no counts yet: a title and a word
    var started = lane("a", .running, to: nil, counts: SessionCounts())
    started.items = []
    let row = sliceCard(lanes: [started], time: utc).rows[0]
    #expect(row.number == nil && row.prNumber == nil && row.quiet == [SliceQuiet(text: "starting…", kind: .plain)])
    // a pull request from an engine that sends no state still has its number
    let old = sliceCard(lanes: [lane("b", slice: 2, pr: 9)], time: utc).rows[0]
    #expect(old.prNumber == 9 && old.prState == .unknown)
    // a lane number with nothing running beside it is not shown, and no counts at all leaves just the range
    let alone = sliceCard(lanes: [lane("c", slice: 3, lane: 1, counts: SessionCounts())], time: utc).rows[0]
    #expect(alone.quiet == [SliceQuiet(text: "14:02–14:07", kind: .plain)])
}

@Test func theRowIsSpokenWithItsStateAndPullRequest() {
    let row = sliceCard(lanes: [lane("a", slice: 730, pr: 736, prState: "merged")], time: utc).rows[0]
    #expect(row.spoken == "Slice 730, Title a, finished, 38 calls, 11 edits, 7 test runs, 1 error, 14:02–14:07, pull request 736 merged")
}
