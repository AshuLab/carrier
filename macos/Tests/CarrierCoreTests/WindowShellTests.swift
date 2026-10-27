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
    for next in [Selection.epic(repo: "acme/web", issue: 7), .settings, .home, .sessions, .session(id: "s1"), .archive, .carrier] {
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
    ] {
        shell.open = nil
        shell.selection = next
        #expect(shell.open == opens)
    }
    for (kept, next) in [(OpenSection.carrier as OpenSection?, Selection.home), (.sessions, .archive), (nil, .settings), (.carrier, .settings)] {
        shell.open = kept
        shell.selection = next
        #expect(shell.open == kept)
    }
}

@Test func foldingTheOpenSectionLeavesBothFoldedAndOpeningOneFoldsTheOther() {
    let shell = WindowShell()
    shell.open = nil
    #expect(shell.open == nil)
    shell.selection = .carrier
    #expect(shell.open == .carrier)
    shell.selection = .sessions
    #expect(shell.open == .sessions)
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
