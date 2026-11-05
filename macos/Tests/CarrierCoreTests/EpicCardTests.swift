import Foundation
import Testing
@testable import CarrierCore

private func running(
    stage: PanelEpic.Stage = .review, round: Int? = 2, slices: PanelEpic.Slices? = .init(done: 5, total: 5), pr: String? = "https://github.com/acme/web/pull/28"
) -> PanelEpic {
    var epic = PanelEpic(
        repo: "acme/web", issue: 12, status: .running, stage: stage, round: round, maxReviews: 5, blockers: 2, stageSince: 100_000,
        lastActivityAt: nil, issueUrl: "https://github.com/acme/web/issues/12", prUrl: pr, lastError: nil, needsHumanReason: nil,
        slices: slices, executionId: nil
    )
    epic.title = "Rotate the keys"
    epic.branch = "feat/issue-12/epic"
    epic.queuedAt = 40_000
    epic.startedAt = 50_000
    return epic
}

@Test func aRunningEpicsCardHasItsStepsWithTheOneInHandFilledAndItsFacts() {
    let card = epicCard(.active(running()), now: 700_000)
    #expect(card.title == "Rotate the keys" && card.name == "web" && card.subtitle == "acme/web · #12")
    #expect(card.steps.map(\.name) == ["Ship", "Review / Fix", "Ready"])
    #expect(card.steps.map(\.state) == [.done, .current, .waiting])
    #expect(card.steps.map(\.progress) == [nil, 0.4, nil])
    #expect(card.facts.map(\.label) == ["In this step", "Review", "Slices", "PR", "Branch"])
    #expect(card.facts.map(\.value) == ["10m", "round 2/5", "5/5 closed", "#28", "feat/issue-12/epic"])
    #expect(card.timeline == "queued 11m ago · started 10m ago")
}

@Test func theShipStepIsFilledBySlicesClosed() {
    let card = epicCard(.active(running(stage: .ship, round: nil, slices: .init(done: 3, total: 7))), now: 700_000)
    #expect(card.steps.map(\.state) == [.current, .waiting, .waiting])
    #expect(card.steps[0].progress == 3.0 / 7.0)
}

@Test func aStuckEpicsStepTakesTheColourOfItsTrouble() {
    var stuck = running()
    stuck.status = .needsHuman
    stuck.needsHumanKind = "timeout"
    #expect(epicCard(.active(stuck), now: 700_000).steps.map(\.state) == [.done, .error, .waiting])
    stuck.needsHumanKind = "agent_needs_human"
    #expect(epicCard(.active(stuck), now: 700_000).steps.map(\.state) == [.done, .input, .waiting])
}

@Test func aQueuedEpicHasNoStepsAndOnlySaysWhenItQueued() {
    let queued = PanelSnapshot.QueuedEpic(repo: "acme/web", issue: 20, title: "Export", queuedAt: 640_000)
    let card = epicCard(.queued(queued, position: 2), now: 700_000)
    #expect(card.steps.isEmpty && card.facts.isEmpty)
    #expect(card.timeline == "queued 1m ago")
}

@Test func aReadyEpicsStepsAreAllDoneAndItHasItsPR() {
    let card = epicCard(.finished(.init(repo: "acme/web", issue: 30, prNumber: 31, finishedAt: 695_000, executionId: nil)), now: 700_000)
    #expect(card.steps.map(\.state) == [.done, .done, .done])
    #expect(card.facts == [.init(label: "PR", value: "#31")])
    #expect(card.timeline == "finished 5s ago")
}

@Test func theRunningEpicsLineIsWhatItsAgentDoesNowAndFallsBackToItsStage() {
    var epic = running()
    epic.executionId = "exec-1"
    var snapshot = PanelSnapshot(
        now: 700_000, slots: .init(busy: 1, total: 3), queue: [], epics: [epic], startedAt: 0, repos: 1, nextCheckAt: nil, problem: nil, paused: false, done: []
    )
    #expect(sidebarGroups(snapshot, by: .status)[1].rows[0].detail == "review · round 2/5")
    snapshot.sessions = [
        .init(executionId: "exec-1", repo: "acme/web", issue: 12, stage: .review, round: 2, harness: "codex", model: "gpt-5", startedAt: 0, last: .init(kind: "tool", text: "Reading src/auth/token.ts", at: 1))
    ]
    #expect(sidebarGroups(snapshot, by: .status)[1].rows[0].detail == "Reading src/auth/token.ts")
}

@Test func aCardOpensAfterAWhileAndAtOnceRightAfterAnotherClosed() {
    let now = Date(timeIntervalSince1970: 1_000)
    #expect(hoverCardDelay(closedAt: nil, now: now) == .milliseconds(600))
    #expect(hoverCardDelay(closedAt: now.addingTimeInterval(-0.1), now: now) == .zero)
    #expect(hoverCardDelay(closedAt: now.addingTimeInterval(-2), now: now) == .milliseconds(600))
}

@Test func aProjectsColourComesFromTheLastPartOfItsFolderOrRepository() {
    #expect(projectColorKey("/Users/dev/Web") == "web" && projectColorKey("acme/web") == "web" && projectColorKey("web") == "web")
}

@Test func theCardStaysWhileThePointerIsOnTheRowOrOnTheCardAndClosesAMomentAfterLeavingBoth() {
    let now = Date(timeIntervalSince1970: 1_000)
    func step(row: Bool, card: Bool, shown: Bool) -> HoverCardStep { hoverCardStep(onRow: row, onCard: card, shown: shown, closedAt: nil, now: now) }
    #expect(step(row: true, card: false, shown: false) == .open(after: .milliseconds(600)))
    #expect(step(row: true, card: false, shown: true) == .keep)
    // on the way to the card: off the row, not yet on the card
    #expect(step(row: false, card: false, shown: true) == .close(after: .milliseconds(250)))
    #expect(step(row: false, card: true, shown: true) == .keep)
    #expect(step(row: false, card: false, shown: false) == .keep)
}
