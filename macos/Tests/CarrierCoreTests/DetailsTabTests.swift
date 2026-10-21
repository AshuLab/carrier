import Foundation
import Testing
@testable import CarrierCore

private let utc = TimeZone(identifier: "UTC")!
private let hour = 3_600_000
/// 2025-01-10 15:00 UTC.
private let now = 1_736_521_200_000

private let claude = PanelSnapshot.Agent(harness: "claude", model: "opus", provider: nil)
private let codex = PanelSnapshot.Agent(harness: "codex", model: "gpt-5", provider: nil)

private func active(
    _ status: PanelEpic.Status = .running, stage: PanelEpic.Stage? = .review, round: Int? = 2, blockers: Int = 0,
    slices: PanelEpic.Slices? = .init(done: 3, total: 3), modern: Bool = true
) -> EpicSubject {
    var epic = PanelEpic(
        repo: "acme/web", issue: 12, status: status, stage: stage, round: round, maxReviews: 5, blockers: blockers, stageSince: now - 5 * 60_000,
        lastActivityAt: now - 30_000, issueUrl: "https://github.com/acme/web/issues/12", prUrl: nil, lastError: nil, needsHumanReason: nil,
        slices: slices, executionId: nil
    )
    if modern {
        epic.startedAt = now - 2 * hour - 3 * 60_000
        epic.branch = "feat/x/epic"
        epic.agents = PanelSnapshot.Agents(author: claude, reviewer: codex)
    }
    return .active(epic)
}

private func reply(pr: EpicReply.PullRequest? = nil, rounds: [EpicReply.Round] = [], lanes: Int = 0, branch: String? = "feat/x/epic") -> EpicReply {
    EpicReply(
        stages: [.init(stage: "queued", startedAt: now - 3 * hour, endedAt: now - 2 * hour), .init(stage: "ship", startedAt: now - 2 * hour, endedAt: nil)],
        rounds: rounds, slices: [],
        worktrees: (0..<lanes).map { .init(kind: "lane", lane: $0 + 1, path: "/w--lane-\($0 + 1)") }, branch: branch, pr: pr
    )
}

private func pull(_ checks: EpicReply.Checks?) -> EpicReply.PullRequest {
    .init(number: 50, url: "https://github.com/acme/web/pull/50", draft: false, mergeState: "clean", reviewDecision: nil, checks: checks)
}

private func approved() -> EpicReply.Round {
    .init(round: 2, reviewer: codex, verdict: "approved", blockers: [], reviewMs: nil, fixMs: nil, reviewedSha: nil, fixedSha: nil, commits: [])
}

private func rows(_ model: DetailsTabModel) -> [String: DetailsRow] {
    Dictionary(model.groups.flatMap(\.rows).map { ($0.label, $0) }) { first, _ in first }
}

private func model(_ subject: EpicSubject?, _ reply: EpicReply? = nil) -> [String: DetailsRow] {
    rows(detailsTab(subject, reply: reply, now: now, timeZone: utc))
}

@Test func theGroupsAreTimingProgressPullRequestAndRun() {
    let groups = detailsTab(active(), reply: nil, now: now, timeZone: utc).groups
    #expect(groups.map(\.title) == ["Timing", "Progress", "Pull request", "Run"])
    #expect(groups.map { $0.rows.map(\.label) } == [
        ["Stage", "Last activity", "Started", "Total time"], ["Slices", "Review round", "Blockers"],
        ["Pull request", "Checks", "Branch"], ["Agent", "Lanes", "Repository"],
    ])
    #expect(detailsTab(nil, reply: nil, now: now).groups.isEmpty)
}

@Test func aRunningEpicInReviewFillsEveryGroup() {
    let r = model(active(), reply(pr: pull(.init(passing: 5, failing: 0, pending: 0)), lanes: 2))
    #expect(r["Stage"] == DetailsRow(label: "Stage", note: "In review", value: "5m 00s"))
    #expect(r["Last activity"]?.value == "30s ago")
    #expect(r["Started"]?.value == "Today 12:57")
    #expect(r["Total time"]?.value == "2h 03m")
    #expect(r["Slices"] == DetailsRow(label: "Slices", note: "all merged", value: "3 of 3"))
    #expect(r["Review round"] == DetailsRow(label: "Review round", note: "in progress", value: "2 of 5"))
    #expect(r["Blockers"]?.value == "none" && r["Blockers"]?.tone == .good)
    #expect(r["Pull request"]?.value == "PR #50" && r["Pull request"]?.url == "https://github.com/acme/web/pull/50")
    #expect(r["Checks"] == DetailsRow(label: "Checks", note: "on the PR", value: "5 passing", tone: .good))
    #expect(r["Branch"]?.value == "feat/x/epic")
    #expect(r["Agent"] == DetailsRow(label: "Agent", note: "gpt-5", value: "Codex"))
    #expect(r["Lanes"]?.value == "2")
    #expect(r["Repository"]?.value == "acme/web")
}

@Test func theAuthorRunsWhileFixing() {
    #expect(model(active(stage: .fix))["Agent"]?.value == "Claude")
    #expect(model(active(stage: .fix))["Stage"]?.note == "Fixing")
}

