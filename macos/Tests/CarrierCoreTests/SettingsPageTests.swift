import Testing
@testable import CarrierCore

@Test func theAppGroupHasNoHeadingAndHoldsGeneralThenNotifications() {
    #expect(SettingsPage.Group.app.heading == nil)
    #expect(SettingsPage.pages(in: .app) == [.general, .notifications, .sidebar])
}

@Test func legacyHasItsHeadingAndHoldsExactlyTheFivePagesThatExistedInOrder() {
    #expect(SettingsPage.Group.legacy.heading == "Legacy")
    #expect(SettingsPage.pages(in: .legacy) == [.engine, .behavior, .repos, .sessions, .health])
}

@Test func theRailListsTheAppGroupFirstAndEveryPageHasARow() {
    #expect(SettingsPage.Group.allCases == [.app, .legacy])
    #expect(SettingsPage.allCases == SettingsPage.Group.allCases.flatMap { SettingsPage.pages(in: $0) })
    #expect(SettingsPage.allCases.allSatisfy { !$0.icon.isEmpty && !$0.detail.isEmpty })
}
