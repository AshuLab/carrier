import Testing
@testable import CarrierCore

@Test func backAndForwardWalkThePagesVisitedAndStopAtTheEnds() {
    var history = SettingsHistory()
    #expect(history.current == .general && !history.canGoBack && !history.canGoForward)
    history.visit(.providers)
    history.visit(.appearance)
    #expect(history.current == .appearance && history.canGoBack && !history.canGoForward)
    history.back()
    #expect(history.current == .providers && history.canGoBack && history.canGoForward)
    history.back()
    history.back()
    #expect(history.current == .general)
    history.forward()
    history.forward()
    history.forward()
    #expect(history.current == .appearance)
}

@Test func visitingFromTheMiddleDropsWhatWasAheadAndTheSamePageAddsNothing() {
    var history = SettingsHistory(.general)
    history.visit(.providers)
    history.visit(.appearance)
    history.back()
    // the page already shown adds nothing and keeps what is ahead
    history.visit(.providers)
    #expect(history.pages == [.general, .providers, .appearance] && history.index == 1)
    history.visit(.chat)
    #expect(history.pages == [.general, .providers, .chat] && history.index == 2 && !history.canGoForward)
}
