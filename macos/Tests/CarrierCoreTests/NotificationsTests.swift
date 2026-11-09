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
    #expect(due == [EpicNotification(title: "a/b #7 needs attention", body: "review limit", epic: EpicRef(repo: "a/b", issue: 7))])
}

@Test func aNeedsHumanWithoutAReasonStillSaysWhatHappened() {
    let due = notifications(from: snapshot(), to: snapshot([epic(7, .needsHuman)]))
    #expect(due.count == 1)
    #expect(due[0].title == "a/b #7 needs attention")
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
    #expect(due.map(\.title) == ["c/d #7 needs attention"])
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
    var sounds: [Bool] = []
    var quiets: [Bool] = []
    func post(_ notifications: [EpicNotification]) {
        posted.append(notifications.map(\.title))
        sounds += notifications.map(\.sound)
        quiets += notifications.map(\.quiet)
    }
}

private func running(_ snapshot: PanelSnapshot) -> ConnectionState { .running(snapshot) }

@Test func theWatcherSeedsOnTheFirstSnapshotAndPostsWhatChangesAfter() {
    let centre = FakeCentre()
    let watcher = NotificationWatcher(centre: centre)
    watcher.react(to: running(snapshot([epic(1, .needsHuman)], done: [ready(3)])))
    watcher.react(to: running(snapshot([epic(1, .needsHuman), epic(2, .needsHuman)], done: [ready(3)])))
    watcher.react(to: running(snapshot([epic(1, .needsHuman), epic(2, .needsHuman)], done: [ready(3)])))
    #expect(centre.posted == [["a/b #2 needs attention"]])
}

@Test func theFirstSnapshotAfterCarrierWasStoppedAndStartedAgainSeedsToo() {
    let centre = FakeCentre()
    let watcher = NotificationWatcher(centre: centre)
    watcher.react(to: running(snapshot()))
    watcher.react(to: .stopped)
    watcher.react(to: running(snapshot([epic(1, .needsHuman)], done: [ready(3)])))
    #expect(centre.posted.isEmpty)

    watcher.react(to: .incompatible(update: nil))
    watcher.react(to: running(snapshot([epic(1, .needsHuman), epic(2, .needsHuman)], done: [ready(3)])))
    #expect(centre.posted.isEmpty)
}

// the sound

@Test func aBannerPlaysASoundOnlyWhileTheSoundSwitchIsOn() {
    let centre = FakeCentre()
    var sound = true
    let watcher = NotificationWatcher(centre: centre, sound: { sound })
    watcher.react(to: running(snapshot()))
    watcher.react(to: running(snapshot([epic(1, .needsHuman)], done: [ready(3)])))
    #expect(centre.sounds == [true, true])
    sound = false
    watcher.react(to: running(snapshot([epic(1, .needsHuman), epic(2, .needsHuman)], done: [ready(3)])))
    #expect(centre.sounds == [true, true, false])
}

@Test func theSoundIsOnUntilTurnedOff() {
    let defaults = UserDefaults(suiteName: "carrier-test-\(UUID().uuidString)")!
    #expect(defaults.notifiesWithSound)
    defaults.set(false, forKey: notifySoundKey)
    #expect(defaults.notifiesWithSound == false)
}

// quiet hours

private func at(_ hour: Int, _ minute: Int = 0) -> Date {
    Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date(timeIntervalSince1970: 1_800_000_000))!
}

@Test func quietHoursAreOffUntilTurnedOnAndOfferTenPMToEightAM() {
    let defaults = UserDefaults(suiteName: "carrier-test-\(UUID().uuidString)")!
    #expect(defaults.quietHours == QuietHours(enabled: false, start: 22 * 60, end: 8 * 60))
    #expect(defaults.quietHours.contains(at(23)) == false)
    defaults.set(true, forKey: notifyQuietKey)
    defaults.set(9 * 60 + 30, forKey: notifyQuietStartKey)
    #expect(defaults.quietHours == QuietHours(enabled: true, start: 9 * 60 + 30, end: 8 * 60))
}

@Test func aWindowInsideOneDayIsQuietFromItsStartUntilItsEnd() {
    let hours = QuietHours(enabled: true, start: 13 * 60, end: 15 * 60)
    #expect(hours.contains(at(12, 59)) == false)
    #expect(hours.contains(at(13)))
    #expect(hours.contains(at(14, 59)))
    #expect(hours.contains(at(15)) == false)
}

