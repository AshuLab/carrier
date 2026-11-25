import Foundation
import Testing
@testable import CarrierCore

// What these tests assert is English: the notifications are rendered in it, whatever language the machine is in.
private func englishNotifications(from previous: PanelSnapshot?, to new: PanelSnapshot, kinds: NotificationKinds = NotificationKinds()) -> [EpicNotification] {
    notifications(from: previous, to: new, kinds: kinds, bundle: english.bundle, locale: english.locale)
}

private func englishChatNotifications(from previous: [SessionRow]?, to new: [SessionRow], kinds: NotificationKinds = NotificationKinds()) -> [EpicNotification] {
    chatNotifications(from: previous, to: new, kinds: kinds, bundle: english.bundle, locale: english.locale)
}

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
    let due = englishNotifications(from: snapshot([epic(7)]), to: snapshot([epic(7, .needsHuman, reason: "review limit")]))
    #expect(due == [EpicNotification(title: "a/b #7 needs attention", body: "review limit", epic: EpicRef(repo: "a/b", issue: 7))])
}

@Test func aNeedsHumanWithoutAReasonStillSaysWhatHappened() {
    let due = englishNotifications(from: snapshot(), to: snapshot([epic(7, .needsHuman)]))
    #expect(due.count == 1)
    #expect(due[0].title == "a/b #7 needs attention")
    #expect(due[0].body.isEmpty == false)
}

@Test func anEpicNewInTheReadyListNotifiesWithItsPullRequest() {
    let due = englishNotifications(from: snapshot(), to: snapshot(done: [ready(9, pr: 42)]))
    #expect(due == [EpicNotification(title: "a/b #9 is ready for test", body: "Pull request #42", epic: EpicRef(repo: "a/b", issue: 9))])
}

@Test func aReadyEpicWithoutAPullRequestStillNotifies() {
    let due = englishNotifications(from: snapshot(), to: snapshot(done: [ready(9)]))
    #expect(due.map(\.title) == ["a/b #9 is ready for test"])
}

@Test func whatWasAlreadyThereDoesNotNotify() {
    let before = snapshot([epic(7, .needsHuman, reason: "x")], done: [ready(9)])
    #expect(englishNotifications(from: before, to: before).isEmpty)
    #expect(englishNotifications(from: before, to: snapshot([epic(7, .needsHuman, reason: "y")], done: [ready(9), ready(8)])).map(\.title) == ["a/b #8 is ready for test"])
}

@Test func theSameIssueNumberInAnotherRepoIsAnotherEpic() {
    let due = englishNotifications(from: snapshot([epic(7, .needsHuman)]), to: snapshot([epic(7, .needsHuman), epic(7, .needsHuman, repo: "c/d")]))
    #expect(due.map(\.title) == ["c/d #7 needs attention"])
}

@Test func theFirstSnapshotOnlySeeds() {
    let full = snapshot([epic(1, .needsHuman), epic(2, .needsHuman)], done: [ready(3), ready(4)])
    #expect(englishNotifications(from: nil, to: full).isEmpty)
}

@Test func anEpicThatLeavesAndEntersAgainNotifiesAgain() {
    let needs = snapshot([epic(7, .needsHuman)])
    let running = snapshot([epic(7)])
    #expect(englishNotifications(from: needs, to: running).isEmpty)
    #expect(englishNotifications(from: running, to: needs).count == 1)

    let listed = snapshot(done: [ready(9)])
    #expect(englishNotifications(from: listed, to: snapshot()).isEmpty)
    #expect(englishNotifications(from: snapshot(), to: listed).count == 1)
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
    func sendTest() {}
}

private func running(_ snapshot: PanelSnapshot) -> ConnectionState { .running(snapshot) }

@Test func theWatcherSeedsOnTheFirstSnapshotAndPostsWhatChangesAfter() {
    let centre = FakeCentre()
    let watcher = NotificationWatcher(centre: centre, bundle: english.bundle, locale: english.locale)
    watcher.react(to: running(snapshot([epic(1, .needsHuman)], done: [ready(3)])))
    watcher.react(to: running(snapshot([epic(1, .needsHuman), epic(2, .needsHuman)], done: [ready(3)])))
    watcher.react(to: running(snapshot([epic(1, .needsHuman), epic(2, .needsHuman)], done: [ready(3)])))
    #expect(centre.posted == [["a/b #2 needs attention"]])
}

