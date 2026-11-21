import Testing
@testable import CarrierCore

// The words of the ring beside a conversation's microphone: its tooltip and what VoiceOver reads.

private func usage(five: Double? = nil, weekly: Double? = nil, monthly: Double? = nil, stale: Bool = false) -> AccountUsage {
    AccountUsage(five: five.map { MeterShape(hatched: $0) }, weekly: weekly.map { MeterShape(hatched: $0) }, monthly: monthly.map { MeterShape(hatched: $0) }, reset: nil, stale: stale)
}

@Test func theInnerRingFollowsTheFiveHourWindowAndOtherwiseTheLongestOneTheAccountHas() {
    #expect(usage(five: 0.3, weekly: 0.6).ringWindow?.name == "5h")
    #expect(usage(weekly: 0.6, monthly: 0.1).ringWindow?.name == "Weekly")
    #expect(usage(monthly: 0.1).ringWindow?.name == "Monthly")
    #expect(usage().ringWindow == nil)
}

@Test func theRingInWordsNamesTheWindowItShowsNotAlwaysTheFiveHourOne() {
    let context = ContextUse(tokens: 46_800, window: 200_000)
    #expect(contextRingWords(context: context, usage: usage(five: 0.42)) == "Context 23% · 5h 42%")
    // an account with no 5h window must not read "5h"
    #expect(contextRingWords(context: context, usage: usage(weekly: 0.63)) == "Context 23% · Weekly 63%")
    #expect(contextRingWords(context: context, usage: nil) == "Context 23%")
    #expect(contextRingWords(context: nil, usage: usage(five: 0.42)) == "5h 42%")
    #expect(contextRingWords(context: ContextUse(tokens: 5), usage: nil) == "Context and usage limits")
    #expect(contextRingWords(context: nil, usage: nil) == "Context and usage limits")
}

@Test func whatTheColorAndTheDimmingSayIsSaidInWordsToo() {
    let near = ContextUse(tokens: 186_000, window: 200_000)
    #expect(contextRingWords(context: near, usage: usage(five: 0.94)) == "Context 93%, near the limit · 5h 94%, near the limit")
    // exactly 90 % is orange, as on the Usage page's bars; just under is not
    #expect(contextRingWords(context: ContextUse(tokens: 90, window: 100), usage: nil) == "Context 90%, near the limit")
    #expect(contextRingWords(context: ContextUse(tokens: 89, window: 100), usage: nil) == "Context 89%")
    #expect(contextRingWords(context: nil, usage: usage(five: 0.28, stale: true)) == "5h 28% · limits last known")
}
