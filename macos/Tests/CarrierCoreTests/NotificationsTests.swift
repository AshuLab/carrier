import Testing
@testable import CarrierCore

private func epic(_ issue: Int, _ status: PanelEpic.Status = .running, reason: String? = nil, repo: String = "a/b") -> PanelEpic {
    PanelEpic(
        repo: repo, issue: issue, status: status, stage: .ship, round: nil, maxReviews: 3, blockers: 0, stageSince: 0,
        lastActivityAt: nil, issueUrl: "https://example.test/\(issue)", prUrl: nil, lastError: nil, needsHumanReason: reason,
        slices: nil, executionId: nil
    )
}

private func ready(_ issue: Int, pr: Int? = nil, repo: String = "a/b") -> PanelSnapshot.DoneEpic {
    .init(repo: repo, issue: issue, prNumber: pr, finishedAt: nil, executionId: nil)
}

private func snapshot(_ epics: [PanelEpic] = [], done: [PanelSnapshot.DoneEpic] = []) -> PanelSnapshot {
    PanelSnapshot(
        now: 0, slots: .init(busy: 0, total: 2), queue: [], epics: epics, startedAt: 0, repos: 1, nextCheckAt: nil,
        problem: nil, paused: false, done: done
    )
}

@Test func anEpicThatNowNeedsAPersonNotifiesWithItsReason() {
    let due = notifications(from: snapshot([epic(7)]), to: snapshot([epic(7, .needsHuman, reason: "review limit")]))
    #expect(due == [EpicNotification(title: "a/b #7 needs you", body: "review limit")])
}

@Test func aNeedsHumanWithoutAReasonStillSaysWhatHappened() {
    let due = notifications(from: snapshot(), to: snapshot([epic(7, .needsHuman)]))
    #expect(due.count == 1)
    #expect(due[0].title == "a/b #7 needs you")
    #expect(due[0].body.isEmpty == false)
}

@Test func anEpicNewInTheReadyListNotifiesWithItsPullRequest() {
    let due = notifications(from: snapshot(), to: snapshot(done: [ready(9, pr: 42)]))
    #expect(due == [EpicNotification(title: "a/b #9 is ready for test", body: "Pull request #42")])
}

@Test func aReadyEpicWithoutAPullRequestStillNotifies() {
    let due = notifications(from: snapshot(), to: snapshot(done: [ready(9)]))
    #expect(due.map(\.title) == ["a/b #9 is ready for test"])
}

@Test func whatWasAlreadyThereDoesNotNotify() {
    let before = snapshot([epic(7, .needsHuman, reason: "x")], done: [ready(9)])
    #expect(notifications(from: before, to: before).isEmpty)
    #expect(notifications(from: before, to: snapshot([epic(7, .needsHuman, reason: "y")], done: [ready(9), ready(8)])).map(\.title) == ["a/b #8 is ready for test"])
}

@Test func theSameIssueNumberInAnotherRepoIsAnotherEpic() {
    let due = notifications(from: snapshot([epic(7, .needsHuman)]), to: snapshot([epic(7, .needsHuman), epic(7, .needsHuman, repo: "c/d")]))
    #expect(due.map(\.title) == ["c/d #7 needs you"])
}

@Test func theFirstSnapshotOnlySeeds() {
    let full = snapshot([epic(1, .needsHuman), epic(2, .needsHuman)], done: [ready(3), ready(4)])
    #expect(notifications(from: nil, to: full).isEmpty)
}

@Test func anEpicThatLeavesAndEntersAgainNotifiesAgain() {
    let needs = snapshot([epic(7, .needsHuman)])
    let running = snapshot([epic(7)])
    #expect(notifications(from: needs, to: running).isEmpty)
    #expect(notifications(from: running, to: needs).count == 1)

    let listed = snapshot(done: [ready(9)])
    #expect(notifications(from: listed, to: snapshot()).isEmpty)
    #expect(notifications(from: snapshot(), to: listed).count == 1)
}

private final class FakeCentre: NotificationCentre {
    var posted: [[String]] = []
    func post(_ notifications: [EpicNotification]) { posted.append(notifications.map(\.title)) }
}

private func running(_ snapshot: PanelSnapshot) -> ConnectionState { .running(snapshot) }

@Test func theWatcherSeedsOnTheFirstSnapshotAndPostsWhatChangesAfter() {
    let centre = FakeCentre()
    let watcher = NotificationWatcher(centre: centre)
    watcher.react(to: running(snapshot([epic(1, .needsHuman)], done: [ready(3)])))
    watcher.react(to: running(snapshot([epic(1, .needsHuman), epic(2, .needsHuman)], done: [ready(3)])))
    watcher.react(to: running(snapshot([epic(1, .needsHuman), epic(2, .needsHuman)], done: [ready(3)])))
    #expect(centre.posted == [["a/b #2 needs you"]])
}

@Test func theFirstSnapshotAfterCarrierWasStoppedAndStartedAgainSeedsToo() {
    let centre = FakeCentre()
    let watcher = NotificationWatcher(centre: centre)
    watcher.react(to: running(snapshot()))
    watcher.react(to: .stopped)
    watcher.react(to: running(snapshot([epic(1, .needsHuman)], done: [ready(3)])))
    #expect(centre.posted.isEmpty)

    watcher.react(to: .incompatible)
    watcher.react(to: running(snapshot([epic(1, .needsHuman), epic(2, .needsHuman)], done: [ready(3)])))
    #expect(centre.posted.isEmpty)
}
