import Testing
@testable import CarrierCore

@Test func theAppGroupHasNoHeadingAndHoldsGeneralThenNotificationsAndEndsWithUpdates() {
    #expect(SettingsPage.Group.app.heading == nil)
    #expect(SettingsPage.pages(in: .app) == [.general, .notifications, .appearance, .sidebar, .chat, .keybindings, .updates])
}

@Test func legacyHasItsHeadingAndHoldsSessionsAndHealth() {
    #expect(SettingsPage.Group.legacy.heading == "Legacy")
    #expect(SettingsPage.pages(in: .legacy) == [.sessions, .health])
}

@Test func theCarrierGroupHasItsHeadingAndHoldsProvidersThenReposAgentsBehaviorAndEngine() {
    #expect(SettingsPage.Group.carrier.heading == "Carrier")
    #expect(SettingsPage.pages(in: .carrier) == [.providers, .repos, .agents, .behavior, .engine])
    #expect(SettingsPage.providers.group == .carrier)
    #expect(SettingsPage.repos.group == .carrier)
    #expect(SettingsPage.agents.group == .carrier)
    #expect(SettingsPage.behavior.group == .carrier)
    #expect(SettingsPage.behavior.detail == "How Carrier runs epics")
    #expect(SettingsPage.engine.group == .carrier)
    #expect(SettingsPage.engine.detail == "How the app runs Carrier")
}

@Test func theRailListsTheAppGroupFirstAndEveryPageHasARow() {
    #expect(SettingsPage.Group.allCases == [.app, .carrier, .legacy])
    #expect(SettingsPage.allCases == SettingsPage.Group.allCases.flatMap { SettingsPage.pages(in: $0) })
    #expect(SettingsPage.allCases.allSatisfy { !$0.icon.isEmpty && !$0.detail.isEmpty })
}
