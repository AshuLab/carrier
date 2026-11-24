import CarrierCore
import Foundation
import IOKit.pwr_mgt
import Testing
@testable import Carrier

/// What the system itself says this process holds, by the name the controller gives its assertions: a hold that was never let go shows here
/// even when the controller believes it let go.
private func assertionsHeldBySystem() -> [String] {
    var byProcess: Unmanaged<CFDictionary>?
    guard IOPMCopyAssertionsByProcess(&byProcess) == kIOReturnSuccess, let all = byProcess?.takeRetainedValue() as? [Int: [[String: Any]]] else { return [] }
    return (all[Int(getpid())] ?? []).compactMap { $0[kIOPMAssertionTypeKey as String] as? String }
        .filter { $0 == kIOPMAssertPreventUserIdleSystemSleep as String || $0 == kIOPMAssertPreventUserIdleDisplaySleep as String }
}

/// A controller of its own: its own preferences, a clock and a battery the test moves, and a notification that is written down. The assertions
/// are the system's real ones, so each test lets go of them before it ends (`finish`).
@MainActor private final class Rig {
    let controller: KeepAwakeController
    let defaults: UserDefaults
    private let suite = "keepawake-controller-\(UUID().uuidString)"
    var clock = Date()
    var power = PowerFacts(onBattery: false, percent: 90)
    var notices: [String] = []
    var changes: [Bool] = []

    init(agents: Bool = false, grace: Int = 5, screen: Bool = false, shortcut: DictationShortcut? = nil) {
        defaults = UserDefaults(suiteName: suite)!
        AppPreferences(defaults: defaults).awakeShortcut = shortcut
        defaults.set(agents, forKey: AppPreferences.awakeAgentsKey)
        defaults.set(grace, forKey: AppPreferences.awakeGraceKey)
        defaults.set(screen, forKey: AppPreferences.awakeScreenKey)
        controller = KeepAwakeController(defaults: defaults)
        controller.now = { [unowned self] in clock }
        controller.readPower = { [unowned self] in power }
        controller.notify = { [unowned self] title, _ in notices.append(title) }
        controller.onChange = { [unowned self] in changes.append($0.holds) }
        controller.settingsChanged()
    }

    func advance(minutes: Double) {
        clock = clock.addingTimeInterval(minutes * 60)
        controller.refresh()
    }

    func plug(_ facts: PowerFacts) {
        power = facts
        controller.powerChanged()
    }

    /// Lets go of what the test took.
    func finish() {
        defaults.set(false, forKey: AppPreferences.awakeAgentsKey)
        controller.settingsChanged()
        controller.stopManual()
        controller.epics(working: 0)
        controller.sessions(working: 0)
        defaults.removePersistentDomain(forName: suite)
    }
}

@Test @MainActor func aKeepAwakeByHandHoldsTheMacAndStoppingItLetsGoWithoutANotice() {
    let rig = Rig()
    defer { rig.finish() }
    #expect(rig.controller.holdsSystem == false)
    rig.controller.start(minutes: 30)
    #expect(rig.controller.decision.holds)
    #expect(rig.controller.holdsSystem)
    #expect(rig.controller.holdsDisplay == false)
    #expect(rig.controller.manualMinutes == 30)
    #expect(assertionsHeldBySystem() == [kIOPMAssertPreventUserIdleSystemSleep as String])
    rig.controller.stopManual()
    #expect(rig.controller.holdsSystem == false)
    #expect(assertionsHeldBySystem().isEmpty)
    #expect(rig.changes == [true, false])
    #expect(rig.notices.isEmpty)
}

@Test @MainActor func theToggleStartsTheDefaultLengthAndThenStopsWhatWasStarted() {
    let rig = Rig()
    defer { rig.finish() }
    rig.controller.toggle()
    #expect(rig.controller.decision.isManual)
    #expect(rig.controller.manualMinutes == AwakeLength.defaultMinutes)
    rig.controller.toggle()
    #expect(rig.controller.decision.holds == false)
}

@Test @MainActor func aLengthThatRunsOutLetsGoAndSaysSo() {
    let rig = Rig()
    defer { rig.finish() }
    rig.controller.start(minutes: 30)
    rig.advance(minutes: 29)
    #expect(rig.controller.holdsSystem)
    #expect(rig.notices.isEmpty)
    rig.advance(minutes: 2)
    #expect(rig.controller.holdsSystem == false)
    #expect(assertionsHeldBySystem().isEmpty)
    #expect(rig.controller.manual == nil)
    #expect(rig.notices == ["Keep awake ended"])
}

