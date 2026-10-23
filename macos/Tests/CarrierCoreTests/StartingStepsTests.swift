import Testing
@testable import CarrierCore

private func epic(_ status: PanelEpic.Status = .running, stage: PanelEpic.Stage? = .ship) -> EpicSubject {
    .active(PanelEpic(
        repo: "acme/web", issue: 12, status: status, stage: stage, round: nil, maxReviews: 5, blockers: 0, stageSince: 0,
        lastActivityAt: nil, issueUrl: "https://github.com/acme/web/issues/12", prUrl: nil, lastError: nil, needsHumanReason: nil,
        slices: nil, executionId: nil
    ))
}

private func reply(worktrees: Int) -> EpicReply {
    EpicReply(
        stages: [], rounds: [], slices: [],
        worktrees: (0..<worktrees).map { .init(kind: "epic", lane: nil, path: "/w\($0)") }, branch: nil, pr: nil
    )
}

@Test func aShippingEpicWithNoWorktreeIsPreparingTheWorkspace() {
    #expect(startingSteps(epic(), reply: nil)?.map(\.state) == [.done, .current, .waiting])
    #expect(startingSteps(epic(), reply: reply(worktrees: 0))?.map(\.state) == [.done, .current, .waiting])
}

@Test func onceThereIsAWorktreeTheFirstAgentIsTheCurrentStep() {
    let steps = startingSteps(epic(), reply: reply(worktrees: 1))
    #expect(steps?.map(\.state) == [.done, .done, .current])
    #expect(steps?[1].title == "Workspace ready")
}

@Test func onlyAShippingRunningEpicHasStartingSteps() {
    #expect(startingSteps(epic(stage: nil), reply: nil) != nil)
    #expect(startingSteps(epic(stage: .review), reply: nil) == nil)
    #expect(startingSteps(epic(.needsHuman), reply: nil) == nil)
}