@Test func theFirstSnapshotAfterCarrierWasStoppedAndStartedAgainSeedsToo() {
    let centre = FakeCentre()
    let watcher = NotificationWatcher(centre: centre, bundle: english.bundle, locale: english.locale)
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
    let watcher = NotificationWatcher(centre: centre, sound: { sound }, bundle: english.bundle, locale: english.locale)
    watcher.react(to: running(snapshot()))
    watcher.react(to: running(snapshot([epic(1, .needsHuman)], done: [ready(3)])))
    #expect(centre.sounds == [true, true])
    sound = false
    watcher.react(to: running(snapshot([epic(1, .needsHuman), epic(2, .needsHuman)], done: [ready(3)])))
    #expect(centre.sounds == [true, true, false])
}

@Test func theSoundIsOnUntilTurnedOff() {
    let defaults = UserDefaults(suiteName: "carrier-test-\(UUID().uuidString)")!
    #expect(AppPreferences(defaults: defaults).notifiesWithSound)
    defaults.set(false, forKey: Preference.notifySound.name)
    #expect(AppPreferences(defaults: defaults).notifiesWithSound == false)
}

// quiet hours

private func at(_ hour: Int, _ minute: Int = 0) -> Date {
    Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date(timeIntervalSince1970: 1_800_000_000))!
}

@Test func quietHoursAreOffUntilTurnedOnAndOfferTenPMToEightAM() {
    let defaults = UserDefaults(suiteName: "carrier-test-\(UUID().uuidString)")!
    #expect(AppPreferences(defaults: defaults).quietHours == QuietHours(enabled: false, start: 22 * 60, end: 8 * 60))
    #expect(AppPreferences(defaults: defaults).quietHours.contains(at(23)) == false)
    defaults.set(true, forKey: Preference.notifyQuiet.name)
    defaults.set(9 * 60 + 30, forKey: Preference.notifyQuietStart.name)
    #expect(AppPreferences(defaults: defaults).quietHours == QuietHours(enabled: true, start: 9 * 60 + 30, end: 8 * 60))
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
    let watcher = NotificationWatcher(centre: centre, quietHours: { QuietHours(enabled: true) }, now: { now }, bundle: english.bundle, locale: english.locale)
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
    let titles = { (kinds: NotificationKinds) in englishNotifications(from: before, to: both, kinds: kinds).map(\.title) }
    #expect(titles(NotificationKinds()) == ["a/b #7 needs attention", "a/b #9 is ready for test"])
    #expect(titles(NotificationKinds(needsYou: false)) == ["a/b #9 is ready for test"])
    #expect(titles(NotificationKinds(readyForTest: false)) == ["a/b #7 needs attention"])
    #expect(titles(NotificationKinds(needsYou: false, readyForTest: false)).isEmpty)
}

@Test func theWatcherReadsTheSwitchesOnEverySnapshotAndRemembersWhatItSkipped() {
    let centre = FakeCentre()
    var kinds = NotificationKinds(needsYou: false)
    let watcher = NotificationWatcher(centre: centre, kinds: { kinds }, bundle: english.bundle, locale: english.locale)
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
    #expect(AppPreferences(defaults: defaults).notificationKinds == NotificationKinds())
    defaults.set(false, forKey: Preference.notifyReadyForTest.name)
    #expect(AppPreferences(defaults: defaults).notificationKinds == NotificationKinds(readyForTest: false))
    defaults.set(false, forKey: Preference.notifyNeedsYou.name)
    #expect(AppPreferences(defaults: defaults).notificationKinds == NotificationKinds(needsYou: false, readyForTest: false))
}

@Test func aProblemIsOffUntilTurnedOnAndNotInFrontIsOnUntilTurnedOff() {
    let defaults = UserDefaults(suiteName: "carrier-test-\(UUID().uuidString)")!
    #expect(AppPreferences(defaults: defaults).notificationKinds.problem == false && AppPreferences(defaults: defaults).notifiesOnlyWhenAway)
    defaults.set(true, forKey: Preference.notifyProblem.name)
    defaults.set(false, forKey: Preference.notifyOnlyWhenAway.name)
    #expect(AppPreferences(defaults: defaults).notificationKinds.problem && AppPreferences(defaults: defaults).notifiesOnlyWhenAway == false)
}

