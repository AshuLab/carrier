import Foundation
import Testing
@testable import CarrierCore

// MARK: ring

private let ring = (radius: 50.0, lineWidth: 11.0, gap: 3.0)
private func arcs(_ counts: [Int]) -> [RingArc] { ringArcs(counts, radius: ring.radius, lineWidth: ring.lineWidth, gap: ring.gap) }

@Test func aZeroTotalHasNoArcs() {
    #expect(arcs([]).isEmpty)
    #expect(arcs([0, 0, 0]).isEmpty)
}

@Test func aSingleGroupFillsTheCircleWithoutCaps() {
    #expect(arcs([0, 0, 4]) == [RingArc(group: 2, start: 0, end: 1, full: true)])
}

@Test func aGroupSmallerThanTheGapStaysADotInsideItsSlot() throws {
    let result = arcs([1, 1000])
    let dot = try #require(result.first)
    #expect(dot.group == 0 && dot.full == false)
    #expect(dot.end > dot.start && dot.end - dot.start < 0.001)
    #expect(dot.start >= 0 && dot.end < result[1].start)
}

@Test func threeGroupsFollowTheirCountsAroundTheCircle() {
    let result = arcs([1, 1, 2])
    #expect(result.map(\.group) == [0, 1, 2])
    let circumference = 2 * Double.pi * ring.radius
    // slots are 1/4, 1/4 and 1/2 of the turn, each arc shortened by the gap plus the caps' reach
    for (arc, share) in zip(result, [0.25, 0.25, 0.5]) {
        #expect(abs((arc.end - arc.start) * circumference - (share * circumference - ring.gap - ring.lineWidth)) < 1e-9)
    }
    #expect(abs((result[0].start + result[0].end) / 2 - 0.125) < 1e-9)
}

// The centre lines never overlap and stay inside one turn, whatever the counts.
@Test(arguments: [[1, 1, 2], [3, 0, 5], [1, 1000], [7, 7, 7], [1, 2, 3, 4, 5], [20, 0, 1], [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]])
func arcsNeverOverlapNorPassAFullTurn(counts: [Int]) {
    let result = arcs(counts)
    var previousEnd = 0.0
    for arc in result {
        #expect(arc.end > arc.start && arc.start >= previousEnd)
        previousEnd = arc.end
    }
    #expect(previousEnd <= 1)
}