@Test func aWindowThatCrossesMidnightIsQuietOnBothSidesOfIt() {
    let hours = QuietHours(enabled: true, start: 22 * 60, end: 8 * 60)
    #expect(hours.contains(at(21, 59)) == false)
    #expect(hours.contains(at(22)))
    #expect(hours.contains(at(23, 30)))
    #expect(hours.contains(at(0)))
    #expect(hours.contains(at(7, 59)))
    #expect(hours.contains(at(8)) == false)
    #expect(hours.contains(at(12)) == false)
}

@Test func aWindowWithEqualStartAndEndIsNeverQuiet_AndOffIsNeverQuiet() {
    let same = QuietHours(enabled: true, start: 6 * 60, end: 6 * 60)
    #expect([0, 6, 12, 23].allSatisfy { same.contains(at($0)) == false })
    #expect(QuietHours(enabled: false, start: 22 * 60, end: 8 * 60).contains(at(23)) == false)
}

@Test func insideTheQuietHoursEveryNotificationIsPostedQuietAndWithoutASound_OutsideAsTheSettingsSay() {
    let centre = FakeCentre()
    var now = at(23)
    let watcher = NotificationWatcher(centre: centre, quietHours: { QuietHours(enabled: true) }, now: { now })
    watcher.react(to: running(snapshot()))
    watcher.react(to: running(snapshot([epic(1, .needsHuman)], done: [ready(3)])))
    #expect(centre.quiets == [true, true])
    #expect(centre.sounds == [false, false])
    now = at(12)
    watcher.react(to: running(snapshot([epic(1, .needsHuman), epic(2, .needsHuman)], done: [ready(3)])))
    #expect(centre.quiets == [true, true, false])
    #expect(centre.sounds == [false, false, true])
}

// the switches

private let both = snapshot([epic(7, .needsHuman, reason: "x")], done: [ready(9, pr: 4)])