@Test func aBannerIsHeldBackOnlyWhenAskedAndTheAppIsInFront_AndTheTestAlwaysShows() {
    #expect(shouldPresent(onlyWhenAway: true, appIsActive: true, isTest: false) == false)
    #expect(shouldPresent(onlyWhenAway: true, appIsActive: false, isTest: false))
    #expect(shouldPresent(onlyWhenAway: false, appIsActive: true, isTest: false))
    #expect(shouldPresent(onlyWhenAway: true, appIsActive: true, isTest: true))
    // a notice marked always shows with the app in front too, as the keep awake's end does
    #expect(shouldPresent(onlyWhenAway: true, appIsActive: true, isTest: false, always: true))
    #expect(EpicNotification(title: "t", body: "b").always == false)
}

// problems

private let withProblems = NotificationKinds(problem: true)

@Test func aProblemNotifiesOnceForEachTextAndOnlyWhenTheSwitchIsOn() {
    let none = snapshot()
    let stalled = snapshot(problem: "GitHub is stalled")
    #expect(englishNotifications(from: none, to: stalled).isEmpty)
    #expect(englishNotifications(from: none, to: stalled, kinds: withProblems) == [EpicNotification(title: "Carrier has a problem", body: "GitHub is stalled")])
    #expect(englishNotifications(from: stalled, to: stalled, kinds: withProblems).isEmpty)
    #expect(englishNotifications(from: stalled, to: snapshot(problem: "A profile was rejected"), kinds: withProblems).map(\.body) == ["A profile was rejected"])
    #expect(englishNotifications(from: stalled, to: none, kinds: withProblems).isEmpty)
    #expect(englishNotifications(from: none, to: stalled, kinds: withProblems).count == 1)
}

@Test func aRepoGitHubRefusesNotifiesOnceUntilItRecovers() {
    let fine = snapshot(watched: [watched("a/b")])
    let refused = snapshot(watched: [watched("a/b", ok: false, error: "Repository not found")])
    #expect(englishNotifications(from: fine, to: refused, kinds: withProblems) == [EpicNotification(title: "a/b was refused by GitHub", body: "Repository not found")])
    #expect(englishNotifications(from: refused, to: refused, kinds: withProblems).isEmpty)
    #expect(englishNotifications(from: refused, to: fine, kinds: withProblems).isEmpty)
    #expect(englishNotifications(from: fine, to: refused, kinds: withProblems).count == 1)
    #expect(englishNotifications(from: fine, to: refused).isEmpty)
}

private func clock(_ time: Date) -> (() -> Date, set: (Date) -> Void) {
    var now = time
    return ({ now }, { now = $0 })
}

@Test func aStopTheAppDidNotAskForIsAProblemAndOneItDidAskForIsNot() {
    let centre = FakeCentre()
    let watcher = NotificationWatcher(centre: centre, kinds: { withProblems }, bundle: english.bundle, locale: english.locale)
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
    let watcher = NotificationWatcher(centre: centre, kinds: { withProblems }, now: time.0, bundle: english.bundle, locale: english.locale)
    watcher.react(to: running(snapshot()))
    watcher.expectStop(for: 30)
    time.set(Date(timeIntervalSince1970: 31))
    watcher.react(to: .stopped)
    #expect(centre.posted == [["Carrier stopped"]])
}

@Test func withoutTheProblemSwitchAStopIsSilent_AndNeverStartedIsNotAStop() {
    let centre = FakeCentre()
    let off = NotificationWatcher(centre: centre, bundle: english.bundle, locale: english.locale)
    off.react(to: running(snapshot()))
    off.react(to: .stopped)
    let fresh = NotificationWatcher(centre: centre, kinds: { withProblems }, bundle: english.bundle, locale: english.locale)
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
    #expect(NotificationPermission.allowed(banners).text(bundle: english.bundle, locale: english.locale) == "Allowed · banners · sound on")
    #expect(NotificationPermission.allowed(.init(style: .alerts, soundOn: false)).text(bundle: english.bundle, locale: english.locale) == "Allowed · alerts · sound off")
    #expect(NotificationPermission.allowed(.init(style: .none, soundOn: true)).text(bundle: english.bundle, locale: english.locale) == "Allowed · notifications set to None")
    #expect(NotificationPermission.denied.text(bundle: english.bundle, locale: english.locale) == "Denied in System Settings")
    #expect(NotificationPermission.notAsked.text(bundle: english.bundle, locale: english.locale) == "Not asked yet · the first notification asks")
    #expect(NotificationPermission.noBundle.text(bundle: english.bundle, locale: english.locale) == "Only available from Carrier.app")
}

