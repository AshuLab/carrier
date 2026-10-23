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

private func model(_ slices: [EpicReply.Slice], filter: SliceFilter = .all, now: Int = 100_000) -> SlicesTabModel {
    slicesTabModel(running(nil), reply: reply(slices), filter: filter, now: now)
}

@Test func theListHoldsEverySliceByNumberWhateverTheOrderTheyCameIn() {
    let all = [slice(5, "ready"), slice(1, "closed", closedAt: 1), slice(3, "in_progress"), slice(2, "skipped"), slice(4, "waiting", blockedBy: [3])]
    let tab = model(all)
    #expect(tab.selected == .all)
    #expect(tab.rows.map(\.number) == [1, 3, 4, 5])
    #expect(tab.rows.map(\.state) == [.merged, .inProgress, .pending, .pending])
}

@Test func eachRowHasItsStateAndDetail() {
    let all = [
        slice(1, "closed", closedAt: 40_000, pr: 9), slice(2, "in_progress", pr: 7, lane: 2, activity: "writing tests"),
        slice(3, "ready"), slice(4, "waiting", blockedBy: [2, 3]), slice(5, "skipped"), slice(6, "in_progress"),
    ]
    #expect(model(all).rows == [
        SliceRow(
            number: 1, title: "Slice 1", state: .merged, detail: "1m ago", prNumber: 9, issueURL: "https://github.com/acme/web/issues/1",
            prURL: "https://github.com/acme/web/pull/9"
        ),
        SliceRow(
            number: 2, title: "Slice 2", state: .inProgress, detail: "lane 2 \u{00B7} writing tests", prNumber: 7,
            issueURL: "https://github.com/acme/web/issues/2", prURL: "https://github.com/acme/web/pull/7"
        ),
        SliceRow(number: 3, title: "Slice 3", state: .pending, detail: "ready to start", prNumber: nil, issueURL: "https://github.com/acme/web/issues/3", prURL: nil),
        SliceRow(
            number: 4, title: "Slice 4", state: .pending, detail: "after #2 Slice 2, #3 Slice 3", prNumber: nil,
            issueURL: "https://github.com/acme/web/issues/4", prURL: nil
        ),
        SliceRow(number: 6, title: "Slice 6", state: .inProgress, detail: "working", prNumber: nil, issueURL: "https://github.com/acme/web/issues/6", prURL: nil),
    ])
    #expect(model(all).legend == [.init(group: .merged, count: 1), .init(group: .inProgress, count: 2), .init(group: .pending, count: 2)])
    #expect(model(all).total == 5 && model(all).centre == "1/5" && model(all).caption == "merged")
}

@Test func aPendingSliceNamesEveryBlockerOfTheEpicAndShowsOneOutsideItAsANumber() {
    let all = [slice(2, "in_progress"), slice(3, "ready"), slice(4, "waiting", blockedBy: [2]), slice(5, "waiting", blockedBy: [12]), slice(6, "waiting", blockedBy: [3, 12, 2])]
    #expect(model(all).rows.map(\.detail) == ["working", "ready to start", "after #2 Slice 2", "after #12", "after #3 Slice 3, #12, #2 Slice 2"])
}

@Test(arguments: [(SliceGroup.merged, [1]), (.inProgress, [2, 6]), (.pending, [3, 4])])
func aFilterShowsOnlyItsGroup(group: SliceGroup, numbers: [Int]) {
    let all = [slice(1, "closed", closedAt: 1), slice(2, "in_progress"), slice(3, "ready"), slice(4, "waiting", blockedBy: [3]), slice(6, "in_progress")]
    let tab = model(all, filter: .only(group))
    #expect(tab.selected == .only(group))
    #expect(tab.rows.map(\.number) == numbers)
    // the totals do not change with the filter
    #expect(tab.legend == model(all).legend && tab.total == 5)
}

@Test func totalShowsEverySlice() {
    let all = [slice(1, "closed", closedAt: 1), slice(2, "in_progress"), slice(3, "ready")]
    #expect(model(all, filter: .all).rows.map(\.number) == [1, 2, 3])
}

@Test func aFilterWhoseGroupHasNoSlicesBehavesAsTotal() {
    let all = [slice(1, "closed", closedAt: 1), slice(3, "ready")]
    let tab = model(all, filter: .only(.inProgress))
    #expect(tab.selected == .all && tab.rows.map(\.number) == [1, 3])
}

@Test func skippedSlicesStayOutOfTheListTheTotalsAndTheRing() {
    let tab = model([slice(1, "closed", closedAt: 1), slice(2, "skipped"), slice(3, "ready")])
    #expect(tab.rows.map(\.number) == [1, 3] && tab.total == 2 && tab.counts == [1, 0, 1])
}

@Test func aQueuedEpicHasEverythingPending() {
    let queued = EpicSubject.queued(PanelSnapshot.QueuedEpic(repo: "acme/web", issue: 1, title: nil, queuedAt: nil), position: 1)
    let tab = slicesTabModel(queued, reply: reply([slice(1, "ready"), slice(2, "in_progress"), slice(3, "waiting", blockedBy: [2])]), now: 0)
    #expect(tab.rows.map(\.state) == [.pending, .pending, .pending])
    #expect(tab.legend == [.init(group: .pending, count: 3)])
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
    #expect(tab.rows.map(\.number) == Array(1...20))
    #expect(model(slices, filter: .only(.pending)).rows.count == 9)
    #expect(model(slices, filter: .only(.merged)).rows.map(\.number) == Array(1...8))
    #expect(tab.unavailable == nil && tab.isEmpty == false)
    #expect(arcs(tab.counts).count == 3)
}

@Test func withoutTheListTheCountsMakeTheRingAndAnEmptyStateReplacesTheList() {
    let counts = slicesTabModel(running(3, 5), reply: nil, now: 0)
    #expect(counts.counts == [3, 0, 2] && counts.centre == "3/5")
    #expect(counts.rows.isEmpty && counts.unavailable == .notShared)
}

@Test func anEngineThatAnsweredWithNoSlicesHasNotReadThemYet() {
    let counts = slicesTabModel(running(3, 5), reply: reply([]), now: 0)
    #expect(counts.counts == [3, 0, 2] && counts.rows.isEmpty && counts.unavailable == .notReadYet)
}

@Test func withNoSlicesAtAllTheTabIsEmpty() {
    #expect(slicesTabModel(running(0, 0), reply: nil, now: 0).isEmpty)
    #expect(slicesTabModel(nil, reply: nil, now: 0).isEmpty)
    #expect(slicesTabModel(running(nil), reply: reply([]), now: 0).unavailable == nil)
}

@Test func theFixtureRepliesSlicesGroupAsTheDesignExpects() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/reply-epic.json")
    let epic = try JSONDecoder().decode(EpicReply.self, from: Data(contentsOf: url))
    let tab = slicesTabModel(nil, reply: epic, now: 99_000)
    // merged, in progress, ready, blocked by several and blocked by one; the skipped one is left out
    #expect(tab.counts == [1, 1, 3] && tab.rows.map(\.number) == [121, 123, 124, 125, 126])
    #expect(tab.rows.map(\.detail).suffix(3) == ["after #121 Request schemas, #123 Sessions request", "ready to start", "after #124 Events request"])
}