@Test func anEpicInShipHasNoPullRequestYet() {
    let r = model(active(stage: .ship, round: nil, blockers: 0, slices: .init(done: 1, total: 3)), reply(lanes: 3))
    #expect(r["Pull request"] == DetailsRow(label: "Pull request", note: "opens when every slice is merged", value: "not yet", tone: .dim))
    #expect(r["Checks"]?.value == "—")
    #expect(r["Review round"] == DetailsRow(label: "Review round", note: "starts after ship", value: "—", tone: .dim))
    #expect(r["Slices"] == DetailsRow(label: "Slices", note: "2 left", value: "1 of 3"))
    #expect(r["Stage"]?.note == "Shipping")
    #expect(r["Agent"]?.value == "Claude")
    #expect(r["Lanes"]?.value == "3")
}

@Test func openBlockersAreCountedAndRed() {
    let r = model(active(blockers: 2))
    #expect(r["Blockers"] == DetailsRow(label: "Blockers", note: "open", value: "2", tone: .bad))
}

@Test func anEpicThatNeedsYouSaysSo() {
    var epic = active(.needsHuman, round: 5)
    if case .active(var e) = epic { e.needsHumanKind = "review_limit"; epic = .active(e) }
    let r = model(epic)
    #expect(r["Review round"] == DetailsRow(label: "Review round", note: "limit reached", value: "5 of 5", tone: .attention))
    #expect(r["Stage"]?.note == "In review · needs you")
    #expect(r["Last activity"]?.note == "no movement since")
}

@Test func aFinishedEpicShowsItsTotalAndItsPullRequest() {
    let done = PanelSnapshot.DoneEpic(repo: "acme/web", issue: 12, prNumber: 50, finishedAt: now - 23 * hour, executionId: nil)
    var finishedReply = reply(pr: pull(.init(passing: 4, failing: 0, pending: 0)), rounds: [approved()])
    finishedReply.stages = [.init(stage: "queued", startedAt: now - 25 * hour, endedAt: now - 24 * hour), .init(stage: "ship", startedAt: now - 24 * hour, endedAt: nil)]
    let r = model(.finished(done), finishedReply)
    #expect(r["Stage"] == DetailsRow(label: "Stage", note: "Finished", value: "23h 00m ago"))
    #expect(r["Total time"]?.value == "1h 00m")
    #expect(r["Started"]?.value == "Yesterday 15:00")
    #expect(r["Review round"] == DetailsRow(label: "Review round", note: "approved", value: "2"))
    #expect(r["Blockers"]?.value == "none")
    #expect(r["Pull request"]?.value == "PR #50")
    #expect(r["Agent"]?.value == "—")
}

@Test func aQueuedEpicHasOnlyItsWaitAndItsRepository() {
    let queued = PanelSnapshot.QueuedEpic(repo: "acme/web", issue: 12, title: nil, queuedAt: now - 7 * 60_000)
    let r = model(.queued(queued, position: 2))
    #expect(r["Stage"] == DetailsRow(label: "Stage", note: "2nd in queue", value: "7m 00s"))
    for label in ["Last activity", "Started", "Total time", "Slices", "Blockers", "Checks", "Branch", "Agent", "Lanes"] {
        #expect(r[label]?.value == "—", "\(label)")
    }
    #expect(r["Pull request"]?.value == "not yet")
    #expect(r["Review round"]?.note == "starts after ship")
    #expect(r["Repository"]?.value == "acme/web")
}

@Test func anOlderEngineLeavesDashesWhereItSendsNothing() {
    let r = model(active(stage: .review, round: nil, slices: nil, modern: false))
    #expect(r["Stage"]?.value == "5m 00s")
    #expect(r["Started"]?.value == "—")
    #expect(r["Total time"]?.value == "—")
    #expect(r["Slices"]?.value == "—")
    #expect(r["Review round"]?.value == "—")
    #expect(r["Pull request"]?.value == "—")
    #expect(r["Checks"]?.value == "—")
    #expect(r["Branch"]?.value == "—")
    #expect(r["Agent"]?.value == "—")
    #expect(r["Lanes"]?.value == "—")
    #expect(r["Repository"]?.value == "acme/web")
}

@Test func theChecksRowShowsCountsOrNoChecks() {
    func checks(_ counts: EpicReply.Checks?) -> DetailsRow? { model(active(), reply(pr: pull(counts)))["Checks"] }
    #expect(checks(.init(passing: 5, failing: 1, pending: 2))?.value == "5 passing · 1 failing · 2 pending")
    #expect(checks(.init(passing: 5, failing: 1, pending: 2))?.tone == .bad)
    #expect(checks(.init(passing: 5, failing: 0, pending: 2))?.tone == .attention)
    #expect(checks(.init(passing: 0, failing: 0, pending: 3))?.value == "3 pending")
    #expect(checks(nil) == DetailsRow(label: "Checks", note: "on the PR", value: "no checks", tone: .dim))
    #expect(checks(.init(passing: 0, failing: 0, pending: 0))?.value == "no checks")
    #expect(model(active(), reply(pr: nil))["Checks"]?.value == "—")
}

@Test func slicesFallBackToTheReplyWhenTheSnapshotHasNoCount() {
    var withSlices = reply()
    withSlices.slices = [
        .init(number: 1, title: "a", state: "closed", blockedBy: [], prNumber: nil, closedAt: nil, readAt: 0),
        .init(number: 2, title: "b", state: "in_progress", blockedBy: [], prNumber: nil, closedAt: nil, readAt: 0),
        .init(number: 3, title: "c", state: "skipped", blockedBy: [], prNumber: nil, closedAt: nil, readAt: 0),
    ]
    #expect(model(active(slices: nil), withSlices)["Slices"] == DetailsRow(label: "Slices", note: "1 left", value: "1 of 2"))
}
