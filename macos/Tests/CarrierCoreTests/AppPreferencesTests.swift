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

@Test func aBadSavedDisplayValueReadsAsTheDefault() {
    let defaults = UserDefaults(suiteName: "prefs-\(UUID().uuidString)")!
    defaults.set("sundial", forKey: AppPreferences.timeStyleKey)
    defaults.set(24, forKey: AppPreferences.clockHoursKey)
    let store = AppPreferences(defaults: defaults)
    #expect(store.timeStyle == .relative && store.clockHours == .system)
}

@Test func resetOfGeneralPutsTheDisplayBlockBackToo() {
    let defaults = UserDefaults(suiteName: "prefs-\(UUID().uuidString)")!
    let store = AppPreferences(defaults: defaults)
    store.timeStyle = .clock
    store.clockHours = .h24
    store.reset(.general)
    #expect(store.timeStyle == .relative && store.clockHours == .system)
}

@Test func theMessageBoxDefaultsAreReturnToSendNoWritingToolsSpellCheckOnCorrectionOff() {
    let store = AppPreferences(defaults: UserDefaults(suiteName: "prefs-\(UUID().uuidString)")!)
    #expect(store.sendKey == .return && store.writingTools == false && store.checksSpelling && store.correctsSpelling == false)
}

@Test func theMessageBoxChoicesSurviveARelaunchAndABadSavedKeyReadsAsTheDefault() {
    let name = "prefs-\(UUID().uuidString)"
    let first = AppPreferences(defaults: UserDefaults(suiteName: name)!)
    first.sendKey = .commandReturn
    first.writingTools = true
    first.checksSpelling = false
    first.correctsSpelling = true
    let second = AppPreferences(defaults: UserDefaults(suiteName: name)!)
    #expect(second.sendKey == .commandReturn && second.writingTools && second.checksSpelling == false && second.correctsSpelling)
    let defaults = UserDefaults(suiteName: "prefs-\(UUID().uuidString)")!
    defaults.set("enter", forKey: AppPreferences.sendKeyKey)
    #expect(AppPreferences(defaults: defaults).sendKey == .return)
}

@Test func resetOfChatPutsTheMessageBoxBackAndLeavesOtherPages() {
    let defaults = UserDefaults(suiteName: "prefs-\(UUID().uuidString)")!
    let store = AppPreferences(defaults: defaults)
    store.sendKey = .commandReturn
    store.writingTools = true
    store.checksSpelling = false
    store.correctsSpelling = true
    store.confirmStop = false
    store.reset(.chat)
    #expect(store.sendKey == .return && store.writingTools == false && store.checksSpelling && store.correctsSpelling == false)
    #expect(store.confirmStop == false)
}

@Test func theSendKeySendsOnItsOwnAndNeverWithShift() {
    #expect(SendKey.return.sends(command: false, shift: false))
    #expect(SendKey.return.sends(command: true, shift: false) == false)
    #expect(SendKey.commandReturn.sends(command: true, shift: false))
    #expect(SendKey.commandReturn.sends(command: false, shift: false) == false)
    #expect(SendKey.return.sends(command: false, shift: true) == false)
    #expect(SendKey.commandReturn.sends(command: true, shift: true) == false)
}