@Test func aKindWhoseSwitchIsOffDoesNotNotify() {
    let before = snapshot([epic(7)])
    let titles = { (kinds: NotificationKinds) in notifications(from: before, to: both, kinds: kinds).map(\.title) }
    #expect(titles(NotificationKinds()) == ["a/b #7 needs attention", "a/b #9 is ready for test"])
    #expect(titles(NotificationKinds(needsYou: false)) == ["a/b #9 is ready for test"])
    #expect(titles(NotificationKinds(readyForTest: false)) == ["a/b #7 needs attention"])
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
    #expect(centre.posted == [["a/b #2 needs attention"]])
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
    fresh.react(to: .incompatible(update: nil))
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

// the chat sessions

private func session(_ id: String, _ state: SessionState, archived: Bool = false) -> SessionRow {
    SessionRow(id: id, title: "Session \(id)", workspace: "w", agent: "a", state: state, updatedAt: Date(timeIntervalSince1970: 0), archived: archived)
}

private let chatDoneOn = NotificationKinds(chatDone: true)

@Test func aSessionThatGoesFromWorkingToWaitingNeedsAttentionAndOpensOnItself() {
    let due = chatNotifications(from: [session("1", .working)], to: [session("1", .waiting)])
    #expect(due == [EpicNotification(title: "Session 1 needs attention", body: "It waits for an approval", session: "1")])
}

@Test func aSessionThatGoesFromWorkingToIdleIsDoneOnlyWithTheSwitchOn() {
    #expect(chatNotifications(from: [session("1", .working)], to: [session("1", .idle)]).isEmpty)
    #expect(chatNotifications(from: [session("1", .working)], to: [session("1", .idle)], kinds: chatDoneOn).map(\.title) == ["Session 1 is done"])
}

@Test func anyOtherChangeOfASessionSaysNothing() {
    for (was, now) in [(SessionState.idle, SessionState.waiting), (.waiting, .idle), (.waiting, .working), (.idle, .working), (.working, .working), (.waiting, .waiting), (.working, .done)] {
        #expect(chatNotifications(from: [session("1", was)], to: [session("1", now)], kinds: chatDoneOn).isEmpty)
    }
}

@Test func aSessionSeenForTheFirstTimeNeverNotifies() {
    #expect(chatNotifications(from: nil, to: [session("1", .waiting), session("2", .idle)], kinds: chatDoneOn).isEmpty)
    #expect(chatNotifications(from: [session("1", .working)], to: [session("1", .working), session("2", .waiting)], kinds: chatDoneOn).isEmpty)
}

@Test func aSessionThatDisappearsOrIsArchivedSaysNothing() {
    #expect(chatNotifications(from: [session("1", .working)], to: [], kinds: chatDoneOn).isEmpty)
    #expect(chatNotifications(from: [session("1", .working)], to: [session("1", .idle, archived: true)], kinds: chatDoneOn).isEmpty)
}

@Test func theChatSwitchesSilenceEachKindAlone() {
    let before = [session("1", .working), session("2", .working)]
    let after = [session("1", .waiting), session("2", .idle)]
    #expect(chatNotifications(from: before, to: after, kinds: NotificationKinds(chatNeedsAttention: false, chatDone: true)).map(\.title) == ["Session 2 is done"])
    #expect(chatNotifications(from: before, to: after, kinds: NotificationKinds(chatNeedsAttention: true, chatDone: false)).map(\.title) == ["Session 1 needs attention"])
    #expect(chatNotifications(from: before, to: after, kinds: NotificationKinds(chatNeedsAttention: false, chatDone: false)).isEmpty)
}

@Test func theChatSwitchesStartWithNeedsAttentionOnAndDoneOff() {
    let defaults = UserDefaults(suiteName: "carrier-test-\(UUID().uuidString)")!
    #expect(defaults.notificationKinds.chatNeedsAttention)
    #expect(defaults.notificationKinds.chatDone == false)
    defaults.set(true, forKey: notifyChatDoneKey)
    defaults.set(false, forKey: notifyChatNeedsAttentionKey)
    #expect(defaults.notificationKinds == NotificationKinds(chatNeedsAttention: false, chatDone: true))
}

@Test func theWatcherSeedsOnTheFirstListAndPostsTheChangesAfterWithTheSound() {
    let centre = FakeCentre()
    var sound = true
    let watcher = NotificationWatcher(centre: centre, sound: { sound })
    watcher.react(toSessions: [session("1", .working)])
    #expect(centre.posted.isEmpty)
    watcher.react(toSessions: [session("1", .waiting)])
    watcher.react(toSessions: [session("1", .waiting)])
    #expect(centre.posted == [["Session 1 needs attention"]])
    sound = false
    watcher.react(toSessions: [session("1", .working)])
    watcher.react(toSessions: [session("1", .waiting)])
    #expect(centre.posted.count == 2)
    #expect(centre.sounds == [true, false])
}

@Test func theDockBadgeCountsEpicsThatNeedAPersonPlusSessionsWaitingForAnApproval() {
    let epics = snapshot([epic(1, .needsHuman), epic(2), epic(3, .needsHuman)])
    let sessions = [session("1", .waiting), session("2", .working), session("3", .idle), session("4", .waiting), session("5", .waiting, archived: true)]
    #expect(dockBadgeCount(snapshot: snapshot([epic(1)]), sessions: [session("1", .working)]) == 0)
    #expect(dockBadgeCount(snapshot: nil, sessions: []) == 0)
    #expect(dockBadgeCount(snapshot: epics, sessions: [session("1", .idle)]) == 2)
    #expect(dockBadgeCount(snapshot: snapshot(), sessions: sessions) == 2)
    #expect(dockBadgeCount(snapshot: epics, sessions: sessions) == 4)
}

@Test func theDockBadgeIsOnUntilTurnedOff() {
    let defaults = UserDefaults(suiteName: "carrier-test-\(UUID().uuidString)")!
    #expect(defaults.showsDockBadge)
    defaults.set(false, forKey: notifyDockBadgeKey)
    #expect(defaults.showsDockBadge == false)
}

@Test func theWatcherSetsTheBadgeFromTheTwoLastStatesAndClearsItAtZeroOrWithTheSwitchOff() {
    var shown = true
    var badge = -1
    let watcher = NotificationWatcher(centre: FakeCentre(), showsBadge: { shown }, setBadge: { badge = $0 })
    watcher.react(to: running(snapshot([epic(1, .needsHuman)])))
    #expect(badge == 1)
    watcher.react(toSessions: [session("1", .waiting)])
    #expect(badge == 2)
    shown = false
    watcher.refreshBadge()
    #expect(badge == 0)
    shown = true
    watcher.refreshBadge()
    #expect(badge == 2)
    watcher.react(to: .stopped)
    #expect(badge == 1)
    watcher.react(toSessions: [session("1", .idle)])
    #expect(badge == 0)
}
