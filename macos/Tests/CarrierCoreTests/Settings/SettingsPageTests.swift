import Foundation
import Testing
@testable import CarrierCore

@Test func theAppGroupHasNoHeadingAndHoldsWhatIsSharedAndWhatIsOfTheMac() {
    #expect(SettingsPage.Group.app.heading == nil)
    #expect(SettingsPage.pages(in: .app) == [.general, .providers, .appearance, .notifications, .keybindings, .dictation, .keepAwake])
    #expect(SettingsPage.terminal.icon == .terminal && SettingsPage.terminal.detail == "Theme, font, cursor, padding and shell behavior")
    #expect(SettingsPage.dictation.icon == .microphone && SettingsPage.dictation.detail == "Speak instead of typing")
}

@Test func theWorkspaceGroupHoldsChatSessionsProjectsSidebarAndTerminal() {
    #expect(SettingsPage.Group.workspace.heading == "Workspace")
    #expect(SettingsPage.pages(in: .workspace) == [.chat, .sessions, .projects, .sidebar, .terminal])
    #expect(SettingsPage.sessions.group == .workspace)
    #expect(SettingsPage.sessions.detail == "How sessions start and age out")
}

@Test func theCarrierGroupHoldsAgentsReposAndBehavior() {
    #expect(SettingsPage.Group.carrier.heading == "Carrier")
    #expect(SettingsPage.pages(in: .carrier) == [.agents, .watching, .behavior])
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
    #expect(SettingsPage.allCases.count == 18)
    #expect(SettingsPage.allCases.allSatisfy { !$0.detail.isEmpty })
    // Projects sits between Sessions and Sidebar, with an icon the set already has
    let workspace = SettingsPage.pages(in: .workspace)
    #expect(workspace.firstIndex(of: .projects) == workspace.firstIndex(of: .sessions)! + 1 && workspace.firstIndex(of: .sidebar) == workspace.firstIndex(of: .projects)! + 1)
    #expect(SettingsPage.projects.icon == .folder)
}

@Test func thePagesOfSettingsThatAreSettingsFormsAreTheOnesMadeOfSimpleRows() {
    #expect(SettingsPage.allCases.filter(\.usesForm) == [.general, .providers, .appearance, .notifications, .keybindings, .dictation, .keepAwake, .chat, .sessions, .sidebar, .terminal, .agents, .watching, .behavior, .engine, .about])
}

@Test func theLongPagesAreAColumnAndTheListsAndTablesTakeTheWidth() {
    #expect(SettingsPage.allCases.filter { !$0.isColumn } == [.projects, .health])
}

@Test func theLastSettingsPageIsSavedByItsIdentifierAndAnEarlierBuildsTitleStillOpensIt() {
    let suite = "last-settings-page-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = AppPreferences(defaults: defaults)
    // nothing stored yet opens General
    #expect(preferences.lastSettingsPage == .general)
    // an identifier is what is stored, and it opens its page
    preferences.lastSettingsPage = .keepAwake
    #expect(defaults.string(forKey: "settingsLastPage") == "keep-awake" && preferences.lastSettingsPage == .keepAwake)
    // an earlier build stored the page's English title: it still opens its page
    defaults.set("Keep awake", forKey: "settingsLastPage")
    #expect(preferences.lastSettingsPage == .keepAwake)
    defaults.set("Watching", forKey: "settingsLastPage")
    #expect(preferences.lastSettingsPage == .watching)
    // anything else opens General
    defaults.set("Not a page", forKey: "settingsLastPage")
    #expect(preferences.lastSettingsPage == .general)
    for page in SettingsPage.allCases { #expect(SettingsPage(stored: page.rawValue) == page && SettingsPage(stored: page.title) == page) }
}
