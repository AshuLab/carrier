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
    #expect(awakeRemaining(0, bundle: english.bundle, locale: english.locale) == "under 1 min")
    #expect(awakeRemaining(1, bundle: english.bundle, locale: english.locale) == "1 min")
    #expect(awakeRemaining(61, bundle: english.bundle, locale: english.locale) == "2 min")
    #expect(awakeRemaining(59 * 60, bundle: english.bundle, locale: english.locale) == "59 min")
    #expect(awakeRemaining(3600, bundle: english.bundle, locale: english.locale) == "1 h")
    #expect(awakeRemaining(3600 + 12 * 60, bundle: english.bundle, locale: english.locale) == "1 h 12 min")
    #expect(awakeRemaining(5 * 3600 - 10, bundle: english.bundle, locale: english.locale) == "5 h")
    #expect(awakeRemaining(-5, bundle: english.bundle, locale: english.locale) == "under 1 min")
}

@Test func theStatusLineSaysWhatIsHappeningAndWhatEndsIt() {
    var settings = AwakeSettings()
    func line(_ decision: AwakeDecision) -> String { awakeStatus(decision, settings: settings, now: now, bundle: english.bundle, locale: english.locale) }
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
    #expect(awakeToggleTitle(manualActive: true, defaultMinutes: 60, bundle: english.bundle, locale: english.locale) == "Stop keeping awake")
    #expect(awakeToggleTitle(manualActive: false, defaultMinutes: 60, bundle: english.bundle, locale: english.locale) == "Keep awake for 1 hour")
    #expect(awakeToggleTitle(manualActive: false, defaultMinutes: 30, bundle: english.bundle, locale: english.locale) == "Keep awake for 30 min")
    #expect(awakeToggleTitle(manualActive: false, defaultMinutes: 300, bundle: english.bundle, locale: english.locale) == "Keep awake for 5 hours")
    #expect(awakeToggleTitle(manualActive: false, defaultMinutes: 0, bundle: english.bundle, locale: english.locale) == "Keep awake")
    // a saved length that is not a choice reads as the default
    #expect(awakeToggleTitle(manualActive: false, defaultMinutes: 7, bundle: english.bundle, locale: english.locale) == "Keep awake for 1 hour")
}

