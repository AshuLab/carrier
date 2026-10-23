import Foundation
import Testing
@testable import CarrierCore

private func epic(
    _ status: PanelEpic.Status = .running, stage: PanelEpic.Stage? = .ship, round: Int? = nil, since: Int = 0, kind: String? = nil
) -> PanelEpic {
    var epic = PanelEpic(
        repo: "acme/web", issue: 12, status: status, stage: stage, round: round, maxReviews: 5, blockers: 0, stageSince: since,
        lastActivityAt: nil, issueUrl: "https://github.com/acme/web/issues/12", prUrl: nil, lastError: nil, needsHumanReason: nil,
        slices: nil, executionId: nil
    )
    epic.needsHumanKind = kind
    return epic
}

private let queuedEpic = PanelSnapshot.QueuedEpic(repo: "acme/web", issue: 12, title: nil, queuedAt: nil)
private let doneEpic = PanelSnapshot.DoneEpic(repo: "acme/web", issue: 12, prNumber: 50, finishedAt: 1_000_000, executionId: nil)

private func line(_ steps: [PipelineStep]) -> [String] {
    steps.map { step in
        let state = ["done": "d", "current": "c", "waiting": "w", "problem": "p"][String(describing: step.state)]!
        return "\(step.name):\(state)\(step.label.map { ":" + $0 } ?? "")"
    }
}

private func reply(stages: [EpicReply.Stage], rounds: Int = 0) -> EpicReply {
    let round = EpicReply.Round(
        round: 1, reviewer: .init(harness: "codex", model: "gpt-5", provider: nil), verdict: "approved", blockers: [], reviewMs: nil,
        fixMs: nil, reviewedSha: nil, fixedSha: nil, commits: []
    )
    return EpicReply(stages: stages, rounds: Array(repeating: round, count: rounds), slices: [], worktrees: [], branch: nil, pr: nil)
}

@Test func aQueuedEpicSaysItsPlaceInTheQueue() {
    #expect(line(pipelineSteps(.queued(queuedEpic, position: 1), now: 0)) == ["Queued:c:1st in queue", "Ship:w", "Review/Fix:w", "Ready:w"])
    #expect(pipelineSteps(.queued(queuedEpic, position: 12), now: 0)[0].label == "12th in queue")
    #expect([2, 3, 4, 11, 21, 22, 103, 111].map(ordinal) == ["2nd", "3rd", "4th", "11th", "21st", "22nd", "103rd", "111th"])
}

@Test func shipIsCurrentWithItsTimeInStageAndQueuedShowsHowLongItWaited() {
    var running = epic(stage: .ship, since: 50_000)
    #expect(line(pipelineSteps(.active(running), now: 110_000)) == ["Queued:d", "Ship:c:1m", "Review/Fix:w", "Ready:w"])
    running.queuedAt = 1_000
    running.startedAt = 46_000
    #expect(pipelineSteps(.active(running), now: 110_000)[0].label == "45s")
    // before the first stage there is nothing to time
    #expect(line(pipelineSteps(.active(epic(stage: nil, since: 50_000)), now: 50_000))[1] == "Ship:c:0s")
}

@Test func reviewRoundTwoIsCurrentWithItsRound() {
    let steps = pipelineSteps(.active(epic(stage: .review, round: 2)), now: 0)
    #expect(line(steps) == ["Queued:d", "Ship:d", "Review/Fix:c:r2/5", "Ready:w"])
    // a fix is the same step; before the first review there is no round yet
    #expect(pipelineSteps(.active(epic(stage: .fix, round: 2)), now: 0)[2].label == "r2/5")
    #expect(pipelineSteps(.active(epic(stage: .review)), now: 0)[2].label == nil)
}

@Test func theReviewLimitIsAProblemAtReviewFix() {
    let steps = pipelineSteps(.active(epic(.needsHuman, stage: .review, round: 5, kind: "review_limit")), now: 0)
    #expect(line(steps) == ["Queued:d", "Ship:d", "Review/Fix:p:limit 5/5", "Ready:w"])
}

