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

private func snapshot(_ epics: [PanelEpic] = [], done: [PanelSnapshot.DoneEpic] = [], problem: String? = nil, watched: [PanelSnapshot.Watched]? = nil) -> PanelSnapshot {
    var made = PanelSnapshot(
        now: 0, slots: .init(busy: 0, total: 2), queue: [], epics: epics, startedAt: 0, repos: 1, nextCheckAt: nil,
        problem: problem, paused: false, done: done
    )
    made.watched = watched
    return made
}

private func watched(_ repo: String, ok: Bool = true, error: String? = nil) -> PanelSnapshot.Watched {
    let agent = PanelSnapshot.Agent(harness: "claude", model: "sonnet", provider: nil)
    return .init(repo: repo, lastCheckedAt: 0, ok: ok, error: error, agents: .init(author: agent, reviewer: agent))
}

@Test func anEpicThatNowNeedsAPersonNotifiesWithItsReason() {
    let due = notifications(from: snapshot([epic(7)]), to: snapshot([epic(7, .needsHuman, reason: "review limit")]))
    #expect(due == [EpicNotification(title: "a/b #7 needs you", body: "review limit", epic: EpicRef(repo: "a/b", issue: 7))])
}

@Test func aNeedsHumanWithoutAReasonStillSaysWhatHappened() {
    let due = notifications(from: snapshot(), to: snapshot([epic(7, .needsHuman)]))
    #expect(due.count == 1)
    #expect(due[0].title == "a/b #7 needs you")
    #expect(due[0].body.isEmpty == false)
}

