import Testing
@testable import CarrierCore

private func epic(_ status: PanelEpic.Status = .running, slices: PanelEpic.Slices? = nil) -> PanelEpic {
    PanelEpic(
        repo: "a/b", issue: 1, status: status, stage: .ship, round: nil, maxReviews: 3, blockers: 0, stageSince: 0,
        lastActivityAt: nil, issueUrl: "https://example.test/1", prUrl: nil, lastError: nil, needsHumanReason: nil,
        slices: slices, executionId: nil
    )
}

private func snapshot(_ epics: [PanelEpic] = [], problem: String? = nil) -> ConnectionState {
    .running(PanelSnapshot(
        now: 0, slots: .init(busy: 0, total: 2), queue: [], epics: epics, startedAt: 0, repos: 1, nextCheckAt: nil,
        problem: problem, paused: false, done: []
    ))
}

@Test func stoppedAndIncompatibleAreNotConnected() {
    #expect(IconState(.stopped) == IconState(connected: false))
    #expect(IconState(.incompatible) == IconState(connected: false))
}

@Test func nothingRunningIsIdle() {
    #expect(IconState(snapshot()) == IconState(connected: true))
}

@Test func oneRunningEpicCountsItsSlices() {
    let state = IconState(snapshot([epic(slices: .init(done: 1, total: 4))]))
    #expect(state == IconState(connected: true, working: 1, done: 1, total: 4))
    #expect(state.fraction == 0.25)
}

@Test func severalRunningEpicsAddUp() {
    let state = IconState(snapshot([epic(slices: .init(done: 1, total: 4)), epic(slices: .init(done: 3, total: 4))]))
    #expect(state == IconState(connected: true, working: 2, done: 4, total: 8))
    #expect(state.fraction == 0.5)
}

@Test func unknownSlicesAndZeroTotalCountAsWorkingButStayOutOfTheBar() {
    let state = IconState(snapshot([epic(slices: nil), epic(slices: .init(done: 0, total: 0)), epic(slices: .init(done: 2, total: 4))]))
    #expect(state == IconState(connected: true, working: 3, done: 2, total: 4))
}

@Test func allSlicesUnknownIsAnEmptyBar() {
    let state = IconState(snapshot([epic(slices: nil), epic(slices: .init(done: 0, total: 0))]))
    #expect(state == IconState(connected: true, working: 2))
    #expect(state.fraction == 0)
}

@Test func anEpicNeedingAPersonWithNothingRunningIsIdleWithTheDot() {
    #expect(IconState(snapshot([epic(.needsHuman)])) == IconState(connected: true, attention: 1))
}

@Test func aProblemWithEpicsRunningIsWorkingWithTheDot() {
    let state = IconState(snapshot([epic(slices: .init(done: 1, total: 2))], problem: "GitHub is not answering"))
    #expect(state == IconState(connected: true, working: 1, done: 1, total: 2, attention: 1))
}

@Test func attentionAddsEpicsAndTheProblem() {
    #expect(IconState(snapshot([epic(.needsHuman), epic(.needsHuman)], problem: "x")).attention == 3)
}

@Test func epicsNeedingAPersonAreOutOfTheBar() {
    let state = IconState(snapshot([epic(.needsHuman, slices: .init(done: 1, total: 3))]))
    #expect(state == IconState(connected: true, attention: 1))
}
