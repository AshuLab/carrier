import Testing
@testable import CarrierCore

@Test func backAndForwardWalkThePagesVisitedAndStopAtTheEnds() {
    var history = SettingsHistory()
    #expect(history.page == .general && !history.canGoBack && !history.canGoForward)
    history.visit(.providers)
    history.visit(.appearance)
    #expect(history.page == .appearance && history.canGoBack && !history.canGoForward)
    history.back()
    #expect(history.page == .providers && history.canGoBack && history.canGoForward)
    history.back()
    history.back()
    #expect(history.page == .general)
    history.forward()
    history.forward()
    history.forward()
    #expect(history.page == .appearance)
}

@Test func visitingFromTheMiddleDropsWhatWasAheadAndTheSamePageAddsNothing() {
    var history = SettingsHistory(.general)
    history.visit(.providers)
    history.visit(.appearance)
    history.back()
    // the page already shown adds nothing and keeps what is ahead
    history.visit(.providers)
    #expect(history.places.map(\.page) == [.general, .providers, .appearance] && history.index == 1)
    history.visit(.chat)
    #expect(history.places.map(\.page) == [.general, .providers, .chat] && history.index == 2 && !history.canGoForward)
}

@Test func aScreenInsideAPageIsAPlaceOfItsOwnThatBackLeaves() {
    var history = SettingsHistory(.general)
    history.visit(.providers)
    history.visit(SettingsPlace(.providers, path: ["claude"]))
    history.visit(SettingsPlace(.providers, path: ["claude", "work"]))
    #expect(history.current == SettingsPlace(.providers, path: ["claude", "work"]) && history.page == .providers)
    history.back()
    #expect(history.current.path == ["claude"])
    history.back()
    #expect(history.current == SettingsPlace(.providers))
    // the same place again adds nothing; the first screen of a page and a screen inside it are two places
    history.visit(.providers)
    #expect(history.places.count == 4)
}

@Test func aProjectsListTakesTheWidthAndAProjectsOwnScreenIsAColumn() {
    #expect(SettingsPlace(.projects).isColumn == false)
    #expect(SettingsPlace(.projects, path: ["/Users/ana/notes"]).isColumn)
    #expect(SettingsPlace(.projects, path: ["/Users/ana/notes", "actions"]).isColumn)
    #expect(SettingsPlace(.repos).isColumn == false && SettingsPlace(.sessions).isColumn)
}
