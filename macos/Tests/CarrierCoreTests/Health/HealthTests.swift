import Testing
@testable import CarrierCore

// The rule that decides whether the app asks the host for the health.

@Test func everyMomentAsksAHostThatListsHealthAndNoneAsksOneThatDoesNot() {
    for moment in HealthMoment.allCases {
        #expect(shouldAskHealth(moment, capabilities: [.agents, .health]))
        #expect(shouldAskHealth(moment, capabilities: [.agents, .list]) == false)
        #expect(shouldAskHealth(moment, capabilities: []) == false)
    }
}

@Test func openUsesTheHostsKeptAnswerAndTheOtherMomentsAskForAFreshOne() {
    #expect(HealthMoment.open.refreshes == false)
    #expect(HealthMoment.active.refreshes && HealthMoment.refresh.refreshes)
}

@Test func onlyMissingAndSignedOutBlock() {
    #expect([ToolState.ready, .missing, .signedOut, .unknown].filter(\.blocks) == [.missing, .signedOut])
}
