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
    for next in [Selection.epic(repo: "acme/web", issue: 7), .settings, .home, .sessions, .session(id: "s1"), .newSession, .archive, .carrier] {
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
    for (kept, next) in [(OpenSection.carrier as OpenSection?, Selection.home), (nil, .settings), (.carrier, .settings), (.archive, .settings)] {
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

@Test func commandAndANumberOrFSelectOrSearch() {
    #expect(shortcutAction(key: "1", modifiers: .command) == .select(.home))
    #expect(shortcutAction(key: "2", modifiers: .command) == .select(.sessions))
    #expect(shortcutAction(key: "3", modifiers: .command) == .select(.carrier))
    #expect(shortcutAction(key: "n", modifiers: .command) == .select(.newSession))
    #expect(shortcutAction(key: "f", modifiers: .command) == .search)
    #expect(shortcutAction(key: "F", modifiers: .command) == .search)
}

@Test func anotherModifierOrAnotherKeyIsNothing() {
    for modifiers in [ShortcutModifiers([]), .shift, .option, .control, [.command, .shift], [.command, .option], [.command, .control]] {
        for key in ["1", "2", "3", "n", "f"] { #expect(shortcutAction(key: key, modifiers: modifiers) == nil) }
    }
    for key in ["4", "0", "g", "", "12"] { #expect(shortcutAction(key: key, modifiers: .command) == nil) }
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