@Test @MainActor func noEndMeansNoEndUntilTheyStopIt() {
    let rig = Rig()
    defer { rig.finish() }
    rig.controller.start(minutes: 0)
    rig.advance(minutes: 24 * 60)
    #expect(rig.controller.holdsSystem)
    #expect(rig.notices.isEmpty)
}

@Test @MainActor func theScreenIsHeldOnlyWhenAsked() {
    let rig = Rig(screen: true)
    defer { rig.finish() }
    rig.controller.start(minutes: 30)
    #expect(rig.controller.holdsSystem && rig.controller.holdsDisplay)
    #expect(Set(assertionsHeldBySystem()) == [kIOPMAssertPreventUserIdleSystemSleep as String, kIOPMAssertPreventUserIdleDisplaySleep as String])
    rig.defaults.set(false, forKey: AppPreferences.awakeScreenKey)
    rig.controller.settingsChanged()
    #expect(rig.controller.holdsSystem)
    #expect(rig.controller.holdsDisplay == false)
    #expect(assertionsHeldBySystem() == [kIOPMAssertPreventUserIdleSystemSleep as String])
}

@Test @MainActor func agentsHoldTheMacOnlyWithTheSwitchOnAndForTheGraceAfter() {
    let rig = Rig(agents: false)
    defer { rig.finish() }
    rig.controller.epics(working: 2)
    #expect(rig.controller.holdsSystem == false)
    rig.controller.setFollowsAgents(true)
    #expect(rig.controller.decision.reason == .agents)
    #expect(rig.controller.holdsSystem)
    // the epics end: the grace holds for five minutes more
    rig.controller.epics(working: 0)
    #expect(rig.controller.holdsSystem)
    rig.advance(minutes: 4)
    #expect(rig.controller.holdsSystem)
    rig.advance(minutes: 2)
    #expect(rig.controller.holdsSystem == false)
    // the ordinary end after agents says nothing
    #expect(rig.notices.isEmpty)
}

@Test @MainActor func aWorkingChatSessionAloneKeepsTheMacAwakeAndAHostThatGoesAwayDoesNot() {
    let rig = Rig(agents: true, grace: 0)
    defer { rig.finish() }
    rig.controller.sessions(working: 1)
    #expect(rig.controller.decision.reason == .agents)
    rig.controller.epics(working: 1)
    rig.controller.sessions(working: 0)
    #expect(rig.controller.holdsSystem)
    rig.controller.epics(working: 0)
    #expect(rig.controller.holdsSystem == false)
}

@Test @MainActor func turningTheAgentsSwitchOffWhileTheyWorkLetsGoAndSaysNothing() {
    let rig = Rig(agents: true)
    defer { rig.finish() }
    rig.controller.epics(working: 1)
    #expect(rig.controller.holdsSystem)
    rig.controller.setFollowsAgents(false)
    #expect(rig.controller.holdsSystem == false)
    #expect(rig.notices.isEmpty)
}

@Test @MainActor func aKeepAwakeByHandWinsAndTheAgentsTakeOverWhenItEnds() {
    let rig = Rig(agents: true)
    defer { rig.finish() }
    rig.controller.epics(working: 1)
    rig.controller.start(minutes: 30)
    #expect(rig.controller.decision.isManual)
    rig.controller.stopManual()
    #expect(rig.controller.decision.reason == .agents)
    #expect(rig.controller.holdsSystem)
}

@Test @MainActor func aLowBatteryPausesAndTellsAndPluggingInGoesOnByItself() {
    let rig = Rig()
    defer { rig.finish() }
    rig.controller.start(minutes: 0)
    #expect(rig.controller.holdsSystem)
    rig.plug(PowerFacts(onBattery: true, percent: 15))
    #expect(rig.controller.holdsSystem == false)
    #expect(assertionsHeldBySystem().isEmpty)
    #expect(rig.controller.decision.blocked == .batteryLow(15))
    #expect(rig.notices == ["Keep awake paused"])
    // still asked for: the toggle still says Stop, and the page says Paused
    #expect(rig.controller.decision.isManual)
    rig.plug(PowerFacts(onBattery: false, percent: 15))
    #expect(rig.controller.holdsSystem)
    #expect(assertionsHeldBySystem().count == 1)
}

@Test @MainActor func startingOnALowBatteryHoldsNothingAndSaysItIsWaiting() {
    let rig = Rig()
    defer { rig.finish() }
    rig.defaults.set(false, forKey: AppPreferences.awakeNotifyKey)
    rig.controller.settingsChanged()
    rig.power = PowerFacts(onBattery: true, percent: 10)
    rig.controller.powerChanged()
    rig.controller.start(minutes: 60)
    #expect(rig.controller.holdsSystem == false)
    #expect(rig.controller.decision.blocked == .batteryLow(10))
    // the person just asked and the menu closed on nothing: it is told, even with the notices switch off
    #expect(rig.notices == ["Keep awake is waiting"])
    rig.plug(PowerFacts(onBattery: false, percent: 10))
    #expect(rig.controller.holdsSystem)
}

