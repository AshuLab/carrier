import Testing
@testable import CarrierCore

@Test func thereAreNineEmptyStatesEachWithAnIconATitleAndOneLine() {
    #expect(EmptyState.allCases.count == 9)
    for state in EmptyState.allCases {
        #expect(state.icon.isEmpty == false)
        #expect(state.title.isEmpty == false)
        #expect(state.line.isEmpty == false)
        #expect(state.line.contains("\n") == false)
    }
}

@Test func noTwoEmptyStatesShareAnIconOrATitle() {
    #expect(Set(EmptyState.allCases.map(\.icon)).count == 9)
    #expect(Set(EmptyState.allCases.map(\.title)).count == 9)
}
