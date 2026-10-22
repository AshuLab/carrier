import Foundation
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

// the switches

private let both = snapshot([epic(7, .needsHuman, reason: "x")], done: [ready(9, pr: 4)])

@Test func aKindWhoseSwitchIsOffDoesNotNotify() {
    let before = snapshot([epic(7)])
    let titles = { (kinds: NotificationKinds) in notifications(from: before, to: both, kinds: kinds).map(\.title) }
    #expect(titles(NotificationKinds()) == ["a/b #7 needs you", "a/b #9 is ready for test"])
    #expect(titles(NotificationKinds(needsYou: false)) == ["a/b #9 is ready for test"])
    #expect(titles(NotificationKinds(readyForTest: false)) == ["a/b #7 needs you"])
    #expect(titles(NotificationKinds(needsYou: false, readyForTest: false)).isEmpty)
}

@Test func theWatcherReadsTheSwitchesOnEverySnapshotAndRemembersWhatItSkipped() {
    let centre = FakeCentre()
    var kinds = NotificationKinds(needsYou: false)
    let watcher = NotificationWatcher(centre: centre, kinds: { kinds })
    watcher.react(to: running(snapshot()))
    watcher.react(to: running(snapshot([epic(1, .needsHuman)])))
    #expect(centre.posted.isEmpty)
    kinds.needsYou = true
    // the epic that needed a person while the switch was off is not news when it goes on
    watcher.react(to: running(snapshot([epic(1, .needsHuman), epic(2, .needsHuman)])))
    #expect(centre.posted == [["a/b #2 needs you"]])
}

@Test func theSwitchesAreOnUntilTurnedOff() {
    let defaults = UserDefaults(suiteName: "carrier-test-\(UUID().uuidString)")!
    #expect(defaults.notificationKinds == NotificationKinds())
    defaults.set(false, forKey: notifyReadyForTestKey)
    #expect(defaults.notificationKinds == NotificationKinds(readyForTest: false))
    defaults.set(false, forKey: notifyNeedsYouKey)
    #expect(defaults.notificationKinds == NotificationKinds(needsYou: false, readyForTest: false))
}

// the permission

private struct StubCentre: NotificationPermissionReader {
    var answer: SystemNotificationAnswer
    func read(_ done: @escaping (SystemNotificationAnswer) -> Void) { done(answer) }
}

private struct UntouchableCentre: NotificationPermissionReader {
    func read(_ done: @escaping (SystemNotificationAnswer) -> Void) { Issue.record("the centre was read without a bundle") }
}

@Test func theSystemsThreeAnswersAndAMissingBundleAreTheFourStates() {
    func permission(_ answer: SystemNotificationAnswer) -> NotificationPermission? {
        var shown: NotificationPermission?
        readPermission(bundleIdentifier: "dev.ashulab.carrier", reader: StubCentre(answer: answer)) { shown = $0 }
        return shown
    }
    #expect(permission(.allowed) == .allowed)
    #expect(permission(.denied) == .denied)
    #expect(permission(.notAsked) == .notAsked)

    var noBundle: NotificationPermission?
    readPermission(bundleIdentifier: nil, reader: UntouchableCentre()) { noBundle = $0 }
    #expect(noBundle == .noBundle)
}