@Test func anEpicThatStopsDuringShipHasShipAsItsProblem() {
    let steps = pipelineSteps(.active(epic(.needsHuman, stage: .ship, since: 0, kind: "timeout")), now: 90_000)
    #expect(line(steps) == ["Queued:d", "Ship:p", "Review/Fix:w", "Ready:w"])
}

@Test func aReadyEpicIsDoneEverywhereAndSaysHowLongAgo() {
    #expect(line(pipelineSteps(.finished(doneEpic), now: 1_120_000)) == ["Queued:d", "Ship:d", "Review/Fix:d", "Ready:d:2m ago"])
    let unknown = PanelSnapshot.DoneEpic(repo: "acme/web", issue: 12, prNumber: nil, finishedAt: nil, executionId: nil)
    #expect(pipelineSteps(.finished(unknown), now: 0)[3].label == nil)
}

@Test func theReplyAddsTheTimeOfEachFinishedStage() {
    let finished = reply(
        stages: [
            .init(stage: "queued", startedAt: 0, endedAt: 360_000), .init(stage: "ship", startedAt: 360_000, endedAt: 6_840_000),
            .init(stage: "review", startedAt: 6_840_000, endedAt: 7_000_000), .init(stage: "fix", startedAt: 7_000_000, endedAt: 7_100_000),
            .init(stage: "review", startedAt: 7_100_000, endedAt: 7_200_000), .init(stage: "ready", startedAt: 7_200_000, endedAt: nil),
        ],
        rounds: 2
    )
    #expect(
        line(pipelineSteps(.finished(doneEpic), reply: finished, now: 1_120_000))
            == ["Queued:d:6m", "Ship:d:1h 48m", "Review/Fix:d:2 rounds", "Ready:d:2m ago"]
    )
    // the same reply while review is running: Ship keeps its time, Review/Fix keeps the round from the snapshot
    let steps = pipelineSteps(.active(epic(stage: .review, round: 2)), reply: finished, now: 0)
    #expect(line(steps) == ["Queued:d:6m", "Ship:d:1h 48m", "Review/Fix:c:r2/5", "Ready:w"])
    #expect(pipelineSteps(.finished(doneEpic), reply: reply(stages: [], rounds: 1), now: 0)[2].label == "1 round")
}

@Test func theSnapshotFindsAnEpicWhereverItIs() {
    let snapshot = PanelSnapshot(
        now: 0, slots: .init(busy: 0, total: 3), queue: [queuedEpic, .init(repo: "acme/api", issue: 3, title: nil, queuedAt: nil)],
        epics: [epic()], startedAt: 0, repos: 1, nextCheckAt: nil, problem: nil, paused: false, done: [doneEpic]
    )
    #expect(snapshot.subject(repo: "acme/web", issue: 12) == .active(epic()))
    #expect(snapshot.subject(repo: "acme/api", issue: 3) == .queued(snapshot.queue[1], position: 2))
    #expect(snapshot.subject(repo: "acme/web", issue: 99) == nil)
}

// MARK: header

@Test func theHeaderFallsBackToTheEpicNumberWithoutATitle() {
    var untitled = epic()
    #expect(epicHeader(.active(untitled)).title == "Epic #12")
    untitled.title = ""
    #expect(epicHeader(.active(untitled)).title == "Epic #12")
    untitled.title = "Checkout flow"
    let header = epicHeader(.active(untitled))
    #expect(header.title == "Checkout flow" && header.subtitle == "acme/web · #12")
    #expect(epicHeader(.queued(queuedEpic, position: 1)).title == "Epic #12")
    var done = PanelSnapshot.DoneEpic(repo: "acme/web", issue: 12, prNumber: nil, finishedAt: nil, executionId: nil)
    #expect(epicHeader(.finished(done)).title == "Epic #12")
    done.title = "Checkout flow"
    #expect(epicHeader(.finished(done)).title == "Checkout flow")
}

