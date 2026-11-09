import Foundation
import Testing
@testable import CarrierCore

private func freshTable() -> (ShortcutTable, UserDefaults) {
    let suite = "shortcuts-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return (ShortcutTable(defaults: defaults), defaults)
}

@Test func theDefaultsAreTheGoToAndSessionsGroups() {
    let (table, _) = freshTable()
    let shown = ShortcutCommand.allCases.filter { $0.group != .carrier }.map { "\($0.group.rawValue) \($0.title) \(table.combo(for: $0)?.text ?? "")" }
    #expect(shown == [
        "Go to Home ⌘1", "Go to Sessions ⌘2", "Go to Carrier ⌘3", "Go to Archive ⌘4", "Sessions New session ⌘N", "Sessions Search ⌘F",
        "Sessions Next session ⌘]", "Sessions Previous session ⌘[", "Sessions Archive the session ⇧⌘A",
        "Conversation Focus the message box ⌘L", "Conversation Stop the agent ⌘.", "Conversation Jump to the latest message ⌘↓", "Conversation Fold or unfold the tool calls ⌥⌘E",
        "Conversation Copy the last answer ⇧⌘C",
    ])
    #expect(ShortcutCommand.allCases.allSatisfy { table.isDefault($0) })
}

@Test func aCombinationOfThePersonReplacesTheDefaultAndSurvivesANewTable() {
    let (table, defaults) = freshTable()
    let own = KeyCombo(key: "k", modifiers: [.command, .shift])
    table.set(own, for: .newSession)
    #expect(table.combo(for: .newSession) == own && table.combo(for: .newSession)?.text == "⇧⌘K")
    #expect(table.isDefault(.newSession) == false && table.isDefault(.home))
    #expect(ShortcutTable(defaults: defaults).combo(for: .newSession) == own)
}

@Test func clearingLeavesNoCombinationAndGoingBackToTheDefaultKeepsNoOverride() {
    let (table, defaults) = freshTable()
    table.set(nil, for: .search)
    #expect(table.combo(for: .search) == nil && table.isDefault(.search) == false)
    table.set(ShortcutCommand.search.defaultCombo, for: .search)
    #expect(table.combo(for: .search)?.text == "⌘F" && table.isDefault(.search))
    #expect((defaults.dictionary(forKey: ShortcutTable.key) ?? [:]).isEmpty)
}

@Test func aBadSavedValueReadsAsTheDefault() {
    let (table, defaults) = freshTable()
    defaults.set(["home": "garbage", "search": "0:f", "carrier": "1:"], forKey: ShortcutTable.key)
    #expect(table.combo(for: .home)?.text == "⌘1")
    #expect(table.combo(for: .search)?.text == "⌘F")
    #expect(table.combo(for: .carrier)?.text == "⌘3")
}

@Test func aRecordedCombinationMustCarryCommandControlOrOption() {
    #expect(KeyCombo(key: "a", modifiers: []) == nil)
    #expect(KeyCombo(key: "a", modifiers: .shift) == nil)
    #expect(KeyCombo(key: "a", modifiers: .command) != nil)
    #expect(KeyCombo(key: "a", modifiers: .control) != nil)
    #expect(KeyCombo(key: "a", modifiers: .option) != nil)
    #expect(KeyCombo(key: "a", modifiers: [.shift, .command]) != nil)
    // more than one key, or no key, or a control character, is not a key
    #expect(KeyCombo(key: "ab", modifiers: .command) == nil)
    #expect(KeyCombo(key: "", modifiers: .command) == nil)
    #expect(KeyCombo(key: "\u{1B}", modifiers: .command) == nil)
}

@Test func aCombinationAnotherActionHasIsAClash() {
    let (table, _) = freshTable()
    let notes = KeyCombo(key: "1", modifiers: .command)!
    #expect(table.clash(of: notes, for: .search) == .home)
    #expect(table.clash(of: notes, for: .home) == nil)
    #expect(table.clash(of: KeyCombo(key: "9", modifiers: .command)!, for: .home) == nil)
    // a clash is flagged and kept: the first action of the table runs
    table.set(notes, for: .search)
    #expect(table.command(for: notes) == .home)
    // a cleared action has no combination to clash with
    table.set(nil, for: .home)
    #expect(table.clash(of: notes, for: .sessions) == .search)
}

@Test func combosChangeWhenACombinationDoes() {
    let (table, _) = freshTable()
    let before = table.combos
    table.set(KeyCombo(key: "k", modifiers: .command), for: .home)
    #expect(table.combos != before)
}

@Test func resetOfTheKeybindingsPageRestoresEveryDefault() {
    let (table, defaults) = freshTable()
    table.set(KeyCombo(key: "k", modifiers: .command), for: .home)
    table.set(nil, for: .search)
    AppPreferences(defaults: defaults).reset(.keybindings)
    #expect(ShortcutCommand.allCases.allSatisfy { table.isDefault($0) })
}

@Test func theCarrierControlsHaveNoCombinationUntilThePersonGivesOne() {
    let (table, defaults) = freshTable()
    let controls: [ShortcutCommand] = [.startOrStop, .pauseOrResume, .checkNow]
    #expect(ShortcutCommand.allCases.filter { $0.group == .carrier } == controls)
    #expect(controls.allSatisfy { table.combo(for: $0) == nil && $0.defaultCombo == nil && $0.action == nil && table.isDefault($0) })
    let own = KeyCombo(key: "p", modifiers: [.command, .option])!
    table.set(own, for: .pauseOrResume)
    #expect(ShortcutTable(defaults: defaults).combo(for: .pauseOrResume) == own)
    #expect(table.command(for: own) == .pauseOrResume && table.isDefault(.pauseOrResume) == false)
    // the window's key monitor leaves it to the menu
    #expect(shortcutAction(key: "p", modifiers: [.command, .option], in: table) == nil)
    table.set(nil, for: .pauseOrResume)
    #expect(table.isDefault(.pauseOrResume))
}

@Test func theKeysOfTheSystemMenusAreReservedAndSpecialKeysAreNotCombinations() {
    for key in ["c", "v", "x", "a", "z", "q", "w", ","] { #expect(KeyCombo(key: key, modifiers: .command)?.isReserved == true) }
    #expect(KeyCombo(key: "z", modifiers: [.command, .shift])?.isReserved == true)
    #expect(KeyCombo(key: "c", modifiers: [.command, .shift])?.isReserved == false)
    #expect(KeyCombo(key: "l", modifiers: .command)?.isReserved == false)
    // an arrow other than ⌘↓ and a function key come as private characters
    #expect(KeyCombo(key: "\u{F702}", modifiers: .command) == nil && KeyCombo(key: "\u{F704}", modifiers: .command) == nil)
    #expect(KeyCombo(key: KeyCombo.downArrow, modifiers: .command)?.text == "⌘↓")
}