@Test func aTestThatMacOSWouldSwallowSaysWhy() {
    #expect(NotificationPermission.denied.testAdvice(bundle: english.bundle, locale: english.locale) == "Notifications are off for Carrier in System Settings.")
    #expect(NotificationPermission.allowed(.init(style: .none, soundOn: false)).testAdvice(bundle: english.bundle, locale: english.locale) != nil)
    #expect(NotificationPermission.allowed(banners).testAdvice(bundle: english.bundle, locale: english.locale) == nil)
    #expect(NotificationPermission.notAsked.testAdvice(bundle: english.bundle, locale: english.locale) == nil)
}

// the chat sessions

private func session(_ id: String, _ state: SessionState, archived: Bool = false) -> SessionRow {
    SessionRow(id: id, title: "Session \(id)", workspace: "w", agent: "a", state: state, updatedAt: Date(timeIntervalSince1970: 0), archived: archived)
}

private let chatDoneOn = NotificationKinds(chatDone: true)

@Test func aSessionThatGoesFromWorkingToWaitingNeedsAttentionAndOpensOnItself() {
    let due = englishChatNotifications(from: [session("1", .working)], to: [session("1", .waiting)])
    #expect(due == [EpicNotification(title: "Session 1 needs attention", body: "It waits for an approval", session: "1")])
}

@Test func aSessionThatGoesFromWorkingToIdleIsDoneOnlyWithTheSwitchOn() {
    #expect(englishChatNotifications(from: [session("1", .working)], to: [session("1", .idle)]).isEmpty)
    #expect(englishChatNotifications(from: [session("1", .working)], to: [session("1", .idle)], kinds: chatDoneOn).map(\.title) == ["Session 1 is done"])
}

@Test func anyOtherChangeOfASessionSaysNothing() {
    for (was, now) in [(SessionState.idle, SessionState.waiting), (.waiting, .idle), (.waiting, .working), (.idle, .working), (.working, .working), (.waiting, .waiting), (.working, .done)] {
        #expect(englishChatNotifications(from: [session("1", was)], to: [session("1", now)], kinds: chatDoneOn).isEmpty)
    }
}

@Test func aSessionSeenForTheFirstTimeNeverNotifies() {
    #expect(englishChatNotifications(from: nil, to: [session("1", .waiting), session("2", .idle)], kinds: chatDoneOn).isEmpty)
    #expect(englishChatNotifications(from: [session("1", .working)], to: [session("1", .working), session("2", .waiting)], kinds: chatDoneOn).isEmpty)
}

@Test func aSessionThatDisappearsOrIsArchivedSaysNothing() {
    #expect(englishChatNotifications(from: [session("1", .working)], to: [], kinds: chatDoneOn).isEmpty)
    #expect(englishChatNotifications(from: [session("1", .working)], to: [session("1", .idle, archived: true)], kinds: chatDoneOn).isEmpty)
}

@Test func theChatSwitchesSilenceEachKindAlone() {
    let before = [session("1", .working), session("2", .working)]
    let after = [session("1", .waiting), session("2", .idle)]
    #expect(englishChatNotifications(from: before, to: after, kinds: NotificationKinds(chatNeedsAttention: false, chatDone: true)).map(\.title) == ["Session 2 is done"])
    #expect(englishChatNotifications(from: before, to: after, kinds: NotificationKinds(chatNeedsAttention: true, chatDone: false)).map(\.title) == ["Session 1 needs attention"])
    #expect(englishChatNotifications(from: before, to: after, kinds: NotificationKinds(chatNeedsAttention: false, chatDone: false)).isEmpty)
}

