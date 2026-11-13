import Testing
@testable import CarrierCore

@Test func theAppGroupHasNoHeadingAndHoldsWhatIsSharedAndWhatIsOfTheMac() {
    #expect(SettingsPage.Group.app.heading == nil)
    #expect(SettingsPage.pages(in: .app) == [.general, .providers, .notifications, .appearance, .keybindings, .updates])
}

@Test func theChatGroupHasItsHeadingAndHoldsChatSidebarSessionsAndDictation() {
    #expect(SettingsPage.Group.chat.heading == "Chat")
    #expect(SettingsPage.pages(in: .chat) == [.chat, .sidebar, .sessions, .dictation])
    #expect(SettingsPage.sessions.group == .chat)
    #expect(SettingsPage.sessions.detail == "How sessions start and age out")
    #expect(SettingsPage.dictation.icon == "mic" && SettingsPage.dictation.detail == "Speak instead of typing")
}

@Test func legacyHasItsHeadingAndHoldsHealth() {
    #expect(SettingsPage.Group.legacy.heading == "Legacy")
    #expect(SettingsPage.pages(in: .legacy) == [.health])
}

@Test func theCarrierGroupHasItsHeadingAndHoldsReposAgentsBehaviorAndEngine() {
    #expect(SettingsPage.Group.carrier.heading == "Carrier")
    #expect(SettingsPage.pages(in: .carrier) == [.repos, .agents, .behavior, .engine])
    #expect(SettingsPage.repos.group == .carrier)
    #expect(SettingsPage.agents.group == .carrier)
    #expect(SettingsPage.behavior.group == .carrier)
    #expect(SettingsPage.behavior.detail == "How Carrier runs epics")
    #expect(SettingsPage.engine.group == .carrier)
    #expect(SettingsPage.engine.detail == "How the app runs Carrier")
}

@Test func theRailListsTheAppGroupFirstAndEveryPageHasARow() {
    #expect(SettingsPage.Group.allCases == [.app, .chat, .carrier, .legacy])
    #expect(SettingsPage.allCases == SettingsPage.Group.allCases.flatMap { SettingsPage.pages(in: $0) })
    #expect(SettingsPage.allCases.allSatisfy { !$0.icon.isEmpty && !$0.detail.isEmpty })
}
