import Testing
@testable import CarrierCore

@Test func aNewWindowShowsBothColumnsOnTheOverview() {
    let shell = WindowShell()
    #expect(shell.selection == .overview)
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

@Test func theSelectionHoldsOverviewAnEpicAndSettings() {
    let shell = WindowShell()
    for next in [Selection.epic(repo: "acme/web", issue: 7), .settings, .overview] {
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
    #expect(shell.selection == .overview && shell.sidebarShown && shell.inspectorShown)
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