@Test func anEpicNewInTheReadyListNotifiesWithItsPullRequest() {
    let due = notifications(from: snapshot(), to: snapshot(done: [ready(9, pr: 42)]))
    #expect(due == [EpicNotification(title: "a/b #9 is ready for test", body: "Pull request #42", epic: EpicRef(repo: "a/b", issue: 9))])
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

@Test func aProblemIsOffUntilTurnedOnAndNotInFrontIsOnUntilTurnedOff() {
    let defaults = UserDefaults(suiteName: "carrier-test-\(UUID().uuidString)")!
    #expect(defaults.notificationKinds.problem == false && defaults.notifiesOnlyWhenAway)
    defaults.set(true, forKey: notifyProblemKey)
    defaults.set(false, forKey: notifyOnlyWhenAwayKey)
    #expect(defaults.notificationKinds.problem && defaults.notifiesOnlyWhenAway == false)
}

@Test func aBannerIsHeldBackOnlyWhenAskedAndTheAppIsInFront_AndTheTestAlwaysShows() {
    #expect(shouldPresent(onlyWhenAway: true, appIsActive: true, isTest: false) == false)
    #expect(shouldPresent(onlyWhenAway: true, appIsActive: false, isTest: false))
    #expect(shouldPresent(onlyWhenAway: false, appIsActive: true, isTest: false))
    #expect(shouldPresent(onlyWhenAway: true, appIsActive: true, isTest: true))
}

// problems

private let withProblems = NotificationKinds(problem: true)

@Test func aProblemNotifiesOnceForEachTextAndOnlyWhenTheSwitchIsOn() {
    let none = snapshot()
    let stalled = snapshot(problem: "GitHub is stalled")
    #expect(notifications(from: none, to: stalled).isEmpty)
    #expect(notifications(from: none, to: stalled, kinds: withProblems) == [EpicNotification(title: "Carrier has a problem", body: "GitHub is stalled")])
    #expect(notifications(from: stalled, to: stalled, kinds: withProblems).isEmpty)
    #expect(notifications(from: stalled, to: snapshot(problem: "A profile was rejected"), kinds: withProblems).map(\.body) == ["A profile was rejected"])
    #expect(notifications(from: stalled, to: none, kinds: withProblems).isEmpty)
    #expect(notifications(from: none, to: stalled, kinds: withProblems).count == 1)
}

@Test func aRepoGitHubRefusesNotifiesOnceUntilItRecovers() {
    let fine = snapshot(watched: [watched("a/b")])
    let refused = snapshot(watched: [watched("a/b", ok: false, error: "Repository not found")])
    #expect(notifications(from: fine, to: refused, kinds: withProblems) == [EpicNotification(title: "a/b was refused by GitHub", body: "Repository not found")])
    #expect(notifications(from: refused, to: refused, kinds: withProblems).isEmpty)
    #expect(notifications(from: refused, to: fine, kinds: withProblems).isEmpty)
    #expect(notifications(from: fine, to: refused, kinds: withProblems).count == 1)
    #expect(notifications(from: fine, to: refused).isEmpty)
}

private func clock(_ time: Date) -> (() -> Date, set: (Date) -> Void) {
    var now = time
    return ({ now }, { now = $0 })
}

@Test func aStopTheAppDidNotAskForIsAProblemAndOneItDidAskForIsNot() {
    let centre = FakeCentre()
    let watcher = NotificationWatcher(centre: centre, kinds: { withProblems })
    watcher.react(to: running(snapshot()))
    watcher.react(to: .stopped)
    #expect(centre.posted == [["Carrier stopped"]])
    // already stopped: the retries say nothing more
    watcher.react(to: .stopped)
    // the first snapshot after a start only seeds, and the next stop is news again
    watcher.react(to: running(snapshot()))
    watcher.expectStop()
    watcher.react(to: .stopped)
    #expect(centre.posted == [["Carrier stopped"]])
    watcher.react(to: running(snapshot()))
    watcher.react(to: .stopped)
    #expect(centre.posted == [["Carrier stopped"], ["Carrier stopped"]])
}

@Test func aStopAskedForThatNeverHappensDoesNotHideACrashLater() {
    let centre = FakeCentre()
    let time = clock(Date(timeIntervalSince1970: 0))
    let watcher = NotificationWatcher(centre: centre, kinds: { withProblems }, now: time.0)
    watcher.react(to: running(snapshot()))
    watcher.expectStop(for: 30)
    time.set(Date(timeIntervalSince1970: 31))
    watcher.react(to: .stopped)
    #expect(centre.posted == [["Carrier stopped"]])
}

@Test func withoutTheProblemSwitchAStopIsSilent_AndNeverStartedIsNotAStop() {
    let centre = FakeCentre()
    let off = NotificationWatcher(centre: centre)
    off.react(to: running(snapshot()))
    off.react(to: .stopped)
    let fresh = NotificationWatcher(centre: centre, kinds: { withProblems })
    fresh.react(to: .stopped)
    fresh.react(to: .incompatible)
    #expect(centre.posted.isEmpty)
}

// the permission

private struct StubCentre: NotificationPermissionReader {
    var answer: SystemNotificationAnswer
    func read(_ done: @escaping (SystemNotificationAnswer) -> Void) { done(answer) }
}

private struct UntouchableCentre: NotificationPermissionReader {
    func read(_ done: @escaping (SystemNotificationAnswer) -> Void) { Issue.record("the centre was read without a bundle") }
}

private let banners = NotificationDelivery(style: .banners, soundOn: true)

@Test func theSystemsThreeAnswersAndAMissingBundleAreTheFourStates() {
    func permission(_ answer: SystemNotificationAnswer) -> NotificationPermission? {
        var shown: NotificationPermission?
        readPermission(bundleIdentifier: "dev.ashulab.carrier", reader: StubCentre(answer: answer)) { shown = $0 }
        return shown
    }
    #expect(permission(.allowed(banners)) == .allowed(banners))
    #expect(permission(.denied) == .denied)
    #expect(permission(.notAsked) == .notAsked)

    var noBundle: NotificationPermission?
    readPermission(bundleIdentifier: nil, reader: UntouchableCentre()) { noBundle = $0 }
    #expect(noBundle == .noBundle)
}

@Test func thePermissionSaysWhatMacOSReallyDoes() {
    #expect(NotificationPermission.allowed(banners).text == "Allowed · banners · sound on")
    #expect(NotificationPermission.allowed(.init(style: .alerts, soundOn: false)).text == "Allowed · alerts · sound off")
    #expect(NotificationPermission.allowed(.init(style: .none, soundOn: true)).text == "Allowed · notifications set to None")
    #expect(NotificationPermission.denied.text == "Denied in System Settings")
    #expect(NotificationPermission.notAsked.text == "Not asked yet · the first notification asks")
    #expect(NotificationPermission.noBundle.text == "Only available from Carrier.app")
}

@Test func aTestThatMacOSWouldSwallowSaysWhy() {
    #expect(NotificationPermission.denied.testAdvice == "Notifications are off for Carrier in System Settings.")
    #expect(NotificationPermission.allowed(.init(style: .none, soundOn: false)).testAdvice != nil)
    #expect(NotificationPermission.allowed(banners).testAdvice == nil)
    #expect(NotificationPermission.notAsked.testAdvice == nil)
}
