import Testing
@testable import CarrierCore

private func epic(
    _ issue: Int, _ status: PanelEpic.Status = .running, stage: PanelEpic.Stage? = .ship, round: Int? = nil,
    slices: PanelEpic.Slices? = nil, reason: String? = nil
) -> PanelEpic {
    PanelEpic(
        repo: "acme/web", issue: issue, status: status, stage: stage, round: round, maxReviews: 5, blockers: 0, stageSince: 0,
        lastActivityAt: nil, issueUrl: "https://example.test/\(issue)", prUrl: nil, lastError: nil, needsHumanReason: reason,
        slices: slices, executionId: nil
    )
}

private func snapshot(
    _ epics: [PanelEpic] = [], queue: [PanelSnapshot.QueuedEpic] = [], done: [PanelSnapshot.DoneEpic] = []
) -> PanelSnapshot {
    PanelSnapshot(
        now: 0, slots: .init(busy: 0, total: 2), queue: queue, epics: epics, startedAt: 0, repos: 1, nextCheckAt: nil,
        problem: nil, paused: false, done: done
    )
}

@Test func noEpicsAddNoSection() {
    #expect(epicMenu(snapshot(), showEpics: true) == nil)
}

@Test func theSettingOffAddsNoSection() {
    #expect(epicMenu(snapshot([epic(1)]), showEpics: false) == nil)
}

@Test func oneOfEachStateComesInTheOrderOfUrgency() throws {
    let all = snapshot(
        [epic(1, stage: .review, round: 2, slices: .init(done: 3, total: 5)), epic(2, .needsHuman, slices: .init(done: 1, total: 4), reason: "review limit")],
        queue: [.init(repo: "acme/api", issue: 3, title: nil, queuedAt: nil)],
        done: [.init(repo: "acme/web", issue: 4, prNumber: 9, finishedAt: nil, executionId: nil)]
    )
    let menu = try #require(epicMenu(all, showEpics: true))
    #expect(menu.more == nil)
    #expect(menu.items.map(\.state) == [EpicMenuState.needsYou, .running, .waiting, .ready])
    #expect(menu.items.map(\.title) == ["web #2", "web #1", "api #3", "web #4"])
    #expect(menu.items.map(\.detail) == ["review limit", "review · round 2/5", "waiting", "ready for test · PR #9"])
    #expect(menu.items.map(\.badge) == ["1/4", "2/5", nil, nil])
}

@Test func theBadgeIsSlicesWhileShippingAndTheRoundWhileReviewing() throws {
    let shipping = epic(1, stage: .ship, slices: .init(done: 9, total: 20))
    let fixing = epic(2, stage: .fix, round: 3, slices: .init(done: 9, total: 20))
    let unknown = epic(3, stage: nil)
    let menu = try #require(epicMenu(snapshot([shipping, fixing, unknown]), showEpics: true))
    #expect(menu.items.map(\.badge) == ["9/20", "3/5", nil])
    #expect(menu.items[2].detail == "starting")
}

@Test func theGlyphNamesAndColoursPerState() {
    #expect(EpicMenuState.needsYou.symbol == "exclamationmark.circle.fill")
    #expect(EpicMenuState.running.symbol == "circle.dotted")
    #expect(EpicMenuState.waiting.symbol == "circle")
    #expect(EpicMenuState.ready.symbol == "checkmark.circle.fill")
    #expect([EpicMenuState.needsYou, .running, .waiting, .ready].map(\.colorName) == ["orange", "green", "gray", "blue"])
}

@Test func moreThanTwentyShowTwentyAndHowManyAreLeft() throws {
    let many = snapshot((1...23).map { epic($0) })
    let menu = try #require(epicMenu(many, showEpics: true))
    #expect(menu.items.count == 20)
    #expect(menu.items.last?.issue == 20)
    #expect(menu.more == "… and 3 more")
    #expect(try #require(epicMenu(snapshot((1...20).map { epic($0) }), showEpics: true)).more == nil)
}
