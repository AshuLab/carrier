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
    defaults.set(false, forKey: Preference.notifyProblem.name)
    store.reset(.general)
    // the stop confirmation is the Engine page's now: General's Reset leaves it as the person set it
    #expect(store.style == .countAndBar && store.animates && store.showsEpics && store.confirmStop == false)
    #expect(defaults.object(forKey: AppPreferences.styleKey) == nil)
    #expect(defaults.object(forKey: Preference.notifyProblem.name) as? Bool == false)
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
    // the ring beside the microphone is on until the person turns it off
    #expect(store.showsContextUsage)
}

@Test func theMessageBoxChoicesSurviveARelaunchAndABadSavedKeyReadsAsTheDefault() {
    let name = "prefs-\(UUID().uuidString)"
    let first = AppPreferences(defaults: UserDefaults(suiteName: name)!)
    first.sendKey = .commandReturn
    first.writingTools = true
    first.checksSpelling = false
    first.correctsSpelling = true
    first.showsContextUsage = false
    let second = AppPreferences(defaults: UserDefaults(suiteName: name)!)
    #expect(second.sendKey == .commandReturn && second.writingTools && second.checksSpelling == false && second.correctsSpelling && second.showsContextUsage == false)
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
    store.showsContextUsage = false
    store.confirmStop = false
    store.reset(.chat)
    #expect(store.sendKey == .return && store.writingTools == false && store.checksSpelling && store.correctsSpelling == false && store.showsContextUsage)
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

@Test func eachDensityHasItsFixedSidebarPadding() {
    #expect(Density.compact.rowPadding == 4)
    #expect(Density.comfortable.rowPadding == 7)
}

@Test func theChatTextIsTheChatsOwnAndResetsWithTheChatPage() {
    let store = AppPreferences(defaults: UserDefaults(suiteName: "chat-text-\(UUID().uuidString)")!)
    #expect(store.chatTextSize == 13 && store.chatLineSpacing == .normal && store.chatMessageSpacing == .comfortable)
    store.chatTextSize = 40
    #expect(store.chatTextSize == ChatText.sizeRange.upperBound)
    store.chatTextSize = 15
    store.chatLineSpacing = .loose
    store.chatMessageSpacing = .spacious
    #expect(store.chatTextSize == 15 && store.chatLineSpacing == .loose && store.chatMessageSpacing == .spacious)
    store.reset(.chat)
    #expect(store.chatTextSize == 13 && store.chatLineSpacing == .normal && store.chatMessageSpacing == .comfortable)
}

@Test func everyChatChoiceRoundTripsAndANumberThatIsNotOneIsTheDefault() {
    let store = AppPreferences(defaults: UserDefaults(suiteName: "chat-choices-\(UUID().uuidString)")!)
    for spacing in ChatLineSpacing.allCases { store.chatLineSpacing = spacing; #expect(store.chatLineSpacing == spacing) }
    for spacing in MessageSpacing.allCases { store.chatMessageSpacing = spacing; #expect(store.chatMessageSpacing == spacing) }
    #expect(ChatText.clamped(.nan) == ChatText.defaultSize)
}

@Test func thePersonsBubbleAddsNoRoomBetweenItsLinesAtNormal() {
    #expect(ChatLineSpacing.tight.extraOverNormal(forSize: 13) == 0 && ChatLineSpacing.normal.extraOverNormal(forSize: 13) == 0)
    #expect(ChatLineSpacing.loose.extraOverNormal(forSize: 13) == 3)
}

@Test func eachChatLineSpacingKeepsTheFourPointsAtThirteen() {
    #expect(ChatLineSpacing.normal.extra(forSize: 13) == 4)
    #expect(ChatLineSpacing.tight.extra(forSize: 13) < 4 && ChatLineSpacing.loose.extra(forSize: 13) > 4)
    #expect(MessageSpacing.comfortable.gap == 12)
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

@Test func monospaceSettingsStartOnTheirDefaults() {
    let mono = AppPreferences(defaults: UserDefaults(suiteName: "mono-\(UUID().uuidString)")!).monospace
    #expect(mono == MonospaceSettings())
    #expect(mono.family == MonospaceSettings.systemFamily && mono.size == 12 && mono.lineHeight == .normal)
    #expect(mono.ligatures && mono.wrapLongLines && mono.lineNumbers == false)
}

@Test func monospaceSettingsSurviveARelaunchAndResetWithAppearance() {
    let name = "mono-\(UUID().uuidString)"
    let store = AppPreferences(defaults: UserDefaults(suiteName: name)!)
    let chosen = MonospaceSettings(family: "Menlo", size: 14, lineHeight: .loose, ligatures: false, wrapLongLines: false, lineNumbers: true)
    store.monospace = chosen
    #expect(AppPreferences(defaults: UserDefaults(suiteName: name)!).monospace == chosen)
    store.confirmStop = false
    store.reset(.chat)
    #expect(store.monospace == chosen)  // Chat's Reset leaves them: they are on the Appearance page
    store.reset(.appearance)
    #expect(store.monospace == MonospaceSettings())
    #expect(store.confirmStop == false)
}

@Test func aBadSavedMonospaceValueReadsAsTheDefaultAndTheSizeStaysInRange() {
    let defaults = UserDefaults(suiteName: "mono-\(UUID().uuidString)")!
    defaults.set("huge", forKey: AppPreferences.monospaceLineHeightKey)
    defaults.set("yes", forKey: AppPreferences.monospaceWrapKey)
    defaults.set(300.0, forKey: AppPreferences.monospaceSizeKey)
    let store = AppPreferences(defaults: defaults)
    #expect(store.monospace.lineHeight == .normal && store.monospace.wrapLongLines)
    #expect(store.monospace.size == 20)
    defaults.set(2.0, forKey: AppPreferences.monospaceSizeKey)
    #expect(store.monospace.size == 9)
}

@Test func aFamilyThatIsNoLongerInstalledFallsBackToTheSystemsMonospacedFont() {
    let installed = ["Menlo", "Courier New"]
    #expect(MonospaceSettings(family: "Menlo").resolved(installed: installed).family == "Menlo")
    #expect(MonospaceSettings(family: "Gone Mono").resolved(installed: installed).family == MonospaceSettings.systemFamily)
    #expect(MonospaceSettings().resolved(installed: []).family == MonospaceSettings.systemFamily)
    // only the family changes
    #expect(MonospaceSettings(family: "Gone Mono", size: 15).resolved(installed: installed).size == 15)
}

@Test func eachLineHeightMapsToItsMultipleAndItsExtraSpacing() {
    #expect(LineHeight.tight.multiple == 1.2 && LineHeight.normal.multiple == 1.45 && LineHeight.loose.multiple == 1.7)
    #expect(LineHeight.tight.extraSpacing(forSize: 12) == 0)
    #expect(abs(LineHeight.normal.extraSpacing(forSize: 12) - 3) < 0.0001)
    #expect(abs(LineHeight.loose.extraSpacing(forSize: 12) - 6) < 0.0001)
}

@Test func eachMessageWidthHasItsFixedMaximumInPoints() {
    #expect(MessageWidth.narrow.points == 640)
    #expect(MessageWidth.medium.points == 760)
    #expect(MessageWidth.wide.points == 880)
    #expect(MessageWidth.ultraWide.points == 1040 && MessageWidth.ultraWide.title == "Ultra wide")
    #expect(MessageWidth.widest.points == 1280 && MessageWidth.widest.title == "Widest")
    #expect(MessageWidth.allCases.last == .widest)  // the preview's track is the last, the widest
    #expect(AppPreferences.defaultMessageWidth == .medium)
}

@Test func theMessageWidthSurvivesARelaunchFallsBackWhenBadAndResetsWithChat() {
    let name = "width-\(UUID().uuidString)"
    let store = AppPreferences(defaults: UserDefaults(suiteName: name)!)
    #expect(store.messageWidth == .medium)
    store.messageWidth = .wide
    store.confirmStop = false
    #expect(AppPreferences(defaults: UserDefaults(suiteName: name)!).messageWidth == .wide)
    store.reset(.chat)
    #expect(store.messageWidth == .medium && store.confirmStop == false)
    UserDefaults(suiteName: name)!.set("huge", forKey: AppPreferences.messageWidthKey)
    #expect(store.messageWidth == .medium)
}

@Test func whileTheAgentWorksQueuesByDefaultSurvivesARelaunchFallsBackAndResetsWithChat() {
    let name = "prefs-\(UUID().uuidString)"
    let first = AppPreferences(defaults: UserDefaults(suiteName: name)!)
    #expect(first.whileWorking == .queue)
    first.whileWorking = .interrupt
    #expect(AppPreferences(defaults: UserDefaults(suiteName: name)!).whileWorking == .interrupt)
    first.reset(.chat)
    #expect(first.whileWorking == .queue)
    let defaults = UserDefaults(suiteName: "prefs-\(UUID().uuidString)")!
    defaults.set("stop", forKey: AppPreferences.whileWorkingKey)
    #expect(AppPreferences(defaults: defaults).whileWorking == .queue)
}

@Test func theConversationChoicesSurviveARelaunchResetWithTheChatPageAndABadValueReadsAsTheDefault() {
    let name = "prefs-\(UUID().uuidString)"
    let first = AppPreferences(defaults: UserDefaults(suiteName: name)!)
    #expect(first.followsOutput && first.messageTimes == .hover)
    first.followsOutput = false
    first.messageTimes = .always
    let second = AppPreferences(defaults: UserDefaults(suiteName: name)!)
    #expect(second.followsOutput == false && second.messageTimes == .always)
    second.reset(.chat)
    #expect(second.followsOutput && second.messageTimes == .hover)
    let defaults = UserDefaults(suiteName: "prefs-\(UUID().uuidString)")!
    defaults.set("sometimes", forKey: AppPreferences.messageTimesKey)
    #expect(AppPreferences(defaults: defaults).messageTimes == .hover)
}

@Test func aTimeShowsAsTheSettingSays() {
    #expect(MessageTimes.never.shows(hovering: true) == false)
    #expect(MessageTimes.hover.shows(hovering: false) == false && MessageTimes.hover.shows(hovering: true))
    #expect(MessageTimes.always.shows(hovering: false))
}

@Test func theConversationDefaultsAreToolsCollapsedFailedCallsOpenAndFiftyLines() {
    let store = AppPreferences(defaults: UserDefaults(suiteName: "prefs-\(UUID().uuidString)")!)
    #expect(store.toolOutput == .collapsed && store.opensFailedCalls && store.outputLength == .short)
}

@Test func theConversationChoicesSurviveARelaunchAndABadSavedValueReadsAsTheDefault() {
    let name = "prefs-\(UUID().uuidString)"
    let first = AppPreferences(defaults: UserDefaults(suiteName: name)!)
    first.toolOutput = .expanded
    first.opensFailedCalls = false
    first.outputLength = .long
    let second = AppPreferences(defaults: UserDefaults(suiteName: name)!)
    #expect(second.toolOutput == .expanded && second.opensFailedCalls == false && second.outputLength == .long)
    let defaults = UserDefaults(suiteName: "prefs-\(UUID().uuidString)")!
    defaults.set("open", forKey: AppPreferences.toolOutputKey)
    defaults.set(7, forKey: AppPreferences.outputLengthKey)
    let bad = AppPreferences(defaults: defaults)
    #expect(bad.toolOutput == .collapsed && bad.outputLength == .short)
}

@Test func resetOfChatPutsTheConversationBackToo() {
    let store = AppPreferences(defaults: UserDefaults(suiteName: "prefs-\(UUID().uuidString)")!)
    store.toolOutput = .hidden
    store.opensFailedCalls = false
    store.outputLength = .long
    store.reset(.chat)
    #expect(store.toolOutput == .collapsed && store.opensFailedCalls && store.outputLength == .short)
}

@Test func askingBeforeDeletingASessionIsOnByDefaultSurvivesARelaunchFallsBackAndResetsWithSessions() {
    let name = "delete-\(UUID().uuidString)"
    let first = AppPreferences(defaults: UserDefaults(suiteName: name)!)
    #expect(first.confirmDelete)
    first.confirmDelete = false
    #expect(AppPreferences(defaults: UserDefaults(suiteName: name)!).confirmDelete == false)
    first.reset(.chat)
    #expect(first.confirmDelete == false)
    first.reset(.sessions)
    #expect(first.confirmDelete)
    let defaults = UserDefaults(suiteName: "delete-\(UUID().uuidString)")!
    defaults.set("never", forKey: AppPreferences.confirmDeleteKey)
    #expect(AppPreferences(defaults: defaults).confirmDelete)
}

@Test func whatANewSessionStartsWithIsReadFromTheSameKeysAsBeforeAndEachPageResetsItsOwn() {
    let defaults = UserDefaults(suiteName: "start-\(UUID().uuidString)")!
    #expect(AppPreferences.newSessionAgentKey == "chat.newSession.agent" && AppPreferences.newSessionModelKey == "chat.newSession.model")
    #expect(AppPreferences.newSessionEffortKey == "chat.newSession.effort" && AppPreferences.newSessionAccessKey == "chat.newSession.access")
    #expect(AppPreferences.confirmDeleteKey == "chat.confirmDelete")
    defaults.set("codex", forKey: "chat.newSession.agent")
    defaults.set("gpt-5", forKey: "chat.newSession.model")
    defaults.set("high", forKey: "chat.newSession.effort")
    defaults.set(NewSessionStart.json(fromAccess: ["sandbox": "read-only"]), forKey: "chat.newSession.access")
    let store = AppPreferences(defaults: defaults)
    store.sendKey = .commandReturn
    let chosen = NewSessionStart(agent: "codex", model: "gpt-5", effort: "high", access: ["sandbox": "read-only"])
    #expect(store.newSessionStart == chosen)
    store.reset(.chat)
    #expect(store.newSessionStart == chosen && store.sendKey == .return)
    store.sendKey = .commandReturn
    store.reset(.sessions)
    #expect(store.newSessionStart == NewSessionStart() && store.sendKey == .commandReturn)
}

@Test func showReasoningIsOnByDefaultSurvivesARelaunchFallsBackAndResetsWithChat() {
    let name = "prefs-\(UUID().uuidString)"
    let first = AppPreferences(defaults: UserDefaults(suiteName: name)!)
    #expect(first.showsReasoning)
    first.showsReasoning = false
    #expect(AppPreferences(defaults: UserDefaults(suiteName: name)!).showsReasoning == false)
    first.reset(.chat)
    #expect(first.showsReasoning)
    let defaults = UserDefaults(suiteName: "prefs-\(UUID().uuidString)")!
    defaults.set("never", forKey: AppPreferences.showsReasoningKey)
    #expect(AppPreferences(defaults: defaults).showsReasoning)
}

@Test func theDiffStyleIsUnifiedByDefaultSurvivesARelaunchAndResetsWithChat() {
    let name = "prefs-\(UUID().uuidString)"
    let first = AppPreferences(defaults: UserDefaults(suiteName: name)!)
    #expect(first.diffStyle == .unified)
    first.diffStyle = .split
    let second = AppPreferences(defaults: UserDefaults(suiteName: name)!)
    #expect(second.diffStyle == .split)
    second.reset(.chat)
    #expect(second.diffStyle == .unified)
    let defaults = UserDefaults(suiteName: "prefs-\(UUID().uuidString)")!
    defaults.set("sideways", forKey: AppPreferences.diffStyleKey)
    #expect(AppPreferences(defaults: defaults).diffStyle == .unified)
}

@Test func resetOfNotificationsTakesEveryNotifyKeyOutAndLeavesOtherPages() {
    let defaults = UserDefaults(suiteName: "prefs-\(UUID().uuidString)")!
    let store = AppPreferences(defaults: defaults)
    let keys = [
        Preference.notifyNeedsYou.name, Preference.notifyReadyForTest.name, Preference.notifyProblem.name, Preference.notifyChatNeedsAttention.name, Preference.notifyChatDone.name, Preference.notifyOnlyWhenAway.name,
        Preference.notifyDockBadge.name, Preference.notifySound.name, Preference.notifyReminder.name, Preference.notifyQuiet.name, Preference.notifyQuietStart.name, Preference.notifyQuietEnd.name,
    ]
    for key in keys { defaults.set(1, forKey: key) }
    store.confirmStop = false
    store.reset(.notifications)
    #expect(keys.allSatisfy { defaults.object(forKey: $0) == nil })
    #expect(store.confirmStop == false)
}

private func dictationDefaults() -> (name: String, defaults: UserDefaults) {
    let name = "dictation-\(UUID().uuidString)"
    return (name, UserDefaults(suiteName: name)!)
}

private func speechModel(_ id: String, _ recognizer: RecognizerID) -> SpeechModel {
    SpeechModel(
        id: id, recognizer: recognizer, name: id, bytes: nil, languages: ["en"], detectsLanguage: false, partial: .native,
        licence: "None", card: URL(string: "https://github.com/AshuLab/carrier")!
    )
}

@Test func dictationStartsOnAndWithNoChoiceMade() {
    let store = AppPreferences(defaults: dictationDefaults().defaults)
    #expect(store.dictationEnabled)
    #expect(store.dictationModelID == nil && store.dictationLanguage == nil)
}

@Test func theDictationChoicesSurviveARelaunch() {
    let (name, defaults) = dictationDefaults()
    let store = AppPreferences(defaults: defaults)
    store.dictationEnabled = false
    store.dictationModelID = "fluidaudio.parakeet-tdt-v3"
    store.dictationLanguage = automaticLanguage
    let relaunched = AppPreferences(defaults: UserDefaults(suiteName: name)!)
    #expect(relaunched.dictationEnabled == false)
    #expect(relaunched.dictationModelID == "fluidaudio.parakeet-tdt-v3")
    #expect(relaunched.dictationLanguage == automaticLanguage)
}

@Test func cleanupStartsOffWithTheDefaultPromptAndSurvivesARelaunch() {
    let (name, defaults) = dictationDefaults()
    let store = AppPreferences(defaults: defaults)
    #expect(store.dictationCleanupEnabled == false && store.dictationCleanupServer == nil && store.dictationCleanupModel == nil)
    #expect(store.dictationCleanupPrompt == defaultCleanupPrompt)
    store.dictationCleanupServer = .ollama
    store.dictationCleanupModel = "llama3.2:3b"
    store.dictationCleanupEnabled = true
    store.dictationCleanupPrompt = "Translate to English"
    let relaunched = AppPreferences(defaults: UserDefaults(suiteName: name)!)
    #expect(relaunched.dictationCleanupEnabled && relaunched.dictationCleanupServer == .ollama && relaunched.dictationCleanupModel == "llama3.2:3b")
    #expect(relaunched.dictationCleanupPrompt == "Translate to English")
}

@Test func theCleanupSwitchDoesNotDependOnTheServerOrTheModel() {
    let store = AppPreferences(defaults: dictationDefaults().defaults)
    store.dictationCleanupEnabled = true
    #expect(store.dictationCleanupEnabled)
    store.dictationCleanupServer = .lmStudio
    store.dictationCleanupModel = "qwen"
    store.dictationCleanupModel = nil
    #expect(store.dictationCleanupEnabled)
    store.dictationCleanupEnabled = false
    #expect(store.dictationCleanupEnabled == false)
}

@Test func resettingDictationPutsCleanupBackToOffWithTheDefaultPrompt() {
    let store = AppPreferences(defaults: dictationDefaults().defaults)
    store.dictationCleanupServer = .lmStudio
    store.dictationCleanupModel = "qwen"
    store.dictationCleanupEnabled = true
    store.dictationCleanupPrompt = ""
    store.reset(.dictation)
    #expect(store.dictationCleanupEnabled == false && store.dictationCleanupServer == nil && store.dictationCleanupModel == nil)
    #expect(store.dictationCleanupPrompt == defaultCleanupPrompt)
}

@Test func anUnknownSavedSpeechModelFallsBackToApples() {
    let apple = speechModel("apple.speech-analyzer", .apple)
    let parakeet = speechModel("fluidaudio.parakeet-tdt-v3", .fluidAudio)
    let store = AppPreferences(defaults: dictationDefaults().defaults)
    #expect(store.dictationModel(among: [apple, parakeet]) == apple)
    store.dictationModelID = "fluidaudio.parakeet-tdt-v3"
    #expect(store.dictationModel(among: [apple, parakeet]) == parakeet)
    store.dictationModelID = "whisper.gone"
    #expect(store.dictationModel(among: [apple, parakeet]) == apple)
}

@Test func resettingDictationPutsItsDefaultsBackAndLeavesTheModelFilesAndOtherPagesAlone() throws {
    let store = AppPreferences(defaults: dictationDefaults().defaults)
    let models = FileManager.default.temporaryDirectory.appendingPathComponent("models-\(UUID().uuidString)/fluidaudio/parakeet")
    try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
    let weights = models.appendingPathComponent("weights.bin")
    try Data("weights".utf8).write(to: weights)
    store.dictationEnabled = false
    store.dictationModelID = "fluidaudio.parakeet-tdt-v3"
    store.dictationLanguage = "es"
    store.sendKey = .commandReturn
    store.reset(.dictation)
    #expect(store.dictationEnabled)
    #expect(store.dictationModelID == nil && store.dictationLanguage == nil)
    #expect(store.sendKey == .commandReturn)
    #expect(try Data(contentsOf: weights) == Data("weights".utf8))
}

@Test func dictatingInAnyAppIsOnByDefaultSurvivesARelaunchAndResetsWithDictation() {
    let (name, defaults) = dictationDefaults()
    let store = AppPreferences(defaults: defaults)
    #expect(store.dictationGlobal && AppPreferences.dictationGlobalKey == "dictation.global")
    store.dictationGlobal = false
    #expect(AppPreferences(defaults: UserDefaults(suiteName: name)!).dictationGlobal == false)
    store.reset(.notifications)
    #expect(store.dictationGlobal == false)
    store.reset(.dictation)
    #expect(store.dictationGlobal)
}

@Test func theAccessibilityExplanationIsRememberedAndNotResetWithDictation() {
    let (name, defaults) = dictationDefaults()
    let store = AppPreferences(defaults: defaults)
    #expect(store.dictationAccessibilityExplained == false && AppPreferences.dictationAccessibilityExplainedKey == "dictation.accessibilityExplained")
    store.dictationAccessibilityExplained = true
    #expect(AppPreferences(defaults: UserDefaults(suiteName: name)!).dictationAccessibilityExplained)
    store.reset(.dictation)
    #expect(store.dictationAccessibilityExplained)
}

@Test func theDictationSoundsStartOnAtSixtySurviveARelaunchReadOnlyWhatIsOnOfferAndResetWithDictation() {
    let (name, defaults) = dictationDefaults()
    let store = AppPreferences(defaults: defaults)
    #expect(store.dictationSounds == DictationSounds())
    #expect(store.dictationSounds.startOn && store.dictationSounds.endOn && store.dictationSounds.volume == 60)
    #expect(AppPreferences.dictationStartSoundOnKey == "dictation.sound.start.on" && AppPreferences.dictationStartSoundKey == "dictation.sound.start")
    #expect(AppPreferences.dictationEndSoundOnKey == "dictation.sound.end.on" && AppPreferences.dictationEndSoundKey == "dictation.sound.end")
    #expect(AppPreferences.dictationSoundVolumeKey == "dictation.sound.volume")
    var sounds = DictationSounds()
    (sounds.startOn, sounds.start, sounds.endOn, sounds.end, sounds.volume) = (false, "Glass", false, "Tink", 25)
    store.dictationSounds = sounds
    #expect(AppPreferences(defaults: UserDefaults(suiteName: name)!).dictationSounds == sounds)
    defaults.set("Basso", forKey: AppPreferences.dictationStartSoundKey)
    defaults.set(500, forKey: AppPreferences.dictationSoundVolumeKey)
    #expect(store.dictationSounds.start == DictationSounds.defaultStart && store.dictationSounds.volume == 100)
    store.reset(.notifications)
    #expect(store.dictationSounds.endOn == false)
    store.reset(.dictation)
    #expect(store.dictationSounds == DictationSounds())
}

@MainActor @Test func keepingTheTextIsOnByDefaultSurvivesARelaunchAndResetsWithDictationWithoutTouchingTheHistory() async {
    let (name, defaults) = dictationDefaults()
    let store = AppPreferences(defaults: defaults)
    #expect(store.dictationKeepText && AppPreferences.dictationKeepTextKey == "dictation.history.keepText")
    store.dictationKeepText = false
    #expect(AppPreferences(defaults: UserDefaults(suiteName: name)!).dictationKeepText == false)
    let folder = NSTemporaryDirectory() + "carrier-history-reset-\(UUID().uuidString)"
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let records = DictationRecords(carrierFolder: folder, keep: { true })
    let kept = DictationEntry(started: Date(timeIntervalSince1970: 1_700_000_000), text: "hola", model: "Apple", transcription: 0.2, audio: 3, destination: "Notes", outcome: .pasted)
    records.record(kept)
    store.reset(.notifications)
    #expect(store.dictationKeepText == false)
    store.reset(.dictation)
    #expect(store.dictationKeepText)
    let again = DictationRecords(carrierFolder: folder, keep: { true })
    await again.load()
    #expect(records.entries == [kept] && again.entries == [kept])
}

@Test func theAudioOfTheHistoryIsOffAndThirtyDaysByDefaultSurvivesARelaunchFallsBackAndResetsWithDictation() {
    let (name, defaults) = dictationDefaults()
    let store = AppPreferences(defaults: defaults)
    #expect(store.dictationKeepAudio == false && store.dictationDeleteAudioAfter == 30)
    store.dictationKeepAudio = true
    store.dictationDeleteAudioAfter = 0
    let again = AppPreferences(defaults: UserDefaults(suiteName: name)!)
    #expect(again.dictationKeepAudio && again.dictationDeleteAudioAfter == 0)
    store.dictationDeleteAudioAfter = 12
    #expect(store.dictationDeleteAudioAfter == 30)
    store.reset(.dictation)
    #expect(store.dictationKeepAudio == false && store.dictationDeleteAudioAfter == 30)
}

@Test func theSpeechModelIsKeptReadyAndReleasedAfterFifteenMinutesByDefaultSurvivesARelaunchFallsBackAndResetsWithDictation() {
    let (name, defaults) = dictationDefaults()
    let store = AppPreferences(defaults: defaults)
    #expect(AppPreferences.dictationKeepReadyKey == "dictation.model.keepReady" && AppPreferences.dictationReleaseAfterKey == "dictation.model.releaseAfter")
    #expect(store.dictationKeepReady && store.dictationReleaseAfter == 15)
    store.dictationKeepReady = false
    store.dictationReleaseAfter = 0
    let again = AppPreferences(defaults: UserDefaults(suiteName: name)!)
    #expect(again.dictationKeepReady == false && again.dictationReleaseAfter == 0)
    store.dictationReleaseAfter = 12
    #expect(store.dictationReleaseAfter == 15)
    store.dictationReleaseAfter = 60
    #expect(store.dictationReleaseAfter == 60)
    store.reset(.dictation)
    #expect(store.dictationKeepReady && store.dictationReleaseAfter == 15)
}

@Test func workInIsTheBaseFolderByDefaultSurvivesARelaunchFallsBackAndResetsWithSessionsOnly() {
    let name = "workin-\(UUID().uuidString)"
    let first = AppPreferences(defaults: UserDefaults(suiteName: name)!)
    #expect(first.workIn == .baseFolder && AppPreferences.workInKey == "chat.newSession.workIn")
    first.workIn = .newWorktree
    #expect(AppPreferences(defaults: UserDefaults(suiteName: name)!).workIn == .newWorktree)
    first.reset(.chat)
    #expect(first.workIn == .newWorktree)
    first.reset(.sessions)
    #expect(first.workIn == .baseFolder)
    let defaults = UserDefaults(suiteName: "workin-\(UUID().uuidString)")!
    defaults.set("somewhere", forKey: AppPreferences.workInKey)
    #expect(AppPreferences(defaults: defaults).workIn == .baseFolder)
}

@Test func theChatSurfaceIsGlassUntilChosenFallsBackWhenBadAndResetsWithChat() {
    let name = "surface-\(UUID().uuidString)"
    let store = AppPreferences(defaults: UserDefaults(suiteName: name)!)
    #expect(store.chatSurface == .glass && AppPreferences.defaultChatSurface == .glass)
    store.chatSurface = .flat
    store.confirmStop = false
    #expect(AppPreferences(defaults: UserDefaults(suiteName: name)!).chatSurface == .flat)
    store.reset(.appearance)
    #expect(store.chatSurface == .flat)  // it is on the Chat page
    store.reset(.chat)
    #expect(store.chatSurface == .glass && store.confirmStop == false)
    UserDefaults(suiteName: name)!.set("frosted", forKey: AppPreferences.chatSurfaceKey)
    #expect(store.chatSurface == .glass)
}

@Test func theDictationShortcutIsOptionShiftSpaceAndToggleBySurvivesARelaunchAndResetsWithDictation() throws {
    let (name, defaults) = dictationDefaults()
    let store = AppPreferences(defaults: defaults)
    #expect(AppPreferences.dictationShortcutKey == "dictation.shortcut" && AppPreferences.dictationActivationKey == "dictation.activation")
    #expect(store.dictationShortcut == .standard && store.dictationShortcut.text == "⌥⇧ Space" && store.dictationActivation == .toggle)
    guard case .accepted(let recorded) = recordShortcut(keyCode: 2, characters: "d", modifiers: [.control, .option]) else {
        Issue.record("refused")
        return
    }
    store.dictationShortcut = recorded
    store.dictationActivation = .hold
    let relaunched = AppPreferences(defaults: UserDefaults(suiteName: name)!)
    #expect(relaunched.dictationShortcut == recorded && relaunched.dictationShortcut.text == "⌃⌥ D" && relaunched.dictationActivation == .hold)
    store.reset(.notifications)
    #expect(store.dictationShortcut == recorded && store.dictationActivation == .hold)
    store.reset(.dictation)
    #expect(store.dictationShortcut == .standard && store.dictationActivation == .toggle)
    #expect(defaults.object(forKey: AppPreferences.dictationShortcutKey) == nil && defaults.object(forKey: AppPreferences.dictationActivationKey) == nil)
}

@Test func aSavedShortcutOrActivationThatMakesNoSenseReadsAsTheDefault() {
    let defaults = dictationDefaults().defaults
    let store = AppPreferences(defaults: defaults)
    defaults.set("0:49:Space", forKey: AppPreferences.dictationShortcutKey)
    defaults.set("press", forKey: AppPreferences.dictationActivationKey)
    #expect(store.dictationShortcut == .standard && store.dictationActivation == .toggle)
}

@Test func theWidgetIsMediumAtTheBottomUntilChosenOtherwiseAndResetsWithDictation() {
    let (name, defaults) = dictationDefaults()
    let store = AppPreferences(defaults: defaults)
    #expect(AppPreferences.dictationWidgetStyleKey == "dictation.widget.style" && AppPreferences.dictationWidgetPositionKey == "dictation.widget.position")
    #expect(store.dictationWidgetStyle == .medium && store.dictationWidgetPosition == .bottom)
    store.dictationWidgetStyle = .pill
    store.dictationWidgetPosition = .top
    let relaunched = AppPreferences(defaults: UserDefaults(suiteName: name)!)
    #expect(relaunched.dictationWidgetStyle == .pill && relaunched.dictationWidgetPosition == .top)
    store.reset(.notifications)
    #expect(store.dictationWidgetStyle == .pill && store.dictationWidgetPosition == .top)
    store.reset(.dictation)
    #expect(store.dictationWidgetStyle == .medium && store.dictationWidgetPosition == .bottom)
    #expect(defaults.object(forKey: AppPreferences.dictationWidgetStyleKey) == nil && defaults.object(forKey: AppPreferences.dictationWidgetPositionKey) == nil)
    defaults.set("huge", forKey: AppPreferences.dictationWidgetStyleKey)
    defaults.set("middle", forKey: AppPreferences.dictationWidgetPositionKey)
    #expect(store.dictationWidgetStyle == .medium && store.dictationWidgetPosition == .bottom)
}

@Test func theWidgetsThemeLiveTextAndSpotAreKeptAndPutBackByReset() {
    let defaults = UserDefaults(suiteName: "widget-look-\(UUID().uuidString)")!
    let store = AppPreferences(defaults: defaults)
    #expect(AppPreferences.dictationWidgetThemeKey == "dictation.widget.theme" && AppPreferences.dictationWidgetPreviewKey == "dictation.widget.preview")
    #expect(AppPreferences.dictationWidgetSpotKey == "dictation.widget.spot")
    #expect(store.dictationWidgetTheme == .accent && store.dictationWidgetPreview && store.dictationWidgetSpot == nil)
    let spot = DictationWidgetSpot(x: 0.3, fromTop: false, gap: 140)
    store.dictationWidgetTheme = .glow
    store.dictationWidgetPreview = false
    store.dictationWidgetSpot = spot
    let relaunched = AppPreferences(defaults: defaults)
    #expect(relaunched.dictationWidgetTheme == .glow && relaunched.dictationWidgetPreview == false && relaunched.dictationWidgetSpot == spot)
    store.dictationWidgetSpot = nil
    #expect(defaults.object(forKey: AppPreferences.dictationWidgetSpotKey) == nil)
    store.dictationWidgetSpot = spot
    store.reset(.dictation)
    #expect(store.dictationWidgetTheme == .accent && store.dictationWidgetPreview && store.dictationWidgetSpot == nil)
    defaults.set("neon", forKey: AppPreferences.dictationWidgetThemeKey)
    defaults.set("somewhere", forKey: AppPreferences.dictationWidgetSpotKey)
    #expect(store.dictationWidgetTheme == .accent && store.dictationWidgetSpot == nil)
}

// MARK: - The schema against the code it replaced

/// One key as the code had it before `design/preferences.json`: its name, what it read as with nothing saved, and the page whose Reset cleared it
/// (nil when no Reset did). The table below is copied from `AppPreferences.keys(of:)`, `terminalKeys` and the declarations of the other files.
private struct KeyRow {
    let name: String
    let page: SettingsPage?
    /// With nothing saved, the generated key has this name and reads as today's default.
    let readsAsToday: (UserDefaults) -> Bool
    /// A saved value that is not valid for the type reads as the default; nil for a key that has no such value.
    let readsBadAsDefault: ((UserDefaults) -> Bool)?
    /// An optional key reads as absent, takes a value and is removed by its accessor; nil for a key that is not optional.
    let behavesAsOptional: ((UserDefaults) -> Bool)?
}

private func row<V: PreferenceValue & Equatable>(_ key: PreferenceKey<V>, _ name: String, _ expected: V, _ page: SettingsPage?) -> KeyRow {
    let bad: Any = V.self == String.self ? ["not", "a", "string"] : "not valid"
    return KeyRow(
        name: name,
        page: page,
        readsAsToday: { defaults in key.name == name && key.defaultValue == expected && AppPreferences(defaults: defaults).value(key) == expected },
        readsBadAsDefault: { defaults in
            defaults.set(bad, forKey: name)
            return AppPreferences(defaults: defaults).value(key) == expected
        },
        behavesAsOptional: nil
    )
}

private func optionalRow<V: PreferenceValue & Equatable>(_ key: OptionalPreferenceKey<V>, _ name: String, _ page: SettingsPage?, sample: V) -> KeyRow {
    KeyRow(
        name: name,
        page: page,
        readsAsToday: { defaults in key.name == name && AppPreferences(defaults: defaults).value(key) == nil },
        readsBadAsDefault: nil,
        behavesAsOptional: { defaults in
            let store = AppPreferences(defaults: defaults)
            store.store(sample, for: key)
            let kept = store.value(key) == sample && defaults.object(forKey: name) != nil
            store.store(nil, for: key)
            return kept && store.value(key) == nil && defaults.object(forKey: name) == nil
        }
    )
}

private func mapRow<V>(_ key: PreferenceKey<[String: V]>, _ name: String, _ page: SettingsPage?) -> KeyRow {
    KeyRow(name: name, page: page, readsAsToday: { _ in key.name == name && key.defaultValue.isEmpty }, readsBadAsDefault: nil, behavesAsOptional: nil)
}

private let todaysKeys: [KeyRow] = [
    row(Preference.menuIconStyle, "menu.iconStyle", IconStyle(rawValue: "countAndBar")!, .general),
    row(Preference.menuAnimate, "menu.animate", true, .general),
    row(Preference.menuShowEpics, "menu.showEpics", true, .general),
    row(Preference.displayTimeStyle, "display.timeStyle", TimeStyle(rawValue: "relative")!, .general),
    row(Preference.displayClock, "display.clock", ClockHours(rawValue: "system")!, .general),
    row(Preference.stopConfirm, "stop.confirm", true, nil),
    row(Preference.appearanceColorScheme, "appearance.colorScheme", ColorSchemeChoice(rawValue: "system")!, .appearance),
    row(Preference.appearanceTextSize, "appearance.textSize", 100, .appearance),
    row(Preference.appearanceIconWeight, "appearance.iconWeight", 1.5, .appearance),
    row(Preference.appearanceIconSet, "appearance.iconSet", IconSet(rawValue: "tabler")!, .appearance),
    row(Preference.appearanceDensity, "appearance.density", Density(rawValue: "comfortable")!, .appearance),
    row(Preference.appearanceTheme, "appearance.theme", Theme(rawValue: "carrier")!, .appearance),
    optionalRow(Preference.appearanceAccent, "appearance.accent", .appearance, sample: "sample"),
    row(Preference.appearanceTint, "appearance.tint", Tint(rawValue: "off")!, .appearance),
    optionalRow(Preference.appearanceTranslucent, "appearance.translucent", .appearance, sample: true),
    row(Preference.appearanceStatesByShape, "appearance.statesByShape", false, .appearance),
    row(Preference.appearanceMonoFamily, "appearance.mono.family", "System", .appearance),
    row(Preference.appearanceMonoSize, "appearance.mono.size", 12, .appearance),
    row(Preference.appearanceMonoLineHeight, "appearance.mono.lineHeight", LineHeight(rawValue: "normal")!, .appearance),
    row(Preference.appearanceMonoLigatures, "appearance.mono.ligatures", true, .appearance),
    row(Preference.appearanceMonoWrap, "appearance.mono.wrap", true, .appearance),
    row(Preference.appearanceMonoLineNumbers, "appearance.mono.lineNumbers", false, .appearance),
    row(Preference.appearanceMessageWidth, "appearance.messageWidth", MessageWidth(rawValue: "medium")!, .chat),
    row(Preference.chatTextSize, "chat.textSize", 13, .chat),
    row(Preference.chatLineSpacing, "chat.lineSpacing", ChatLineSpacing(rawValue: "normal")!, .chat),
    row(Preference.chatMessageSpacing, "chat.messageSpacing", MessageSpacing(rawValue: "comfortable")!, .chat),
    row(Preference.chatSurface, "chat.surface", ChatSurface(rawValue: "glass")!, .chat),
    row(Preference.chatSendKey, "chat.sendKey", SendKey(rawValue: "return")!, .chat),
    row(Preference.chatWhileWorking, "chat.whileWorking", WhileWorking(rawValue: "queue")!, .chat),
    row(Preference.chatWritingTools, "chat.writingTools", false, .chat),
    row(Preference.chatCheckSpelling, "chat.checkSpelling", true, .chat),
    row(Preference.chatCorrectSpelling, "chat.correctSpelling", false, .chat),
    row(Preference.chatShowsContextUsage, "chat.showsContextUsage", true, .chat),
    row(Preference.chatFollowOutput, "chat.followOutput", true, .chat),
    row(Preference.chatMessageTimes, "chat.messageTimes", MessageTimes(rawValue: "hover")!, .chat),
    row(Preference.chatToolOutput, "chat.toolOutput", ToolOutputMode(rawValue: "collapsed")!, .chat),
    row(Preference.chatOpensFailedCalls, "chat.opensFailedCalls", true, .chat),
    row(Preference.chatDiffStyle, "chat.diffStyle", DiffStyle(rawValue: "unified")!, .chat),
    row(Preference.chatOutputLength, "chat.outputLength", 20, .chat),
    row(Preference.chatShowReasoning, "chat.showReasoning", true, .chat),
    row(Preference.chatConfirmDelete, "chat.confirmDelete", true, .sessions),
    row(Preference.chatNewSessionAgent, "chat.newSession.agent", "", .sessions),
    row(Preference.chatNewSessionModel, "chat.newSession.model", "", .sessions),
    row(Preference.chatNewSessionEffort, "chat.newSession.effort", "", .sessions),
    row(Preference.chatNewSessionAccess, "chat.newSession.access", "", .sessions),
    row(Preference.chatNewSessionWorkIn, "chat.newSession.workIn", WorkIn(rawValue: "baseFolder")!, .sessions),
    row(Preference.notifyNeedsYou, "notify.needsYou", true, .notifications),
    row(Preference.notifyReadyForTest, "notify.readyForTest", true, .notifications),
    row(Preference.notifyProblem, "notify.problem", false, .notifications),
    row(Preference.notifyChatNeedsAttention, "notify.chatNeedsAttention", true, .notifications),
    row(Preference.notifyChatDone, "notify.chatDone", false, .notifications),
    row(Preference.notifyOnlyWhenAway, "notify.onlyWhenAway", true, .notifications),
    row(Preference.notifyDockBadge, "notify.dockBadge", true, .notifications),
    row(Preference.notifySound, "notify.sound", true, .notifications),
    row(Preference.notifyReminder, "notify.reminder", 0, .notifications),
    row(Preference.notifyQuiet, "notify.quiet", false, .notifications),
    row(Preference.notifyQuietStart, "notify.quietStart", 1320, .notifications),
    row(Preference.notifyQuietEnd, "notify.quietEnd", 480, .notifications),
    row(Preference.dictationEnabled, "dictation.enabled", true, .dictation),
    row(Preference.dictationCleanupEnabled, "dictation.cleanup.enabled", false, .dictation),
    optionalRow(Preference.dictationCleanupServer, "dictation.cleanup.server", .dictation, sample: CleanupServer(rawValue: "ollama")!),
    optionalRow(Preference.dictationCleanupModel, "dictation.cleanup.model", .dictation, sample: "sample"),
    row(Preference.dictationCleanupPrompt, "dictation.cleanup.prompt", "Clean up this dictated text: remove filler words and false starts, fix the punctuation and capitalization, and keep the language that was spoken. Do not translate, add or explain anything. Reply with the cleaned text only.", .dictation),
    optionalRow(Preference.dictationModel, "dictation.model", .dictation, sample: "sample"),
    optionalRow(Preference.dictationLanguage, "dictation.language", .dictation, sample: "sample"),
    row(Preference.dictationModelKeepReady, "dictation.model.keepReady", true, .dictation),
    row(Preference.dictationModelReleaseAfter, "dictation.model.releaseAfter", 15, .dictation),
    row(Preference.dictationGlobal, "dictation.global", true, .dictation),
    row(Preference.dictationHistoryKeepText, "dictation.history.keepText", true, .dictation),
    row(Preference.dictationHistoryKeepAudio, "dictation.history.keepAudio", false, .dictation),
    row(Preference.dictationHistoryDeleteAudioAfter, "dictation.history.deleteAudioAfter", 30, .dictation),
    row(Preference.dictationStatisticsWpm, "dictation.statistics.wpm", 40, .dictation),
    row(Preference.dictationShortcut, "dictation.shortcut", "6:49:Space", .dictation),
    row(Preference.dictationActivation, "dictation.activation", DictationActivation(rawValue: "toggle")!, .dictation),
    row(Preference.dictationWidgetStyle, "dictation.widget.style", DictationWidgetStyle(rawValue: "medium")!, .dictation),
    row(Preference.dictationWidgetPosition, "dictation.widget.position", DictationWidgetPosition(rawValue: "bottom")!, .dictation),
    row(Preference.dictationWidgetTheme, "dictation.widget.theme", DictationWidgetTheme(rawValue: "accent")!, .dictation),
    row(Preference.dictationWidgetPreview, "dictation.widget.preview", true, .dictation),
    optionalRow(Preference.dictationWidgetSpot, "dictation.widget.spot", .dictation, sample: "sample"),
    row(Preference.dictationSoundStartOn, "dictation.sound.start.on", true, .dictation),
    row(Preference.dictationSoundStart, "dictation.sound.start", "Tink", .dictation),
    row(Preference.dictationSoundEndOn, "dictation.sound.end.on", true, .dictation),
    row(Preference.dictationSoundEnd, "dictation.sound.end", "Pop", .dictation),
    row(Preference.dictationSoundVolume, "dictation.sound.volume", 60, .dictation),
    row(Preference.dictationAccessibilityExplained, "dictation.accessibilityExplained", false, nil),
    mapRow(Preference.keybindings, "keybindings", .keybindings),
    row(Preference.awakeScreen, "awake.screen", false, .keepAwake),
    row(Preference.awakeMinutes, "awake.minutes", 60, .keepAwake),
    row(Preference.awakeAgents, "awake.agents", false, .keepAwake),
    row(Preference.awakeGrace, "awake.grace", 5, .keepAwake),
    row(Preference.awakeBattery, "awake.battery", BatteryRule(rawValue: "below20")!, .keepAwake),
    row(Preference.awakeNotify, "awake.notify", true, .keepAwake),
    optionalRow(Preference.awakeShortcut, "awake.shortcut", .keepAwake, sample: "sample"),
    row(Preference.updatesDelayDays, "updates.delayDays", 0, nil),
    row(Preference.engineStartOnOpen, "engine.startOnOpen", false, nil),
    row(Preference.engineCarrier, "engine.carrier", "", nil),
    mapRow(Preference.shellSetup, "shellSetup", nil),
    mapRow(Preference.carrierInstalledVersion, "carrier.installedVersion", nil),
    optionalRow(Preference.terminalTheme, "terminal.theme", .terminal, sample: Theme(rawValue: "graphite")!),
    optionalRow(Preference.terminalFontFamily, "terminal.font.family", .terminal, sample: "sample"),
    optionalRow(Preference.terminalFontSize, "terminal.font.size", .terminal, sample: 14),
    optionalRow(Preference.terminalFontLigatures, "terminal.font.ligatures", .terminal, sample: true),
    row(Preference.terminalFontThicken, "terminal.font.thicken", false, .terminal),
    row(Preference.terminalCursorStyle, "terminal.cursor.style", TerminalCursorStyleChoice(rawValue: "block")!, .terminal),
    row(Preference.terminalCursorBlink, "terminal.cursor.blink", true, .terminal),
    row(Preference.terminalPaddingX, "terminal.padding.x", 10, .terminal),
    row(Preference.terminalPaddingY, "terminal.padding.y", 8, .terminal),
    row(Preference.terminalMinimumContrast, "terminal.minimumContrast", 3, .terminal),
    row(Preference.terminalPanesDimInactive, "terminal.panes.dimInactive", false, .terminal),
    row(Preference.terminalPanesFocusFollowsMouse, "terminal.panes.focusFollowsMouse", false, .terminal),
    row(Preference.terminalInputOptionAsAlt, "terminal.input.optionAsAlt", TerminalOptionAsAlt(rawValue: "false")!, .terminal),
    row(Preference.terminalInputCopyOnSelect, "terminal.input.copyOnSelect", false, .terminal),
    row(Preference.terminalScrollbackLimit, "terminal.scrollback.limit", 10000000, .terminal),
    row(Preference.terminalConfirmCloseRunningProcess, "terminal.confirmCloseRunningProcess", true, .terminal),
    row(Preference.terminalPinPromptToBottom, "terminal.pinPromptToBottom", false, .terminal),
    row(Preference.terminalDrawerHeight, "terminal.drawerHeight", 260, .terminal),
    row(Preference.sidebarGroupBy, "sidebar.groupBy", GroupBy(rawValue: "status")!, .sidebar),
    row(Preference.sidebarSessionSort, "sidebar.sessionSort", SessionSort(rawValue: "workspace")!, .sidebar),
    row(Preference.sidebarArchiveSort, "sidebar.archiveSort", ArchiveSort(rawValue: "dateArchived")!, .sidebar),
    row(Preference.sidebarArchiveListSort, "sidebar.archiveListSort", SessionSort(rawValue: "age")!, .sidebar),
    row(Preference.sidebarPinned, "sidebar.pinned", "", nil),
    row(Preference.sidebarRowIcon, "sidebar.row.icon", true, .sidebar),
    row(Preference.sidebarRowBranch, "sidebar.row.branch", true, .sidebar),
    row(Preference.sidebarRowProviders, "sidebar.row.providers", true, .sidebar),
    row(Preference.sidebarRowAge, "sidebar.row.age", true, .sidebar),
    row(Preference.sidebarRowPullRequest, "sidebar.row.pullRequest", true, .sidebar),
    row(Preference.sidebarRowDiff, "sidebar.row.diff", true, .sidebar),
    row(Preference.sidebarOpen, "sidebar.open", "sessions", nil),
    optionalRow(Preference.sidebarSlotsTotal, "sidebar.slotsTotal", nil, sample: 3),
    row(Preference.sidebarWidth, "sidebar.width", 360, .sidebar),
    mapRow(Preference.sessionsSeen, "sessions.seen", nil),
    optionalRow(Preference.inspectorTab, "inspector.tab", nil, sample: InspectorTab(rawValue: "review")!),
]

private func scratchDefaults() -> UserDefaults { UserDefaults(suiteName: "preferences-\(UUID().uuidString)")! }

@Test func everyKeyHasTheNameAndTheDefaultItHadBeforeTheSchema() {
    #expect(todaysKeys.count == Set(todaysKeys.map(\.name)).count)
    for key in todaysKeys { #expect(key.readsAsToday(scratchDefaults()), "\(key.name)") }
}

@Test func theCleanupSwitchIsOffInTheSchemaAndTheDefaultPromptIsTheOneTheAppHad() {
    #expect(Preference.dictationCleanupEnabled.defaultValue == false)
    #expect(AppPreferences(defaults: scratchDefaults()).value(Preference.dictationCleanupPrompt) == defaultCleanupPrompt)
}

@Test func aStoredValueIsReadBackThroughTheGeneratedKeys() {
    let name = "preferences-\(UUID().uuidString)"
    let store = AppPreferences(defaults: UserDefaults(suiteName: name)!)
    store.store(false, for: Preference.menuAnimate)
    store.store(130, for: Preference.appearanceTextSize)
    store.store(14.5, for: Preference.appearanceMonoSize)
    store.store(Theme(rawValue: "ocean")!, for: Preference.appearanceTheme)
    store.store("Menlo", for: Preference.appearanceMonoFamily)
    let relaunched = AppPreferences(defaults: UserDefaults(suiteName: name)!)
    #expect(relaunched.value(Preference.menuAnimate) == false)
    #expect(relaunched.value(Preference.appearanceTextSize) == 130)
    #expect(relaunched.value(Preference.appearanceMonoSize) == 14.5)
    #expect(relaunched.value(Preference.appearanceTheme) == Theme(rawValue: "ocean"))
    #expect(relaunched.value(Preference.appearanceMonoFamily) == "Menlo")
}

@Test func aStoredValueThatIsNotValidReadsAsTheDefault() {
    for key in todaysKeys {
        guard let readsBad = key.readsBadAsDefault else { continue }
        #expect(readsBad(scratchDefaults()), "\(key.name)")
    }
    let defaults = scratchDefaults()
    defaults.set("a lot", forKey: Preference.chatOutputLength.name)
    defaults.set("sparkles", forKey: Preference.menuIconStyle.name)
    #expect(AppPreferences(defaults: defaults).value(Preference.chatOutputLength) == 20)
    #expect(AppPreferences(defaults: defaults).value(Preference.menuIconStyle) == .countAndBar)
}

@Test func anOptionalPreferenceIsAbsentUntilSetAndRemovedByItsAccessor() {
    let optionals = todaysKeys.compactMap(\.behavesAsOptional)
    #expect(optionals.count == 14)
    for behaves in optionals { #expect(behaves(scratchDefaults())) }
    let store = AppPreferences(defaults: scratchDefaults())
    #expect(store.value(Preference.terminalFontSize) == nil)
    store.store(15.5, for: Preference.terminalFontSize)
    #expect(store.value(Preference.terminalFontSize) == 15.5)
    store.store(nil, for: Preference.terminalFontSize)
    #expect(store.value(Preference.terminalFontSize) == nil)
}

@Test func resetOfAPageClearsExactlyTheKeysItClearedBeforeAndNoKeyOfAnotherPage() {
    for page in SettingsPage.allCases {
        let defaults = scratchDefaults()
        for key in todaysKeys { defaults.set("saved", forKey: key.name) }
        AppPreferences(defaults: defaults).reset(page)
        for key in todaysKeys {
            let cleared = defaults.object(forKey: key.name) == nil
            #expect(cleared == (key.page == page), "\(key.name) on \(page)")
        }
    }
}

@Test func resettingTheTerminalTakesOutTheTerminalKeysOnly() {
    let defaults = scratchDefaults()
    for key in todaysKeys { defaults.set("saved", forKey: key.name) }
    AppPreferences(defaults: defaults).resetTerminal()
    for key in todaysKeys { #expect((defaults.object(forKey: key.name) == nil) == (key.page == .terminal), "\(key.name)") }
}
