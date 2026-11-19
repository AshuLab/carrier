import Testing
@testable import CarrierCore

@Test func theAppGroupHasNoHeadingAndHoldsWhatIsSharedAndWhatIsOfTheMac() {
    #expect(SettingsPage.Group.app.heading == nil)
    #expect(SettingsPage.pages(in: .app) == [.general, .providers, .appearance, .notifications, .keybindings, .dictation])
    #expect(SettingsPage.terminal.icon == "terminal" && SettingsPage.terminal.detail == "Theme, font, cursor, padding and shell behavior")
    #expect(SettingsPage.dictation.icon == "mic" && SettingsPage.dictation.detail == "Speak instead of typing")
}

@Test func theWorkspaceGroupHoldsChatSessionsSidebarAndTerminal() {
    #expect(SettingsPage.Group.workspace.heading == "Workspace")
    #expect(SettingsPage.pages(in: .workspace) == [.chat, .sessions, .sidebar, .terminal])
    #expect(SettingsPage.sessions.group == .workspace)
    #expect(SettingsPage.sessions.detail == "How sessions start and age out")
}

@Test func theCarrierGroupHoldsAgentsReposAndBehavior() {
    #expect(SettingsPage.Group.carrier.heading == "Carrier")
    #expect(SettingsPage.pages(in: .carrier) == [.agents, .repos, .behavior])
    #expect(SettingsPage.behavior.detail == "How Carrier runs epics")
}

@Test func theSystemGroupHoldsEngineHealthAndAboutAtTheFoot() {
    #expect(SettingsPage.Group.system.heading == "System")
    #expect(SettingsPage.pages(in: .system) == [.engine, .health, .about])
    #expect(SettingsPage.engine.detail == "How the app runs Carrier")
    #expect(SettingsPage.allCases.last == .about)
}

@Test func theSidebarListsEveryPageOnceInTheOrderOfItsGroups() {
    #expect(SettingsPage.Group.allCases == [.app, .workspace, .carrier, .system])
    #expect(SettingsPage.Group.allCases.map(\.heading) == [nil, "Workspace", "Carrier", "System"])
    #expect(SettingsPage.allCases == SettingsPage.Group.allCases.flatMap { SettingsPage.pages(in: $0) })
    #expect(SettingsPage.allCases.count == 16)
    #expect(SettingsPage.allCases.allSatisfy { !$0.icon.isEmpty && !$0.detail.isEmpty })
}

@Test func thePagesOfSettingsThatAreSettingsFormsAreTheOnesMadeOfSimpleRows() {
    #expect(SettingsPage.allCases.filter(\.usesForm) == [.general, .providers, .appearance, .notifications, .keybindings, .dictation, .chat, .sessions, .sidebar, .terminal, .agents, .behavior, .engine, .about])
}

@Test func theLongPagesAreAColumnAndTheListsAndTablesTakeTheWidth() {
    #expect(SettingsPage.allCases.filter { !$0.isColumn } == [.repos, .health])
}
