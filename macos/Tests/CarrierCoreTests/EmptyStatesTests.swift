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

@Test func slicesUnavailableHasItsOwnIconTitleAndLine() {
    let cases: [SlicesUnavailable] = [.notShared, .notReadYet]
    #expect(Set(cases.map(\.title)).count == 2 && Set(cases.map(\.icon)).count == 2)
    #expect(cases.allSatisfy { $0.line.isEmpty == false && $0.line.contains("\n") == false })
}