@Test @MainActor func theNoticeIsLeftOutWhenTheSwitchIsOff() {
    let rig = Rig()
    defer { rig.finish() }
    rig.defaults.set(false, forKey: AppPreferences.awakeNotifyKey)
    rig.controller.settingsChanged()
    rig.controller.start(minutes: 30)
    rig.advance(minutes: 31)
    #expect(rig.controller.holdsSystem == false)
    #expect(rig.notices.isEmpty)
}

/// ⌃⌥⇧⌘ Y: a combination nothing else registers.
private func oddShortcut() -> DictationShortcut? {
    guard case .accepted(let shortcut) = recordShortcut(keyCode: 16, characters: "y", modifiers: [.control, .option, .shift, .command]) else { return nil }
    return shortcut
}

@Test @MainActor func aShortcutTheSystemRefusesIsNotShownAsActiveAndIsTriedAgainOnceItIsFree() throws {
    let shortcut = try #require(oddShortcut())
    let first = Rig(shortcut: shortcut)
    let second = Rig(shortcut: shortcut)
    defer {
        first.finish()
        second.finish()
    }
    #expect(first.controller.shortcutProblem == nil)
    // the same keys in the same process: the second is refused, and says so
    #expect(second.controller.shortcutProblem?.contains(shortcut.text) == true)
    // the first lets go (it records other keys), and the second takes them when it is asked again
    first.controller.recordingShortcut = true
    second.controller.recordingShortcut = true
    second.controller.recordingShortcut = false
    #expect(second.controller.shortcutProblem == nil)
    // and now the first is the refused one
    first.controller.recordingShortcut = false
    #expect(first.controller.shortcutProblem?.contains(shortcut.text) == true)
}

private func otherShortcut() -> DictationShortcut? {
    guard case .accepted(let shortcut) = recordShortcut(keyCode: 17, characters: "t", modifiers: [.control, .option, .shift, .command]) else { return nil }
    return shortcut
}

@Test @MainActor func noShortcutIsNoProblemAndOnlyARegisteredOneIsTheActiveOne() throws {
    let shortcut = try #require(oddShortcut())
    let rig = Rig()
    defer { rig.finish() }
    #expect(rig.controller.shortcutProblem == nil)
    #expect(rig.controller.registeredShortcut == nil)
    AppPreferences(defaults: rig.defaults).awakeShortcut = shortcut
    rig.controller.settingsChanged()
    #expect(rig.controller.registeredShortcut == shortcut)
    #expect(rig.controller.shortcutProblem == nil)
}

@Test @MainActor func aRefusedShortcutIsNotActiveAndClearingItLeavesNoProblemBehind() throws {
    let shortcut = try #require(oddShortcut())
    let first = Rig(shortcut: shortcut)
    let second = Rig(shortcut: shortcut)
    defer {
        first.finish()
        second.finish()
    }
    #expect(second.controller.shortcutProblem != nil)
    // refused: the menu and the page must not show it as the active one
    #expect(second.controller.registeredShortcut == nil)
    // Clear (or Reset) takes the shortcut away: nothing is left to complain about
    AppPreferences(defaults: second.defaults).awakeShortcut = nil
    second.controller.settingsChanged()
    #expect(second.controller.shortcutProblem == nil)
    // and the keys refused before are not remembered against a new one
    let other = try #require(otherShortcut())
    AppPreferences(defaults: second.defaults).awakeShortcut = other
    second.controller.settingsChanged()
    #expect(second.controller.shortcutProblem == nil)
    #expect(second.controller.registeredShortcut == other)
}

@Test @MainActor func aRefusalSurvivesNoOtherChangeAndRecordingOtherKeysReplacesIt() throws {
    let shortcut = try #require(oddShortcut())
    let other = try #require(otherShortcut())
    let first = Rig(shortcut: shortcut)
    let second = Rig(shortcut: shortcut)
    defer {
        first.finish()
        second.finish()
    }
    #expect(second.controller.shortcutProblem != nil)
    // an unrelated change of settings does not try again and again
    second.controller.settingsChanged()
    #expect(second.controller.shortcutProblem != nil)
    // recording starts: the page stops showing a problem of keys that are being replaced
    second.controller.recordingShortcut = true
    AppPreferences(defaults: second.defaults).awakeShortcut = other
    second.controller.recordingShortcut = false
    #expect(second.controller.registeredShortcut == other)
    #expect(second.controller.shortcutProblem == nil)
}
