import Foundation
import Testing
@testable import CarrierCore

@Test func aNewWindowShowsBothColumnsOnHome() {
    let shell = WindowShell()
    #expect(shell.selection == .home)
    #expect(shell.sidebarShown && shell.inspectorShown)
}

@Test func theToolbarButtonsToggleTheirOwnColumnOnly() {
    let shell = WindowShell()
    shell.toggleSidebar()
    #expect(shell.sidebarShown == false && shell.inspectorShown)
    shell.toggleInspector()
    #expect(shell.sidebarShown == false && shell.inspectorShown == false)
    shell.toggleSidebar()
    shell.toggleInspector()
    #expect(shell.sidebarShown && shell.inspectorShown)
}

@Test func theSelectionHoldsEveryPage() {
    let shell = WindowShell()
    for next in [Selection.epic(repo: "acme/web", issue: 7), .home, .sessions, .session(id: "s1"), .newSession, .archive, .carrier] {
        shell.selection = next
        #expect(shell.selection == next)
    }
    #expect(Selection.epic(repo: "acme/web", issue: 7) != .epic(repo: "acme/web", issue: 8))
}

@Test func resetPutsTheWindowBackToItsStart() {
    let shell = WindowShell()
    shell.selection = .epic(repo: "acme/web", issue: 7)
    shell.sidebarShown = false
    shell.inspectorShown = false
    shell.reset()
    #expect(shell.selection == .home && shell.sidebarShown && shell.inspectorShown)
}

