import Testing
@testable import CarrierCore

@Test func thereAreFifteenEmptyStatesEachWithAnIconATitleAndOneLine() {
    #expect(EmptyState.allCases.count == 15)
    for state in EmptyState.allCases {
        #expect(state.icon.isEmpty == false)
        #expect(state.title.isEmpty == false)
        #expect(state.line.isEmpty == false)
        #expect(state.line.contains("\n") == false)
    }
}

@Test func noTwoEmptyStatesShareAnIconOrATitle() {
    #expect(Set(EmptyState.allCases.map(\.icon)).count == 15)
    #expect(Set(EmptyState.allCases.map(\.title)).count == 15)
}

@Test func slicesUnavailableHasItsOwnIconTitleAndLine() {
    let cases: [SlicesUnavailable] = [.notShared, .notReadYet]
    #expect(Set(cases.map(\.title)).count == 2 && Set(cases.map(\.icon)).count == 2)
    #expect(cases.allSatisfy { $0.line.isEmpty == false && $0.line.contains("\n") == false })
}

@Test func theSessionsHomeHasAnEmptyStateForNoSessionsAndOneForNoMatches() {
    #expect((EmptyState.noSessions.title, EmptyState.noSessions.line) == ("No sessions yet", "Sessions you start are listed here."))
    #expect(EmptyState.noSessionsMatch.title == "No sessions match")
}

@Test func noEpicsHasItsOwnIconTitleAndALineThatNamesTheLabelThatStartsOne() {
    #expect(EmptyState.noEpics.title == "No epics yet")
    #expect(EmptyState.noEpics.line.contains("solve:epic:ready"))
    #expect(EmptyState.allCases.filter { $0.icon == EmptyState.noEpics.icon }.count == 1)
}
