import Testing
@testable import CarrierCore

@Test func thereAreSixteenEmptyStatesEachWithAnIconATitleAndOneLine() {
    #expect(EmptyState.allCases.count == 16)
    for state in EmptyState.allCases {
        #expect(state.title(bundle: english.bundle, locale: english.locale).isEmpty == false)
        #expect(state.line(bundle: english.bundle, locale: english.locale).isEmpty == false)
        #expect(state.line(bundle: english.bundle, locale: english.locale).contains("\n") == false)
    }
}

@Test func noTwoEmptyStatesShareAnIconOrATitle() {
    #expect(Set(EmptyState.allCases.map(\.icon)).count == 16)
    #expect(Set(EmptyState.allCases.map { $0.title(bundle: english.bundle, locale: english.locale) }).count == 16)
}

@Test func slicesUnavailableHasItsOwnIconTitleAndLine() {
    let cases: [SlicesUnavailable] = [.notShared, .notReadYet]
    #expect(Set(cases.map { $0.title(bundle: english.bundle, locale: english.locale) }).count == 2 && Set(cases.map(\.icon)).count == 2)
    #expect(cases.allSatisfy {
        let line = $0.line(bundle: english.bundle, locale: english.locale)
        return line.isEmpty == false && line.contains("\n") == false
    })
}

@Test func theSessionsHomeHasAnEmptyStateForNoSessionsAndOneForNoMatches() {
    #expect((EmptyState.noSessions.title(bundle: english.bundle, locale: english.locale), EmptyState.noSessions.line(bundle: english.bundle, locale: english.locale)) == ("No sessions yet", "Sessions you start are listed here."))
    #expect(EmptyState.noSessionsMatch.title(bundle: english.bundle, locale: english.locale) == "No sessions match")
}

@Test func noEpicsHasItsOwnIconTitleAndALineThatNamesTheLabelThatStartsOne() {
    #expect(EmptyState.noEpics.title(bundle: english.bundle, locale: english.locale) == "No epics yet")
    #expect(EmptyState.noEpics.line(bundle: english.bundle, locale: english.locale).contains("solve:epic:ready"))
    #expect(EmptyState.allCases.filter { $0.icon == EmptyState.noEpics.icon }.count == 1)
}

@Test func noTerminalsHasItsOwnIconTitleAndLine() {
    #expect((EmptyState.noTerminals.icon, EmptyState.noTerminals.title(bundle: english.bundle, locale: english.locale), EmptyState.noTerminals.line(bundle: english.bundle, locale: english.locale)) == (
        .terminal,
        "No terminals yet",
        "Terminal sessions you start are listed here."
    ))
}