@Test func aNewWindowStartsWithSessionsOpen() { #expect(WindowShell().open == .sessions) }

@Test func eachSelectionSetsOrKeepsTheOpenSection() {
    let shell = WindowShell()
    for (next, opens) in [
        (Selection.carrier, OpenSection.carrier), (.sessions, .sessions), (.epic(repo: "acme/web", issue: 7), .carrier), (.session(id: "s1"), .sessions),
        (.newSession, .sessions),
        (.archive, .archive),
    ] {
        shell.open = nil
        shell.selection = next
        #expect(shell.open == opens)
    }
    for (kept, next) in [(OpenSection.carrier as OpenSection?, Selection.home), (nil, .home), (.archive, .home)] {
        shell.open = kept
        shell.selection = next
        #expect(shell.open == kept)
    }
}

@Test func aSessionChosenFromAnywhereOpensSessions() {
    // the Archive list chooses through `chooseArchived`; any other way to a session unfolds Sessions
    let shell = WindowShell(open: .archive)
    shell.selection = .session(id: "s1")
    #expect(shell.open == .sessions)
}

@Test func aSessionChosenFromTheArchiveListKeepsArchiveOpen() {
    let shell = WindowShell(open: .archive)
    shell.chooseArchived("s1")
    #expect(shell.selection == .session(id: "s1"))
    #expect(shell.open == .archive)
}

@Test func foldingTheOpenSectionLeavesBothFoldedAndOpeningOneFoldsTheOther() {
    let shell = WindowShell()
    shell.open = nil
    #expect(shell.open == nil)
    shell.selection = .carrier
    #expect(shell.open == .carrier)
    shell.selection = .sessions
    #expect(shell.open == .sessions)
    shell.selection = .archive
    #expect(shell.open == .archive)
    shell.selection = .carrier
    #expect(shell.open == .carrier)
}

@Test func resetOpensTheGivenSectionOrSessions() {
    let shell = WindowShell(open: .carrier)
    #expect(shell.open == .carrier)
    shell.selection = .sessions
    shell.reset()
    #expect(shell.open == .sessions)
    shell.reset(open: nil)
    #expect(shell.open == nil)
    shell.reset(open: .carrier)
    #expect(shell.open == .carrier && shell.selection == .home)
}

@Test func escapeAndAClickOutsideCloseTheAboutSheetButAClickOnItDoesNot() {
    let shell = WindowShell()
    shell.selection = .epic(repo: "acme/web", issue: 7)
    for closing in [AboutInput.escape, .clickOutside] {
        shell.showAbout()
        #expect(shell.aboutShown)
        shell.aboutInput(.clickInside)
        #expect(shell.aboutShown)
        shell.aboutInput(closing)
        #expect(shell.aboutShown == false)
    }
    #expect(shell.selection == .epic(repo: "acme/web", issue: 7))
    shell.showAbout()
    shell.reset()
    #expect(shell.aboutShown == false)
}

@Test func askingForNewSessionWhileItsDraftIsOpenCountsAsOpeningIt() {
    let shell = WindowShell()
    shell.selection = .newSession
    shell.selection = .newSession
    #expect(shell.newSessionOpened == 2)
    shell.selection = .home
    #expect(shell.newSessionOpened == 2)
}

private func freshTable() -> ShortcutTable {
    let suite = "shortcuts-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return ShortcutTable(defaults: defaults)
}

@Test func commandAndANumberOrFSelectOrSearch() {
    let table = freshTable()
    #expect(shortcutAction(key: "1", modifiers: .command, in: table) == .select(.home))
    #expect(shortcutAction(key: "2", modifiers: .command, in: table) == .select(.sessions))
    #expect(shortcutAction(key: "3", modifiers: .command, in: table) == .select(.carrier))
    #expect(shortcutAction(key: "n", modifiers: .command, in: table) == .select(.newSession))
    #expect(shortcutAction(key: "f", modifiers: .command, in: table) == .search)
    #expect(shortcutAction(key: "F", modifiers: .command, in: table) == .search)
}

@Test func anotherModifierOrAnotherKeyIsNothing() {
    let table = freshTable()
    for modifiers in [ShortcutModifiers([]), .shift, .option, .control, [.command, .shift], [.command, .option], [.command, .control]] {
        for key in ["1", "2", "3", "n", "f"] { #expect(shortcutAction(key: key, modifiers: modifiers, in: table) == nil) }
    }
    for key in ["4", "0", "g", "", "12"] { #expect(shortcutAction(key: key, modifiers: .command, in: table) == nil) }
}

@Test func shortcutActionReadsThePersonsOwnCombinations() {
    let table = freshTable()
    table.set(KeyCombo(key: "j", modifiers: [.command, .option]), for: .search)
    #expect(shortcutAction(key: "j", modifiers: [.command, .option], in: table) == .search)
    #expect(shortcutAction(key: "f", modifiers: .command, in: table) == nil)
    table.set(nil, for: .home)
    #expect(shortcutAction(key: "1", modifiers: .command, in: table) == nil)
}

@Test func theSelectionShortcutsActAsAClickDoes() {
    let shell = WindowShell()
    shell.open = nil
    shell.perform(.select(.sessions))
    #expect(shell.selection == .sessions && shell.open == .sessions)
    shell.perform(.select(.carrier))
    #expect(shell.selection == .carrier && shell.open == .carrier)
    shell.perform(.select(.home))
    #expect(shell.selection == .home && shell.open == .carrier)
}

@Test func searchAsksTheOpenSectionAndNothingWhenBothAreFolded() {
    let shell = WindowShell()
    shell.open = nil
    shell.perform(.search)
    #expect(shell.searchRequest == nil)
    shell.open = .sessions
    shell.perform(.search)
    #expect(shell.searchRequest?.section == .sessions)
    let first = shell.searchRequest
    shell.perform(.search)
    #expect(shell.searchRequest != first && shell.searchRequest?.section == .sessions)
    shell.open = .carrier
    shell.perform(.search)
    #expect(shell.searchRequest?.section == .carrier)
    shell.reset()
    #expect(shell.searchRequest == nil)
}

@Test func settingsIsASheetOverTheSelectionThatOpensOnTheFirstPageUnlessAskedOtherwise() {
    let shell = WindowShell()
    shell.selection = .sessions
    shell.showSettings()
    #expect(shell.settingsShown && shell.settingsTab == .general && shell.selection == .sessions)
    shell.settingsShown = false
    shell.openHealth()
    #expect(shell.settingsShown && shell.settingsTab == .health && shell.selection == .sessions)
    shell.showSettings()
    #expect(shell.settingsTab == .general)
    shell.reset()
    #expect(shell.settingsShown == false)
}

@Test func settingsOpensOnAskedPage() {
    let shell = WindowShell()
    shell.showSettings(.sessions)
    #expect(shell.settingsShown && shell.settingsTab == .sessions)
    shell.showSettings(.engine)
    #expect(shell.settingsTab == .engine)
}