// The round caps reach lineWidth / 2 past each end: they still keep apart when every slot is wider than the gap and the caps.
@Test(arguments: [[1, 1, 2], [3, 0, 5], [7, 7, 7], [1, 2, 3, 4, 5], [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]])
func capsStayApartAndInsideTheCircle(counts: [Int]) {
    let result = arcs(counts)
    let circumference = 2 * Double.pi * ring.radius
    let reach = ring.lineWidth / 2 / circumference
    let space = ring.gap / circumference
    for (arc, next) in zip(result, result.dropFirst()) { #expect(next.start - arc.end - 2 * reach >= space - 1e-9) }
    #expect(result.first.map { $0.start - reach >= space / 2 - 1e-9 } ?? true)
    #expect(result.last.map { $0.end + reach <= 1 - space / 2 + 1e-9 } ?? true)
}

// MARK: model

private func slice(_ n: Int, _ state: String, blockedBy: [Int] = [], closedAt: Int? = nil, pr: Int? = nil, lane: Int? = nil, activity: String? = nil) -> EpicReply.Slice {
    .init(number: n, title: "Slice \(n)", state: state, blockedBy: blockedBy, prNumber: pr, closedAt: closedAt, readAt: 0, lane: lane, activity: activity)
}

private func reply(_ slices: [EpicReply.Slice]) -> EpicReply {
    EpicReply(stages: [], rounds: [], slices: slices, worktrees: [], branch: nil, pr: nil)
}

private func running(_ done: Int?, _ total: Int = 0) -> EpicSubject {
    .active(
        PanelEpic(
            repo: "acme/web", issue: 1, status: .running, stage: .ship, round: nil, maxReviews: 5, blockers: 0, stageSince: 0,
            lastActivityAt: nil, issueUrl: "https://example.test/1", prUrl: nil, lastError: nil, needsHumanReason: nil,
            slices: done.map { .init(done: $0, total: total) }, executionId: nil
        )
    )
}

private func model(_ slices: [EpicReply.Slice], chosen: SliceGroup? = nil, now: Int = 100_000) -> SlicesTabModel {
    slicesTabModel(running(nil), reply: reply(slices), chosen: chosen, now: now)
}

@Test func theDefaultGroupIsInProgressElseWaitingElseMerged() {
    let all = [slice(1, "closed", closedAt: 1), slice(2, "in_progress"), slice(3, "ready")]
    #expect(model(all).selected == .inProgress)
    #expect(model([slice(1, "closed", closedAt: 1), slice(3, "ready")]).selected == .waiting)
    #expect(model([slice(1, "closed", closedAt: 1)]).selected == .merged)
    #expect(model([]).selected == nil)
}

@Test func aChosenGroupWinsUnlessItIsEmpty() {
    let all = [slice(1, "closed", closedAt: 1), slice(2, "in_progress")]
    #expect(model(all, chosen: .merged).selected == .merged)
    #expect(model(all, chosen: .waiting).selected == .inProgress)
}

@Test func eachGroupListsItsRows() {
    let all = [
        slice(1, "closed", closedAt: 40_000, pr: 9), slice(2, "in_progress", pr: 7, lane: 2, activity: "writing tests"),
        slice(3, "ready"), slice(4, "waiting", blockedBy: [2, 3]), slice(5, "skipped"),
    ]
    #expect(model(all, chosen: .merged).rows == [SliceRow(number: 1, title: "Slice 1", detail: "1m 00s ago")])
    #expect(model(all, chosen: .inProgress).rows == [SliceRow(number: 2, title: "Slice 2", detail: "lane 2 · writing tests · PR #7")])
    #expect(model(all, chosen: .waiting).rows.map(\.detail) == ["ready to start", "after #2, #3"])
    #expect(model([slice(2, "in_progress")]).rows.map(\.detail) == ["working"])
    #expect(model(all).legend == [.init(group: .merged, count: 1), .init(group: .inProgress, count: 1), .init(group: .waiting, count: 2)])
    #expect(model(all).centre == "1/4")
    #expect(model(all).caption == "merged")
}

@Test func aCompleteEpicSaysAllMerged() {
    let done = model([slice(1, "closed", closedAt: 1), slice(2, "closed", closedAt: 2)])
    #expect(done.centre == "2/2" && done.caption == "all merged" && done.counts == [2, 0, 0])
}

@Test func aShipEpicWithTwentySlices() {
    var slices = (1...8).map { slice($0, "closed", closedAt: $0 * 1000) }
    slices += (9...11).map { slice($0, "in_progress", lane: $0 - 8) }
    slices += (12...14).map { slice($0, "ready") }
    slices += (15...20).map { slice($0, "waiting", blockedBy: [$0 - 1]) }
    let tab = model(slices)
    #expect(tab.total == 20 && tab.merged == 8 && tab.counts == [8, 3, 9])
    #expect(tab.selected == .inProgress && tab.rows.count == 3)
    #expect(model(slices, chosen: .waiting).rows.count == 9)
    #expect(model(slices, chosen: .merged).rows.map(\.number) == Array(1...8))
    #expect(tab.notice == nil && tab.isEmpty == false)
    #expect(arcs(tab.counts).count == 3)
}

@Test func withoutTheListTheCountsMakeTheRingAndANoticeReplacesTheList() {
    let counts = slicesTabModel(running(3, 5), reply: nil, now: 0)
    #expect(counts.counts == [3, 0, 2] && counts.centre == "3/5")
    #expect(counts.rows.isEmpty && counts.notice != nil)
    #expect(slicesTabModel(running(3, 5), reply: reply([]), now: 0) == counts)
}

@Test func withNoSlicesAtAllTheTabIsEmpty() {
    #expect(slicesTabModel(running(0, 0), reply: nil, now: 0).isEmpty)
    #expect(slicesTabModel(nil, reply: nil, now: 0).isEmpty)
    #expect(slicesTabModel(running(nil), reply: reply([]), now: 0).notice == nil)
}

@Test func theFixtureRepliesSlicesGroupAsTheDesignExpects() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/reply-epic.json")
    let epic = try JSONDecoder().decode(EpicReply.self, from: Data(contentsOf: url))
    let tab = slicesTabModel(nil, reply: epic, now: 99_000)
    #expect(tab.counts == [1, 1, 2] && tab.selected == .inProgress)
}
