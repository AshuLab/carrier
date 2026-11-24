import Testing

@testable import CarrierCore

private final class FakeTrust: AccessibilityTrust, @unchecked Sendable {
    var trusted: Bool
    private(set) var prompts = 0

    init(trusted: Bool) { self.trusted = trusted }

    func isTrusted() -> Bool { trusted }
    func prompt() { prompts += 1 }
}

@MainActor
@Test func theStateStartsWithWhatMacOSSaysAndIsReadAgainOnRefresh() {
    let trust = FakeTrust(trusted: false)
    let state = AccessibilityState(trust: trust)
    #expect(state.trusted == false)
    trust.trusted = true
    #expect(state.trusted == false)
    state.refresh()
    #expect(state.trusted)
}

@MainActor
@Test func askingPromptsMacOSAndDoesNotChangeWhatIsShown() {
    let trust = FakeTrust(trusted: false)
    let state = AccessibilityState(trust: trust)
    state.ask()
    #expect(trust.prompts == 1)
    #expect(state.trusted == false)
}

@MainActor
@Test func theExplanationIsForTheFirstTimeAndOnlyWithoutTheAccess() {
    let trust = FakeTrust(trusted: false)
    let state = AccessibilityState(trust: trust)
    #expect(state.shouldExplain(explained: false))
    #expect(state.shouldExplain(explained: true) == false)
    // allowed in System Settings since the state last read it: it asks macOS now
    trust.trusted = true
    #expect(state.shouldExplain(explained: false) == false)
}
