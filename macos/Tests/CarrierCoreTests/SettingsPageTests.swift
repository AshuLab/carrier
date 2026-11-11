import Testing
@testable import CarrierCore

@Test func theAppGroupHasNoHeadingAndHoldsGeneralThenNotifications() {
    #expect(SettingsPage.Group.app.heading == nil)
    #expect(SettingsPage.pages(in: .app) == [.general, .notifications, .appearance, .sidebar, .chat, .keybindings])
}

@Test func legacyHasItsHeadingAndNoLongerHoldsRepos() {
    #expect(SettingsPage.Group.legacy.heading == "Legacy")
    #expect(SettingsPage.pages(in: .legacy) == [.engine, .behavior, .sessions, .health])
}

@Test func theCarrierGroupHasItsHeadingAndHoldsRepos() {
    #expect(SettingsPage.Group.carrier.heading == "Carrier")
    #expect(SettingsPage.pages(in: .carrier) == [.repos])
    #expect(SettingsPage.repos.group == .carrier)
}

@Test func theRailListsTheAppGroupFirstAndEveryPageHasARow() {
    #expect(SettingsPage.Group.allCases == [.app, .carrier, .legacy])
    #expect(SettingsPage.allCases == SettingsPage.Group.allCases.flatMap { SettingsPage.pages(in: $0) })
    #expect(SettingsPage.allCases.allSatisfy { !$0.icon.isEmpty && !$0.detail.isEmpty })
}
