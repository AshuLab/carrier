import Foundation
import Testing

@testable import CarrierCore

private let now = Date(timeIntervalSince1970: 1_000_000)
private let plugged = PowerFacts(onBattery: false, percent: 80)

private func decide(
    manual: AwakeManual? = nil, follows: Bool = false, grace: Int = 5, battery: BatteryRule = .below20, working: Bool = false,
    last: Date? = nil, power: PowerFacts = plugged
) -> AwakeDecision {
    var settings = AwakeSettings()
    settings.followsAgents = follows
    settings.graceMinutes = grace
    settings.battery = battery
    return awakeDecision(now: now, manual: manual, settings: settings, agentsWorking: working, lastWorked: last, power: power)
}

@Test func nothingAskedHoldsNothing() {
    #expect(decide() == AwakeDecision())
    #expect(decide(follows: true, working: false).holds == false)
}

@Test func aManualKeepAwakeHoldsUntilItsEnd() {
    let end = now.addingTimeInterval(600)
    #expect(decide(manual: .until(end)).reason == .manual(until: end))
    #expect(decide(manual: .until(now)).holds == false)
    #expect(decide(manual: .until(now.addingTimeInterval(-1))).holds == false)
    #expect(decide(manual: .indefinite).reason == .manual(until: nil))
}

@Test func agentsCountOnlyWithTheSwitchOn() {
    #expect(decide(follows: false, working: true).holds == false)
    #expect(decide(follows: true, working: true).reason == .agents)
}

@Test func theGraceRunsFromTheLastWorkAndThenEnds() {
    let last = now.addingTimeInterval(-120)
    #expect(decide(follows: true, last: last).reason == .grace(until: last.addingTimeInterval(300)))
    #expect(decide(follows: true, last: now.addingTimeInterval(-300)).holds == false)
    #expect(decide(follows: true, grace: 0, last: last).holds == false)
    #expect(decide(follows: false, last: last).holds == false)
}

@Test func aManualKeepAwakeWinsOverTheAgents() {
    #expect(decide(manual: .indefinite, follows: true, working: true).reason == .manual(until: nil))
}

@Test func theBatteryRuleBlocksOnlyOnBattery() {
    let low = PowerFacts(onBattery: true, percent: 15)
    #expect(decide(manual: .indefinite, power: low).blocked == .batteryLow(15))
    #expect(decide(manual: .indefinite, power: low).holds == false)
    #expect(decide(manual: .indefinite, power: PowerFacts(onBattery: true, percent: 20)).holds)
    #expect(decide(manual: .indefinite, battery: .below10, power: low).holds)
    #expect(decide(manual: .indefinite, battery: .never, power: low).holds)
    #expect(decide(manual: .indefinite, battery: .pluggedIn, power: PowerFacts(onBattery: true, percent: 90)).blocked == .unplugged)
    #expect(decide(manual: .indefinite, battery: .pluggedIn, power: plugged).holds)
    // a Mac with no battery reports no level and is never on battery
    #expect(decide(manual: .indefinite, power: PowerFacts(onBattery: false, percent: nil)).holds)
    // on battery and the level unknown: nothing to compare, it holds
    #expect(decide(manual: .indefinite, power: PowerFacts(onBattery: true, percent: nil)).holds)
}

@Test func nothingAskedIsNeverBlocked() {
    #expect(decide(power: PowerFacts(onBattery: true, percent: 1)).blocked == nil)
}

@Test func theNextChangeIsTheEndOfTheManualOrOfTheGrace() {
    let end = now.addingTimeInterval(600)
    #expect(nextAwakeChange(decide(manual: .until(end))) == end)
    #expect(nextAwakeChange(decide(manual: .indefinite)) == nil)
    #expect(nextAwakeChange(decide(follows: true, working: true)) == nil)
    let last = now.addingTimeInterval(-60)
    #expect(nextAwakeChange(decide(follows: true, last: last)) == last.addingTimeInterval(300))
    #expect(nextAwakeChange(decide()) == nil)
}

@Test func timeLeftIsRoundedUp() {
    #expect(awakeRemaining(0) == "under 1 min")
    #expect(awakeRemaining(1) == "1 min")
    #expect(awakeRemaining(61) == "2 min")
    #expect(awakeRemaining(59 * 60) == "59 min")
    #expect(awakeRemaining(3600) == "1 h")
    #expect(awakeRemaining(3600 + 12 * 60) == "1 h 12 min")
    #expect(awakeRemaining(5 * 3600 - 10) == "5 h")
    #expect(awakeRemaining(-5) == "under 1 min")
}

