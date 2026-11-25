import Foundation
import Testing
@testable import CarrierCore

private func epic(_ status: PanelEpic.Status = .running, stage: PanelEpic.Stage? = .ship, queuedAt: Int? = nil, startedAt: Int? = nil) -> PanelEpic {
    var epic = PanelEpic(
        repo: "acme/web", issue: 12, status: status, stage: stage, round: nil, maxReviews: 5, blockers: 0, stageSince: 0,
        lastActivityAt: nil, issueUrl: "https://github.com/acme/web/issues/12", prUrl: nil, lastError: nil, needsHumanReason: nil,
        slices: nil, executionId: nil
    )
    (epic.queuedAt, epic.startedAt) = (queuedAt, startedAt)
    return epic
}

private func reply(worktrees: Int, branch: String? = nil) -> EpicReply {
    EpicReply(
        stages: [], rounds: [], slices: [],
        worktrees: (0..<worktrees).map { .init(kind: "epic", lane: nil, path: "/w\($0)") }, branch: branch, pr: nil
    )
}

private let time = TimeFormat(style: .clock, hours: .h24, locale: Locale(identifier: "en_US_POSIX"), timeZone: TimeZone(identifier: "UTC")!)

@Test func aShippingEpicWithNoWorktreeIsPreparingTheWorkspace() {
    #expect(startingSteps(epic(), reply: nil, now: 0, bundle: english.bundle, locale: english.locale).map(\.state) == [.done, .current, .waiting])
    #expect(startingSteps(epic(), reply: reply(worktrees: 0), now: 0, bundle: english.bundle, locale: english.locale).map(\.state) == [.done, .current, .waiting])
}

@Test func onceThereIsAWorktreeTheFirstAgentIsTheCurrentStep() {
    let steps = startingSteps(epic(), reply: reply(worktrees: 1), now: 0, bundle: english.bundle, locale: english.locale)
    #expect(steps.map(\.state) == [.done, .done, .current])
    #expect(steps[1].title == "Workspace ready")
}

@Test func onlyAShippingRunningEpicIsStarting() {
    #expect(isStarting(epic()))
    #expect(isStarting(epic(stage: nil)))
    #expect(isStarting(epic(stage: .review)) == false)
    #expect(isStarting(epic(.needsHuman)) == false)
}

@Test func theStepsSayWhatTheSnapshotKnows() {
    // 16:05:00 UTC on 2023-11-14, a slot two minutes later, and twelve seconds into the workspace
    let queued = 1_699_977_900_000, started = queued + 120_000
    let running = epic(queuedAt: queued, startedAt: started)
    let steps = startingSteps(running, reply: reply(worktrees: 0, branch: "fix/salary"), now: started + 12_000, time: time, bundle: english.bundle, locale: english.locale)
    #expect(steps[0].detail == "Waited 2m for a slot")
    #expect(steps[0].clock == "16:07")
    #expect(steps[1].detail == "Branch fix/salary")
    #expect(steps[1].clock == "12s")
    #expect(steps[2].detail == "Its output appears here")
    let ready = startingSteps(running, reply: reply(worktrees: 1, branch: "fix/salary"), now: started, time: time, bundle: english.bundle, locale: english.locale)
    #expect(ready[1].detail == "Worktree on fix/salary")
    #expect(ready[1].clock == nil)
}

@Test func aMissingValueLeavesItsPartOutOfTheLine() {
    let steps = startingSteps(epic(), reply: reply(worktrees: 0), now: 5_000, bundle: english.bundle, locale: english.locale)
    #expect(steps.map(\.clock) == [nil, nil, nil])
    #expect(steps.map(\.detail) == [nil, nil, "Its output appears here"])
    // a start before the queue time is no wait to report
    #expect(startingSteps(epic(queuedAt: 9_000, startedAt: 1_000), reply: nil, now: 5_000, bundle: english.bundle, locale: english.locale)[0].detail == nil)
}

@Test func theStartingStepsSaySpanishWhatTheSnapshotKnows() {
    let queued = 1_699_977_900_000, started = queued + 120_000
    let running = epic(queuedAt: queued, startedAt: started)
    let steps = startingSteps(running, reply: reply(worktrees: 0, branch: "fix/salary"), now: started + 12_000, time: time, bundle: spanish.bundle, locale: spanish.locale)
    #expect(steps.map(\.title) == ["Epic en cola", "Preparando el espacio de trabajo", "Arranca el primer agente"])
    #expect(steps.map(\.detail) == ["Esperó 2m por un cupo", "Rama fix/salary", "Su salida aparece aquí"])
    let ready = startingSteps(running, reply: reply(worktrees: 1, branch: "fix/salary"), now: started, time: time, bundle: spanish.bundle, locale: spanish.locale)
    #expect(ready[1].title == "Espacio de trabajo listo")
    #expect(ready[1].detail == "Worktree en fix/salary")
}