@Test func theChatSwitchesStartWithNeedsAttentionOnAndDoneOff() {
    let defaults = UserDefaults(suiteName: "carrier-test-\(UUID().uuidString)")!
    #expect(AppPreferences(defaults: defaults).notificationKinds.chatNeedsAttention)
    #expect(AppPreferences(defaults: defaults).notificationKinds.chatDone == false)
    defaults.set(true, forKey: Preference.notifyChatDone.name)
    defaults.set(false, forKey: Preference.notifyChatNeedsAttention.name)
    #expect(AppPreferences(defaults: defaults).notificationKinds == NotificationKinds(chatNeedsAttention: false, chatDone: true))
}

@Test func theWatcherSeedsOnTheFirstListAndPostsTheChangesAfterWithTheSound() {
    let centre = FakeCentre()
    var sound = true
    let watcher = NotificationWatcher(centre: centre, sound: { sound }, bundle: english.bundle, locale: english.locale)
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
    #expect(AppPreferences(defaults: defaults).showsDockBadge)
    defaults.set(false, forKey: Preference.notifyDockBadge.name)
    #expect(AppPreferences(defaults: defaults).showsDockBadge == false)
}

@Test func theWatcherSetsTheBadgeFromTheTwoLastStatesAndClearsItAtZeroOrWithTheSwitchOff() {
    var shown = true
    var badge = -1
    let watcher = NotificationWatcher(centre: FakeCentre(), showsBadge: { shown }, setBadge: { badge = $0 }, bundle: english.bundle, locale: english.locale)
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

// reminders

private let start = Date(timeIntervalSince1970: 1_000_000)
private func after(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

@Test func aReminderIsDueOnceTheIntervalHasPassedSinceTheLastNotification() {
    let last = ["epic a/b#1": start]
    #expect(remindersDue(needing: ["epic a/b#1"], lastNotified: last, every: .quarterHour, now: after(14)).isEmpty)
    #expect(remindersDue(needing: ["epic a/b#1"], lastNotified: last, every: .quarterHour, now: after(15)) == ["epic a/b#1"])
    #expect(remindersDue(needing: ["epic a/b#1"], lastNotified: last, every: .hour, now: after(59)).isEmpty)
    #expect(remindersDue(needing: ["epic a/b#1"], lastNotified: last, every: .hour, now: after(60)) == ["epic a/b#1"])
}

@Test func neverRemindsNothing() {
    #expect(remindersDue(needing: ["a"], lastNotified: ["a": start], every: .never, now: after(10_000)).isEmpty)
}

@Test func anItemThatStoppedNeedingAttentionIsNotDueAndOneWithoutAHistoryYetIsNotEither() {
    let last = ["a": start, "b": start]
    #expect(remindersDue(needing: ["a", "c"], lastNotified: last, every: .quarterHour, now: after(20)) == ["a"])
}

@Test func theReminderIntervalIsNeverUntilChosenAndABadValueReadsAsNever() {
    let defaults = UserDefaults(suiteName: "carrier-test-\(UUID().uuidString)")!
    #expect(AppPreferences(defaults: defaults).reminderInterval == .never)
    defaults.set(900, forKey: Preference.notifyReminder.name)
    #expect(AppPreferences(defaults: defaults).reminderInterval == .quarterHour)
    defaults.set(3600, forKey: Preference.notifyReminder.name)
    #expect(AppPreferences(defaults: defaults).reminderInterval == .hour)
    defaults.set(7, forKey: Preference.notifyReminder.name)
    #expect(AppPreferences(defaults: defaults).reminderInterval == .never)
}

@Test func theWatcherRemindsAnEpicAndASessionAtTheirOwnPaceAndLeavesTheRestAlone() {
    let centre = FakeCentre()
    var clock = start
    let watcher = NotificationWatcher(centre: centre, reminder: { .quarterHour }, now: { clock }, bundle: english.bundle, locale: english.locale)
    watcher.react(to: running(snapshot([epic(1, .needsHuman)], done: [ready(3)])))
    watcher.react(toSessions: [session("1", .working)])
    clock = after(10)
    watcher.react(toSessions: [session("1", .waiting)])
    #expect(centre.posted == [["Session 1 needs attention"]])

    clock = after(15)
    watcher.remind()
    #expect(centre.posted.last == ["a/b #1 needs attention"])
    clock = after(24)
    watcher.remind()
    #expect(centre.posted.count == 2)
    clock = after(25)
    watcher.remind()
    #expect(centre.posted.last == ["Session 1 needs attention"])
    clock = after(30)
    watcher.remind()
    #expect(centre.posted.count == 4)
    #expect(centre.posted.flatMap { $0 }.contains { $0.contains("ready") } == false)
}

@Test func anItemThatStopsNeedingAttentionStopsRemindingAndOneThatReturnsStartsOver() {
    let centre = FakeCentre()
    var clock = start
    let watcher = NotificationWatcher(centre: centre, reminder: { .quarterHour }, now: { clock }, bundle: english.bundle, locale: english.locale)
    watcher.react(to: running(snapshot([epic(1, .needsHuman)])))
    clock = after(10)
    watcher.react(to: running(snapshot([epic(1)])))
    clock = after(11)
    watcher.react(to: running(snapshot([epic(1, .needsHuman)])))
    // its return notified at 11, so the clock started over then and the first 10 minutes did not count
    clock = after(25)
    watcher.remind()
    #expect(centre.posted == [["a/b #1 needs attention"]])
    clock = after(26)
    watcher.remind()
    #expect(centre.posted.count == 2)
}

@Test func withNeverOrASwitchOffTheWatcherDoesNotRemind() {
    let centre = FakeCentre()
    var clock = start
    var interval = ReminderInterval.never
    var kinds = NotificationKinds()
    let watcher = NotificationWatcher(centre: centre, kinds: { kinds }, reminder: { interval }, now: { clock }, bundle: english.bundle, locale: english.locale)
    watcher.react(to: running(snapshot([epic(1, .needsHuman)])))
    clock = after(120)
    watcher.remind()
    #expect(centre.posted.isEmpty)
    interval = .hour
    kinds.needsYou = false
    watcher.remind()
    #expect(centre.posted.isEmpty)
}

@Test func aReminderIsPostedLikeTheOriginalWouldBeWithTheSoundAndTheQuietHours() {
    let centre = FakeCentre()
    var clock = start
    var sound = true
    var quiet = QuietHours()
    let watcher = NotificationWatcher(centre: centre, sound: { sound }, quietHours: { quiet }, reminder: { .quarterHour }, now: { clock }, bundle: english.bundle, locale: english.locale)
    watcher.react(to: running(snapshot([epic(1, .needsHuman)])))
    clock = after(15)
    watcher.remind()
    #expect(centre.sounds == [true] && centre.quiets == [false])
    sound = false
    quiet = QuietHours(enabled: true, start: 0, end: 24 * 60 - 1)
    clock = after(30)
    watcher.remind()
    #expect(centre.sounds == [true, false] && centre.quiets == [false, true])
}

// the eight notifications in Spanish (design/copy/es.json): each is built from its arguments through its key, never from pieces of English

private func spanishNotifications(from previous: PanelSnapshot?, to new: PanelSnapshot, kinds: NotificationKinds = NotificationKinds(problem: true)) -> [EpicNotification] {
    notifications(from: previous, to: new, kinds: kinds, bundle: spanish.bundle, locale: spanish.locale)
}

private func spanishChatNotifications(from previous: [SessionRow], to new: [SessionRow]) -> [EpicNotification] {
    chatNotifications(from: previous, to: new, kinds: NotificationKinds(chatDone: true), bundle: spanish.bundle, locale: spanish.locale)
}

@Test func anEpicThatNeedsAPersonNotifiesInSpanishWithItsIssueNumberUngrouped() {
    // 1234 stays 1234: an issue number is not grouped by the locale (`es_AR` would write 1.234)
    let withReason = spanishNotifications(from: snapshot([epic(1234)]), to: snapshot([epic(1234, .needsHuman, reason: "review limit")]))
    #expect(withReason == [EpicNotification(title: "a/b #1234 requiere atención", body: "review limit", epic: EpicRef(repo: "a/b", issue: 1234))])
    let withoutReason = spanishNotifications(from: snapshot(), to: snapshot([epic(7, .needsHuman)]))
    #expect(withoutReason == [EpicNotification(title: "a/b #7 requiere atención", body: "Se detuvo y espera a una persona", epic: EpicRef(repo: "a/b", issue: 7))])
}

@Test func theReasonOfAnEpicThatNeedsAPersonIsSaidInSpanishWhenItHasACode() {
    var stopped = epic(7, .needsHuman, reason: "the head of PR #5 changed")
    stopped.needsHumanCode = "epic.stop.pullRequestNotOpen"
    stopped.needsHumanParams = ["pr": .string("5")]
    let due = spanishNotifications(from: snapshot(), to: snapshot([stopped]))
    #expect(due.map(\.body) == ["el PR #5 no está abierto"])
}

@Test func anEpicReadyForTestNotifiesInSpanishWithAndWithoutItsPullRequest() {
    let withPull = spanishNotifications(from: snapshot(), to: snapshot(done: [ready(9, pr: 1042)]))
    #expect(withPull == [EpicNotification(title: "a/b #9 está listo para probar", body: "Pull request #1042", epic: EpicRef(repo: "a/b", issue: 9))])
    let withoutPull = spanishNotifications(from: snapshot(), to: snapshot(done: [ready(9)]))
    #expect(withoutPull == [EpicNotification(title: "a/b #9 está listo para probar", body: "Su trabajo está terminado", epic: EpicRef(repo: "a/b", issue: 9))])
}

@Test func aSessionThatNeedsAnApprovalOrIsDoneNotifiesInSpanish() {
    let waiting = spanishChatNotifications(from: [session("1", .working)], to: [session("1", .waiting)])
    #expect(waiting == [EpicNotification(title: "Session 1 requiere atención", body: "Espera una aprobación", session: "1")])
    let done = spanishChatNotifications(from: [session("1", .working)], to: [session("1", .idle)])
    #expect(done == [EpicNotification(title: "Session 1 terminó", body: "El agente terminó su turno", session: "1")])
}

@Test func aProblemAndARefusedRepoNotifyInSpanishAndKeepTheTextsTheyCarry() {
    let stalled = spanishNotifications(from: snapshot(), to: snapshot(problem: "GitHub is stalled"))
    #expect(stalled == [EpicNotification(title: "Carrier tiene un problema", body: "GitHub is stalled")])
    let fine = snapshot(watched: [watched("a/b")])
    let withError = spanishNotifications(from: fine, to: snapshot(watched: [watched("a/b", ok: false, error: "Repository not found")]))
    #expect(withError == [EpicNotification(title: "a/b fue rechazado por GitHub", body: "Repository not found")])
    let withoutError = spanishNotifications(from: fine, to: snapshot(watched: [watched("a/b", ok: false)]))
    #expect(withoutError == [EpicNotification(title: "a/b fue rechazado por GitHub", body: "GitHub lo rechazó")])
}

@Test func aStopTheAppDidNotAskForNotifiesInSpanish() {
    final class Recording: NotificationCentre {
        var posted: [EpicNotification] = []
        func post(_ notifications: [EpicNotification]) { posted += notifications }
        func sendTest() {}
    }
    let centre = Recording()
    let watcher = NotificationWatcher(centre: centre, kinds: { withProblems }, bundle: spanish.bundle, locale: spanish.locale)
    watcher.react(to: running(snapshot()))
    watcher.react(to: .stopped)
    #expect(centre.posted.map(\.title) == ["Carrier se detuvo"])
    #expect(centre.posted.map(\.body) == ["Se detuvo sin que nadie lo pidiera. Abre la app para iniciarlo de nuevo."])
}

@Test func theTestNotificationOfSettingsSaysItsWordsInBothLanguages() {
    let inSpanish = testNotification(sound: true, quiet: false, bundle: spanish.bundle, locale: spanish.locale)
    #expect(inSpanish == EpicNotification(title: "Prueba de Carrier", body: "Las notificaciones funcionan", isTest: true, sound: true, quiet: false))
    let inEnglish = testNotification(sound: false, quiet: true, bundle: english.bundle, locale: english.locale)
    #expect(inEnglish == EpicNotification(title: "Carrier test", body: "Notifications work", isTest: true, sound: false, quiet: true))
}

@Test func theWatcherPostsInTheLanguageItWasGiven() {
    let centre = FakeCentre()
    let watcher = NotificationWatcher(centre: centre, bundle: spanish.bundle, locale: spanish.locale)
    watcher.react(to: running(snapshot()))
    watcher.react(to: running(snapshot([epic(2, .needsHuman)])))
    #expect(centre.posted == [["a/b #2 requiere atención"]])
}
