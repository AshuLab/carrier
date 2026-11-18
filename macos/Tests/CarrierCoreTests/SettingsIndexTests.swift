import Testing
@testable import CarrierCore

@Test func everyPlaceInTheIndexHasItsOwnAnchorAndEveryPageIsInIt() {
    let ids = settingsIndex.map(\.id)
    #expect(Set(ids).count == ids.count)
    for page in SettingsPage.allCases { #expect(settingsIndex.contains { $0.page == page && $0.isPage }) }
    #expect(settingsAnchor(.appearance, group: "Code and output", title: "Font") == "appearance.code-and-output.font")
    // a group is the place of its own title, and a page is its name alone
    #expect(settingsAnchor(.providers, group: "Accounts", title: "Accounts") == "providers.accounts")
    #expect(settingsIndex.first { $0.page == .general && $0.isPage }?.id == "general")
    // the same title in two groups is two places
    #expect(settingsAnchor(.notifications, group: "Carrier", title: "Needs attention") != settingsAnchor(.notifications, group: "Chat", title: "Needs attention"))
}

@Test func aSearchFindsTheRowsThatHaveEveryWordAndListsTitlesFirst() {
    let font = settingsResults("font")
    #expect(font.contains { $0.page == .appearance && $0.title == "Font" })
    #expect(font.contains { $0.page == .terminal && $0.title == "Font" })
    // a match in the title comes before one that is only in the description
    #expect(font.first?.title == "Font")
    #expect(font.prefix(3).allSatisfy { $0.title.lowercased().contains("font") })
    // every word, in any order, across the title and the page's name
    #expect(settingsResults("terminal cursor").contains { $0.title == "Cursor style" })
    #expect(settingsResults("cursor terminal").contains { $0.title == "Blink cursor" })
    #expect(settingsResults("blink terminal font").isEmpty)
}

@Test func aSearchIgnoresCaseAndAccentsAndAnEmptyOneFindsNothing() {
    #expect(settingsResults("QUIET HOURS").contains { $0.title == "Quiet hours" })
    #expect(settingsResults("  ").isEmpty && settingsResults("").isEmpty)
    #expect(settingsResults("zzzz-no-such-setting").isEmpty)
    // a page is found by its name
    #expect(settingsResults("keybindings").first?.isPage == true)
}

@Test func theIndexReadsTheRowsOfTheBehaviorAndKeybindingsPagesFromTheirOwnModels() {
    for group in behaviorGroups { for row in group.rows { #expect(settingsIndex.contains { $0.page == .behavior && $0.group == group.title && $0.title == row.title }) } }
    for command in ShortcutCommand.allCases { #expect(settingsIndex.contains { $0.page == .keybindings && $0.group == command.group.rawValue && $0.title == command.title }) }
}
