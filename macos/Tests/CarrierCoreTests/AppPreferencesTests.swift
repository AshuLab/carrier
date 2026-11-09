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

@Test func appearanceStartsOnTheDefaultsAndSurvivesARelaunch() {
    let name = "appearance-\(UUID().uuidString)"
    let store = AppPreferences(defaults: UserDefaults(suiteName: name)!)
    #expect(store.colorScheme == .system)
    #expect(store.textSize == 100)
    #expect(store.density == .comfortable)
    store.colorScheme = .dark
    store.textSize = 115
    store.density = .compact
    let relaunched = AppPreferences(defaults: UserDefaults(suiteName: name)!)
    #expect(relaunched.colorScheme == .dark)
    #expect(relaunched.textSize == 115)
    #expect(relaunched.density == .compact)
    // the percent is the one the type scale reads
    #expect(TypeScale.stored(in: UserDefaults(suiteName: name)!).percent == 115)
}

@Test func aBadSavedAppearanceReadsAsTheDefaultAndTheTextSizeStaysInRange() {
    let defaults = UserDefaults(suiteName: "appearance-\(UUID().uuidString)")!
    defaults.set("sepia", forKey: AppPreferences.colorSchemeKey)
    defaults.set("roomy", forKey: AppPreferences.densityKey)
    let store = AppPreferences(defaults: defaults)
    #expect(store.colorScheme == .system)
    #expect(store.density == .comfortable)
    store.textSize = 300
    #expect(store.textSize == 130)
    store.textSize = 10
    #expect(store.textSize == 90)
}

@Test func resettingAppearanceLeavesTheOtherPagesAlone() {
    let store = AppPreferences(defaults: UserDefaults(suiteName: "appearance-\(UUID().uuidString)")!)
    store.colorScheme = .light
    store.textSize = 125
    store.density = .compact
    store.confirmStop = false
    store.reset(.appearance)
    #expect(store.colorScheme == .system)
    #expect(store.textSize == 100)
    #expect(store.density == .comfortable)
    #expect(store.confirmStop == false)
}

@Test func eachDensityHasItsFixedSidebarPaddingAndMessageGap() {
    #expect(Density.compact.rowPadding == 4)
    #expect(Density.compact.messageGap == 8)
    #expect(Density.comfortable.rowPadding == 7)
    #expect(Density.comfortable.messageGap == 12)
}

@Test func theThemeChoicesStartOnTheDefaultsAndSurviveARelaunch() {
    let name = "theme-\(UUID().uuidString)"
    let store = AppPreferences(defaults: UserDefaults(suiteName: name)!)
    #expect(store.theme == .carrier && store.accent == nil && store.tint == .off)
    store.theme = .forest
    store.accent = .orange
    store.tint = .strong
    store.setTranslucent(false)
    let relaunched = AppPreferences(defaults: UserDefaults(suiteName: name)!)
    #expect(relaunched.theme == .forest && relaunched.accent == .orange && relaunched.tint == .strong)
    #expect(relaunched.translucent(systemReducesTransparency: false) == false)
    relaunched.accent = nil
    #expect(AppPreferences(defaults: UserDefaults(suiteName: name)!).accent == nil)
}

@Test func translucentWindowsFollowReduceTransparencyUntilTheyAreChosen() {
    let store = AppPreferences(defaults: UserDefaults(suiteName: "theme-\(UUID().uuidString)")!)
    #expect(store.translucent(systemReducesTransparency: false))
    #expect(store.translucent(systemReducesTransparency: true) == false)
    store.setTranslucent(true)
    #expect(store.translucent(systemReducesTransparency: true))
}

@Test func aBadSavedThemeReadsAsTheDefaultAndResettingAppearanceClearsTheThemeChoices() {
    let defaults = UserDefaults(suiteName: "theme-\(UUID().uuidString)")!
    defaults.set("neon", forKey: AppPreferences.themeKey)
    defaults.set("teal", forKey: AppPreferences.accentKey)
    defaults.set("loud", forKey: AppPreferences.tintKey)
    let store = AppPreferences(defaults: defaults)
    #expect(store.theme == .carrier && store.accent == nil && store.tint == .off)
    store.theme = .ocean
    store.accent = .red
    store.tint = .subtle
    store.setTranslucent(false)
    store.reset(.appearance)
    #expect(store.theme == .carrier && store.accent == nil && store.tint == .off)
    #expect(store.translucent(systemReducesTransparency: false))
}
