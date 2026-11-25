import CarrierCore
import Foundation
import Testing
@testable import Carrier

/// The assertions the controller holds, written down; the system's real ones are tried by `SystemKeepAwakeAssertionTests`.
@MainActor private final class FakeAssertion: KeepAwakeAssertion {
    var held: Set<AwakeAssertionKind> = []
    var power = PowerFacts(onBattery: false, percent: 90)

    func isHeld(_ kind: AwakeAssertionKind) -> Bool { held.contains(kind) }
    func take(_ kind: AwakeAssertionKind) -> Bool {
        held.insert(kind)
        return true
    }
    func release(_ kind: AwakeAssertionKind) { held.remove(kind) }
    func powerFacts() -> PowerFacts { power }
    func watchPower(_ changed: @escaping @MainActor () -> Void) {}
}

/// The keys the controllers of a test hold. As the system does, it refuses keys that are already registered, and frees them when the registration goes.
private final class HeldKeys {
    var taken: [DictationShortcut] = []
}

private final class Registration {
    let keys: DictationShortcut
    let board: HeldKeys

    init(_ keys: DictationShortcut, _ board: HeldKeys) {
        self.keys = keys
        self.board = board
        board.taken.append(keys)
    }

    deinit { board.taken.removeAll { $0 == keys } }
}

@MainActor private struct FakeShortcuts: GlobalShortcut {
    let board: HeldKeys

    func register(_ shortcut: DictationShortcut, pressed: @escaping () -> Void, released: @escaping () -> Void) -> AnyObject? {
        board.taken.contains(shortcut) ? nil : Registration(shortcut, board)
    }
}

private struct NullCentre: NotificationCentre {
    func post(_ notifications: [EpicNotification]) {}
    func sendTest() {}
}

/// A controller of its own: its own preferences, a clock and a battery the test moves, and a notification that is written down. Each test lets go
/// of what it took (`finish`).
@MainActor private final class Rig {
    let controller: KeepAwakeController
    let defaults: UserDefaults
    let assertion = FakeAssertion()
    private let suite = "keepawake-controller-\(UUID().uuidString)"
    var clock = Date()
    var power: PowerFacts {
        get { assertion.power }
        set { assertion.power = newValue }
    }
    var notices: [String] = []
    var changes: [Bool] = []

    init(agents: Bool = false, grace: Int = 5, screen: Bool = false, shortcut: DictationShortcut? = nil, keys: HeldKeys = HeldKeys()) {
        defaults = UserDefaults(suiteName: suite)!
        AppPreferences(defaults: defaults).awakeShortcut = shortcut
        defaults.set(agents, forKey: AppPreferences.awakeAgentsKey)
        defaults.set(grace, forKey: AppPreferences.awakeGraceKey)
        defaults.set(screen, forKey: AppPreferences.awakeScreenKey)
        controller = KeepAwakeController(defaults: defaults, assertion: assertion, shortcuts: FakeShortcuts(board: keys), centre: NullCentre())
        controller.now = { [unowned self] in clock }
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
    #expect(rig.assertion.held == [.system])
    rig.controller.stopManual()
    #expect(rig.controller.holdsSystem == false)
    #expect(rig.assertion.held.isEmpty)
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
    #expect(rig.assertion.held.isEmpty)
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
    #expect(rig.assertion.held == [.system, .display])
    rig.defaults.set(false, forKey: AppPreferences.awakeScreenKey)
    rig.controller.settingsChanged()
    #expect(rig.controller.holdsSystem)
    #expect(rig.controller.holdsDisplay == false)
    #expect(rig.assertion.held == [.system])
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
    #expect(rig.assertion.held.isEmpty)
    #expect(rig.controller.decision.blocked == .batteryLow(15))
    #expect(rig.notices == ["Keep awake paused"])
    // still asked for: the toggle still says Stop, and the page says Paused
    #expect(rig.controller.decision.isManual)
    rig.plug(PowerFacts(onBattery: false, percent: 15))
    #expect(rig.controller.holdsSystem)
    #expect(rig.assertion.held.count == 1)
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
    let keys = HeldKeys()
    let first = Rig(shortcut: shortcut, keys: keys)
    let second = Rig(shortcut: shortcut, keys: keys)
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
    let keys = HeldKeys()
    let first = Rig(shortcut: shortcut, keys: keys)
    let second = Rig(shortcut: shortcut, keys: keys)
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
    let keys = HeldKeys()
    let first = Rig(shortcut: shortcut, keys: keys)
    let second = Rig(shortcut: shortcut, keys: keys)
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