@Test func theHeaderHidesTheSolveLabels() {
    var labelled = epic()
    #expect(epicHeader(.active(labelled)).labels == [])
    labelled.labels = ["solve:epic", "solve:epic:running", "shop", "payments"]
    #expect(epicHeader(.active(labelled)).labels == ["shop", "payments"])
    labelled.labels = ["solve:epic"]
    #expect(epicHeader(.active(labelled)).labels == [])
}

@Test func theHeaderHasNoPullRequestUntilThereIsOne() {
    let header = epicHeader(.active(epic(stage: .ship)))
    #expect(header.prURL == nil && header.prLabel == nil)
    #expect(header.issueURL == "https://github.com/acme/web/issues/12")
    // the toolbar then offers Open issue only, also for an epic still in the queue
    #expect(epicHeader(.queued(queuedEpic, position: 1)).prURL == nil)
    #expect(epicHeader(.queued(queuedEpic, position: 1)).issueURL == "https://github.com/acme/web/issues/12")
}

@Test func theHeaderLinksThePullRequestFromTheSnapshotOrTheReply() {
    var withPR = epic(stage: .review)
    withPR.prUrl = "https://github.com/acme/web/pull/50"
    let header = epicHeader(.active(withPR))
    #expect(header.prURL == "https://github.com/acme/web/pull/50" && header.prLabel == "PR #50")
    let done = epicHeader(.finished(doneEpic))
    #expect(done.prURL == "https://github.com/acme/web/pull/50" && done.prLabel == "PR #50")
    let pr = EpicReply.PullRequest(number: 51, url: "https://github.com/acme/web/pull/51", draft: false, mergeState: "clean", reviewDecision: nil, checks: nil)
    var fromReply = reply(stages: [])
    fromReply.pr = pr
    #expect(epicHeader(.active(epic()), reply: fromReply).prLabel == "PR #51")
}

// MARK: tabs

@Test func theTabsListAgentOutputAndFilesChangedWithACountOnlyAboveZero() {
    #expect(EpicTab.allCases.map(\.title) == ["Agent output", "Files changed"])
    #expect(EpicTab.agentOutput.title(filesChanged: 7) == "Agent output")
    #expect(EpicTab.filesChanged.title(filesChanged: 0) == "Files changed")
    #expect(EpicTab.filesChanged.title(filesChanged: 3) == "Files changed · 3")
}

@Test func aFileTouchedByTwoSessionsCountsOnce() {
    func file(_ path: String) -> FilesReply.File { .init(path: path, added: 1, removed: 0, alsoIn: []) }
    func section(_ id: String, _ files: [String]) -> FilesReply.Section {
        .init(id: id, kind: "ship", title: id, added: 0, removed: 0, files: files.map(file))
    }
    #expect(filesChangedCount(nil) == 0)
    #expect(filesChangedCount(FilesReply(sections: [])) == 0)
    #expect(filesChangedCount(FilesReply(sections: [section("a", ["x.ts", "y.ts"]), section("b", ["y.ts", "z.ts"])])) == 3)
}

@Test func theHeaderSaysTheStateInWords() {
    let running = epicHeader(.active(epic(.running, stage: .review, round: 2)))
    #expect(running.state == .running)
    #expect(running.status == "Running · review · round 2/5")
    #expect((running.repo, running.issue) == ("acme/web", 12))
    let stuck = epicHeader(.active(epic(.needsHuman, stage: .review, round: 5, kind: "review_limit")))
    #expect(stuck.state == .needsYou)
    #expect(stuck.status == "Needs you · review limit reached")
    #expect(epicHeader(.queued(queuedEpic, position: 2)).status == "Up next · 2nd in queue")
    #expect(epicHeader(.queued(queuedEpic, position: 2)).state == .waiting)
    #expect(epicHeader(.finished(doneEpic)).state == .ready)
}

