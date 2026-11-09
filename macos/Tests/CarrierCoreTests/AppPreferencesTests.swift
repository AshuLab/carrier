import Foundation
import Testing
@testable import CarrierCore

@Test func menuBarSettingsStartOnTheDefaults() {
    let store = AppPreferences(defaults: UserDefaults(suiteName: "menubar-\(UUID().uuidString)")!)
    #expect(store.style == .countAndBar)
    #expect(store.animates)
    #expect(store.showsEpics)
}

@Test func menuBarSettingsSurviveARelaunch() {
    let name = "menubar-\(UUID().uuidString)"
    let store = AppPreferences(defaults: UserDefaults(suiteName: name)!)
    store.style = .barOnly
    store.animates = false
    store.showsEpics = false
    let relaunched = AppPreferences(defaults: UserDefaults(suiteName: name)!)
    #expect(relaunched.style == .barOnly)
    #expect(relaunched.animates == false)
    #expect(relaunched.showsEpics == false)
}

@Test func anUnknownSavedStyleFallsBackToTheDefault() {
    let defaults = UserDefaults(suiteName: "menubar-\(UUID().uuidString)")!
    defaults.set("sparkles", forKey: AppPreferences.styleKey)
    #expect(AppPreferences(defaults: defaults).style == .countAndBar)
}

private let idle = PanelSnapshot(
    now: 0, slots: .init(busy: 0, total: 2), queue: [], epics: [], startedAt: 0, repos: 1, nextCheckAt: nil,
    problem: nil, paused: false, done: []
)

@Test func theStopQuestionHonoursItsSwitch() {
    let busy = PanelSnapshot(
        now: 0, slots: .init(busy: 1, total: 2), queue: [],
        epics: [PanelEpic(repo: "a/b", issue: 1, status: .running, stage: .ship, round: nil, maxReviews: 3, blockers: 0, stageSince: 0, lastActivityAt: nil, issueUrl: "u", prUrl: nil, lastError: nil, needsHumanReason: nil, slices: nil, executionId: nil)],
        startedAt: 0, repos: 1, nextCheckAt: nil, problem: nil, paused: false, done: []
    )
    #expect(busy.stopNeedsConfirmation)
    #expect(asksBeforeStopping(busy, switchOn: true))
    #expect(asksBeforeStopping(busy, switchOn: false) == false)
    // nothing running: no question whatever the switch says
    #expect(asksBeforeStopping(idle, switchOn: true) == false)
}

@Test func theNewDefaultsAreWhatTheAppDidBefore() {
    let store = AppPreferences(defaults: UserDefaults(suiteName: "prefs-\(UUID().uuidString)")!)
    #expect(store.confirmStop)
}

@Test func theConfirmationSurvivesARelaunchAndABadSavedValueReadsAsTheDefault() {
    let name = "prefs-\(UUID().uuidString)"
    AppPreferences(defaults: UserDefaults(suiteName: name)!).confirmStop = false
    #expect(AppPreferences(defaults: UserDefaults(suiteName: name)!).confirmStop == false)
    let defaults = UserDefaults(suiteName: "prefs-\(UUID().uuidString)")!
    defaults.set("maybe", forKey: AppPreferences.confirmStopKey)
    defaults.set("no", forKey: AppPreferences.animatesKey)
    let store = AppPreferences(defaults: defaults)
    #expect(store.confirmStop == AppPreferences.defaultConfirmStop && store.animates == AppPreferences.defaultAnimates)
}

@Test func resetOfGeneralTakesItsKeysOutAndLeavesTheKeysOfOtherPages() {
    let defaults = UserDefaults(suiteName: "prefs-\(UUID().uuidString)")!
    let store = AppPreferences(defaults: defaults)
    store.style = .barOnly
    store.animates = false
    store.showsEpics = false
    store.confirmStop = false
    defaults.set(false, forKey: notifyProblemKey)
    store.reset(.general)
    #expect(store.style == .countAndBar && store.animates && store.showsEpics && store.confirmStop)
    #expect(defaults.object(forKey: AppPreferences.styleKey) == nil)
    #expect(defaults.object(forKey: notifyProblemKey) as? Bool == false)
}