@Test func theEndNoticeNamesTheBatteryWhenItWasTheCause() {
    #expect(awakeEndedNotice(nil, bundle: english.bundle, locale: english.locale).title == "Keep awake ended")
    #expect(awakeEndedNotice(.batteryLow(9), bundle: english.bundle, locale: english.locale).body.contains("9 %"))
    #expect(awakeEndedNotice(.unplugged, bundle: english.bundle, locale: english.locale).title == "Keep awake paused")
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

@Test func theMenuShowsTheShortcutsCharacterWhenItHasOne() throws {
    func shortcut(_ code: Int, _ characters: String) throws -> DictationShortcut {
        guard case .accepted(let accepted) = recordShortcut(keyCode: code, characters: characters, modifiers: [.control, .option, .command]) else {
            throw RecordingRefused()
        }
        return accepted
    }
    #expect(awakeMenuKey(nil) == nil)
    #expect(awakeMenuKey(try shortcut(0, "a")) == "a")
    #expect(awakeMenuKey(try shortcut(49, " ")) == " ")
    // a key with a name and no character shows none
    #expect(awakeMenuKey(try shortcut(126, "")) == nil)
    #expect(awakeMenuKey(try shortcut(122, "")) == nil)
}

private struct RecordingRefused: Error {}

@Test func theIconSaysWhenTheMacIsKeptAwake() {
    #expect(awakeIconWords(awake: false, bundle: english.bundle, locale: english.locale) == ("Carrier", nil))
    #expect(awakeIconWords(awake: true, bundle: english.bundle, locale: english.locale).label.contains("awake"))
    #expect(awakeIconWords(awake: true, bundle: english.bundle, locale: english.locale).tip != nil)
}

@Test func theWaitingNoticeNamesTheBatteryOrThePlug() {
    #expect(awakeWaitingNotice(.batteryLow(10), bundle: english.bundle, locale: english.locale).body.contains("10 %"))
    #expect(awakeWaitingNotice(.unplugged, bundle: english.bundle, locale: english.locale).body.contains("plugged"))
    #expect(awakeWaitingNotice(.unplugged, bundle: english.bundle, locale: english.locale).title == "Keep awake is waiting")
}

@Test func theLengthsAndTheBatteryRulesHaveTheirTitlesInBothLanguages() {
    #expect(AwakeLength.choices.map { AwakeLength.title($0, bundle: english.bundle, locale: english.locale) } == ["30 min", "1 hour", "2 hours", "5 hours", "Until I turn it off"])
    #expect(AwakeLength.choices.map { AwakeLength.title($0, bundle: spanish.bundle, locale: spanish.locale) } == ["30 min", "1 hora", "2 horas", "5 horas", "Hasta que lo apague"])
    #expect(BatteryRule.allCases.map { $0.title(bundle: english.bundle, locale: english.locale) } == ["Keep awake on battery too", "Stop below 30 %", "Stop below 20 %", "Stop below 10 %", "Only while plugged in"])
    #expect(BatteryRule.allCases.map { $0.title(bundle: spanish.bundle, locale: spanish.locale) } == ["Mantener despierto también con batería", "Parar por debajo del 30 %", "Parar por debajo del 20 %", "Parar por debajo del 10 %", "Solo con el cargador conectado"])
}

@Test func theStatusLineSaysSpanishWhatIsHappeningAndWhatEndsIt() {
    var settings = AwakeSettings()
    func line(_ decision: AwakeDecision) -> String { awakeStatus(decision, settings: settings, now: now, bundle: spanish.bundle, locale: spanish.locale) }
    #expect(line(AwakeDecision()) == "Apagado")
    settings.followsAgents = true
    #expect(line(AwakeDecision()) == "Apagado · se activa cuando trabajan los agentes")
    #expect(line(AwakeDecision(reason: .manual(until: now.addingTimeInterval(4320)))) == "Despierto · quedan 1 h 12 min")
    #expect(line(AwakeDecision(reason: .manual(until: now.addingTimeInterval(1200)))) == "Despierto · quedan 20 min")
    #expect(line(AwakeDecision(reason: .manual(until: now.addingTimeInterval(7200)))) == "Despierto · quedan 2 h")
    #expect(line(AwakeDecision(reason: .manual(until: now.addingTimeInterval(10)))) == "Despierto · quedan 1 min")
    #expect(line(AwakeDecision(reason: .manual(until: nil))) == "Despierto hasta que lo apagues")
    #expect(line(AwakeDecision(reason: .agents)) == "Despierto mientras trabajan los agentes")
    #expect(line(AwakeDecision(reason: .grace(until: now.addingTimeInterval(240)))) == "Despierto · 4 min después de que terminen los agentes")
    #expect(line(AwakeDecision(reason: .agents, blocked: .batteryLow(18))) == "En pausa: batería al 18 %")
    #expect(line(AwakeDecision(reason: .agents, blocked: .unplugged)) == "En pausa: con batería")
    #expect(awakeRemaining(0, bundle: spanish.bundle, locale: spanish.locale) == "menos de 1 min")
}

@Test func theToggleAndTheNoticesSaySpanishWhatAClickDoesAndWhyItStopped() {
    #expect(awakeToggleTitle(manualActive: true, defaultMinutes: 60, bundle: spanish.bundle, locale: spanish.locale) == "Dejar de mantener despierto")
    #expect(awakeToggleTitle(manualActive: false, defaultMinutes: 60, bundle: spanish.bundle, locale: spanish.locale) == "Mantener despierto durante 1 hora")
    #expect(awakeToggleTitle(manualActive: false, defaultMinutes: 300, bundle: spanish.bundle, locale: spanish.locale) == "Mantener despierto durante 5 horas")
    #expect(awakeToggleTitle(manualActive: false, defaultMinutes: 0, bundle: spanish.bundle, locale: spanish.locale) == "Mantener despierto")
    #expect(awakeEndedNotice(nil, bundle: spanish.bundle, locale: spanish.locale) == ("Mantener despierto terminó", "Tu Mac puede volver a dormirse."))
    #expect(awakeEndedNotice(.batteryLow(9), bundle: spanish.bundle, locale: spanish.locale) == ("Mantener despierto en pausa", "La batería está al 9 %. Tu Mac ya puede dormirse; conéctalo y sigue."))
    #expect(awakeEndedNotice(.unplugged, bundle: spanish.bundle, locale: spanish.locale).body == "Tu Mac funciona con batería. Ya puede dormirse; conéctalo y sigue.")
    #expect(awakeWaitingNotice(.batteryLow(10), bundle: spanish.bundle, locale: spanish.locale) == ("Mantener despierto está esperando", "La batería está al 10 %. Se activa solo cuando conectes el Mac."))
    #expect(awakeWaitingNotice(.unplugged, bundle: spanish.bundle, locale: spanish.locale).body.hasPrefix("Tu Mac funciona con batería y elegiste mantenerlo despierto"))
    #expect(awakeIconWords(awake: true, bundle: spanish.bundle, locale: spanish.locale) == ("Carrier, manteniendo el Mac despierto", "Manteniendo el Mac despierto"))
    #expect(awakeIconWords(awake: false, bundle: spanish.bundle, locale: spanish.locale) == ("Carrier", nil))
}