// MARK: finished epics

private func ended(_ status: PanelSnapshot.FinishedEpic.Status, reason: String? = nil, pr: Int? = 50) -> PanelSnapshot.FinishedEpic {
    .init(
        repo: "acme/web", issue: 12, title: "Checkout flow", labels: ["solve:epic", "shop"], prNumber: pr, finishedAt: 1_000_000, status: status,
        cancelReason: reason, executionId: "exec-1"
    )
}

@Test func theSnapshotFindsAFinishedEpicAfterTheOthers() {
    var snapshot = PanelSnapshot(
        now: 0, slots: .init(busy: 0, total: 3), queue: [], epics: [], startedAt: 0, repos: 1, nextCheckAt: nil, problem: nil, paused: false, done: []
    )
    snapshot.finished = [ended(.merged)]
    #expect(snapshot.subject(repo: "acme/web", issue: 12) == .ended(ended(.merged)))
    #expect(snapshot.subject(repo: "acme/web", issue: 13) == nil)
    snapshot.epics = [epic()]
    #expect(snapshot.subject(repo: "acme/web", issue: 12) == .active(epic()))
}

@Test func aMergedEpicHeaderIsDoneWithItsPullRequestAndLabels() {
    let header = epicHeader(.ended(ended(.merged)))
    #expect(header.state == .done && header.status == "Done")
    #expect(header.title == "Checkout flow" && header.labels == ["shop"])
    #expect(header.prURL == "https://github.com/acme/web/pull/50" && header.prLabel == "PR #50")
    #expect(header.issueURL == "https://github.com/acme/web/issues/12")
}

@Test func aCancelledEpicHeaderSaysWhy() {
    let header = epicHeader(.ended(ended(.cancelled, reason: "final PR closed without merge", pr: nil)))
    #expect(header.state == .cancelled && header.status == "Cancelled · final PR closed without merge")
    #expect(header.prURL == nil)
    #expect(epicHeader(.ended(ended(.cancelled))).status == "Cancelled")
}

@Test func aMergedEpicIsDoneEverywhereAndACancelledOneStopsWhereItHadNotGot() {
    #expect(line(pipelineSteps(.ended(ended(.merged)), now: 1_120_000)) == ["Queued:d", "Ship:d", "Review/Fix:d", "Ready:d:2m ago"])
    // without the reply only the queue is known to have been passed
    #expect(line(pipelineSteps(.ended(ended(.cancelled)), now: 1_120_000)) == ["Queued:d", "Ship:p:cancelled 2m ago", "Review/Fix:w", "Ready:w"])
    let shipped = reply(stages: [.init(stage: "queued", startedAt: 0, endedAt: 60_000), .init(stage: "ship", startedAt: 60_000, endedAt: 360_000)])
    #expect(
        line(pipelineSteps(.ended(ended(.cancelled)), reply: shipped, now: 1_120_000))
            == ["Queued:d:1m", "Ship:d:5m", "Review/Fix:p:cancelled 2m ago", "Ready:w"]
    )
    let reviewed = reply(stages: shipped.stages, rounds: 2)
    #expect(line(pipelineSteps(.ended(ended(.cancelled)), reply: reviewed, now: 1_120_000))[3] == "Ready:p:cancelled 2m ago")
}

@Test func aFinishedEpicOffersNoContinueButAnOverSessionOfAnotherEpicStillDoes() {
    let resume = ResumeDescriptor(harness: "claude", sessionId: "s", cwd: "/w", configDir: nil)
    let sessions = SessionsReply(sessions: [
        .init(
            executionId: "e", stage: "ship", role: "author", round: nil, agent: .init(harness: "claude", model: "m", provider: nil),
            status: "finished", startedAt: 0, finishedAt: 10, resume: resume
        )
    ])
    #expect(sessionList(sessions).sections[0].resume == resume)
    #expect(sessionList(sessions, resumable: false).sections[0].resume == nil)
}