@Test func theStatusLineSaysWhatIsHappeningAndWhatEndsIt() {
    var settings = AwakeSettings()
    func line(_ decision: AwakeDecision) -> String { awakeStatus(decision, settings: settings, now: now) }
    #expect(line(AwakeDecision()) == "Off")
    settings.followsAgents = true
    #expect(line(AwakeDecision()) == "Off · wakes up when agents work")
    #expect(line(AwakeDecision(reason: .manual(until: now.addingTimeInterval(4320)))) == "Awake · 1 h 12 min left")
    #expect(line(AwakeDecision(reason: .manual(until: nil))) == "Awake until you turn it off")
    #expect(line(AwakeDecision(reason: .agents)) == "Awake while agents work")
    #expect(line(AwakeDecision(reason: .grace(until: now.addingTimeInterval(240)))) == "Awake · 4 min after agents finished")
    #expect(line(AwakeDecision(reason: .agents, blocked: .batteryLow(18))) == "Paused: battery at 18 %")
    #expect(line(AwakeDecision(reason: .agents, blocked: .unplugged)) == "Paused: on battery")
}

@Test func theToggleSaysWhatAClickDoes() {
    #expect(awakeToggleTitle(manualActive: true, defaultMinutes: 60) == "Stop keeping awake")
    #expect(awakeToggleTitle(manualActive: false, defaultMinutes: 60) == "Keep awake for 1 hour")
    #expect(awakeToggleTitle(manualActive: false, defaultMinutes: 30) == "Keep awake for 30 min")
    #expect(awakeToggleTitle(manualActive: false, defaultMinutes: 300) == "Keep awake for 5 hours")
    #expect(awakeToggleTitle(manualActive: false, defaultMinutes: 0) == "Keep awake")
    // a saved length that is not a choice reads as the default
    #expect(awakeToggleTitle(manualActive: false, defaultMinutes: 7) == "Keep awake for 1 hour")
}

@Test func theEndNoticeNamesTheBatteryWhenItWasTheCause() {
    #expect(awakeEndedNotice(nil).title == "Keep awake ended")
    #expect(awakeEndedNotice(.batteryLow(9)).body.contains("9 %"))
    #expect(awakeEndedNotice(.unplugged).title == "Keep awake paused")
}

@Test func theSettingsReadTheirDefaultsAndRefuseBadValues() throws {
    let suite = "keepawake-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = AppPreferences(defaults: defaults)
    #expect(preferences.awake == AwakeSettings())
    #expect(preferences.awakeShortcut == nil)
    defaults.set(7, forKey: AppPreferences.awakeMinutesKey)
    defaults.set(11, forKey: AppPreferences.awakeGraceKey)
    defaults.set("nonsense", forKey: AppPreferences.awakeBatteryKey)
    defaults.set(true, forKey: AppPreferences.awakeScreenKey)
    let read = preferences.awake
    #expect(read.defaultMinutes == AwakeLength.defaultMinutes)
    #expect(read.graceMinutes == AwakeSettings().graceMinutes)
    #expect(read.battery == .standard)
    #expect(read.keepsScreenOn)
    preferences.reset(.keepAwake)
    #expect(preferences.awake == AwakeSettings())
}

@Test func aShortcutIsKeptAndCleared() throws {
    let suite = "keepawake-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = AppPreferences(defaults: defaults)
    guard case .accepted(let shortcut) = recordShortcut(keyCode: 0, characters: "a", modifiers: [.control, .option, .command]) else {
        Issue.record("the recorder refused ⌃⌥⌘ A")
        return
    }
    preferences.awakeShortcut = shortcut
    #expect(preferences.awakeShortcut == shortcut)
    preferences.awakeShortcut = nil
    #expect(preferences.awakeShortcut == nil)
}

@Test func theIconShowsTheCupOnlyWhileAwake() {
    var state = IconState(connected: true, working: 1)
    #expect(state.parts.cup == false)
    state.awake = true
    #expect(state.parts.cup)
    var stopped = IconState(); stopped.awake = true; #expect(stopped.parts.cup)
}
