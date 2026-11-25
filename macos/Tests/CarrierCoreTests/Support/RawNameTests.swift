import Testing
@testable import CarrierCore

@Test func aValueWithNoWordsShowsByItsOwnNameWithACapitalFirstLetter() {
    #expect(capitalizingFirst("review") == "Review" && capitalizingFirst("timed out") == "Timed Out" && capitalizingFirst("CLI") == "CLI" && capitalizingFirst("") == "")
}

@Test func anOutcomeAndAStageTheAppDoesNotKnowKeepTheOneFormOfFallback() {
    let unknown = resultCard(SessionResult(outcome: "timed_out", summary: "s", verification: nil, reason: nil), bundle: english.bundle, locale: english.locale)
    #expect(unknown?.outcome == "Timed Out" && unknown?.tone == .warning)
    #expect(AccentColor(rawValue: "blue")?.title(bundle: english.bundle, locale: english.locale) == "Blue")
}
