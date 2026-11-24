import Foundation
import Testing
@testable import CarrierCore

@Test func eachStateHasItsOwnSymbol() {
    let symbols = StateShape.allCases.map(stateSymbol)
    #expect(symbols.count == 4)
    #expect(Set(symbols).count == 4)
}

@Test func theStatesOfAnEpicASessionAStepAndACallMapToTheFour() {
    #expect(EpicMenuState.running.shape() == .working)
    #expect(EpicMenuState.needsYou.shape(attention: .input) == .needsAttention)
    #expect(EpicMenuState.needsYou.shape(attention: .error) == .problem)
    #expect(EpicMenuState.ready.shape() == .ready)
    #expect(EpicMenuState.done.shape() == nil)
    #expect(SessionState.working.shape == .working)
    #expect(SessionState.waiting.shape == .needsAttention)
    #expect(StepState.input.shape == .needsAttention)
    #expect(StepState.error.shape == .problem)
    #expect(CallStatus.failed.shape == .problem)
    #expect(CallStatus.running.shape == .working)
}

@Test func statesAreToldApartByShapeOnlyWhenAsked() {
    let store = AppPreferences(defaults: UserDefaults(suiteName: "shape-\(UUID().uuidString)")!)
    #expect(store.statesByShape == false)
    store.statesByShape = true
    #expect(store.statesByShape)
    store.reset(.appearance)
    #expect(store.statesByShape == false)
}
