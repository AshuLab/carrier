import Foundation
import Testing
@testable import CarrierCore

// The words of the ring beside a conversation's microphone: its tooltip and what VoiceOver reads.

private func usage(five: Double? = nil, weekly: Double? = nil, monthly: Double? = nil, stale: Bool = false) -> AccountUsage {
    AccountUsage(five: five.map { MeterShape(hatched: $0) }, weekly: weekly.map { MeterShape(hatched: $0) }, monthly: monthly.map { MeterShape(hatched: $0) }, reset: nil, stale: stale)
}

@Test func theInnerRingFollowsTheFiveHourWindowAndOtherwiseTheLongestOneTheAccountHas() {
    #expect(usage(five: 0.3, weekly: 0.6).ringWindow?.kind == .fiveHour)
    #expect(usage(weekly: 0.6, monthly: 0.1).ringWindow?.kind == .weekly)
    #expect(usage(monthly: 0.1).ringWindow?.kind == .monthly)
    #expect(usage().ringWindow == nil)
}

@Test func theRingInWordsNamesTheWindowItShowsNotAlwaysTheFiveHourOne() {
    let context = ContextUse(tokens: 46_800, window: 200_000)
    #expect(contextRingWords(context: context, usage: usage(five: 0.42), bundle: english.bundle, locale: english.locale) == "Context 23% · 5h 42%")
    // an account with no 5h window must not read "5h"
    #expect(contextRingWords(context: context, usage: usage(weekly: 0.63), bundle: english.bundle, locale: english.locale) == "Context 23% · Weekly 63%")
    #expect(contextRingWords(context: context, usage: nil, bundle: english.bundle, locale: english.locale) == "Context 23%")
    #expect(contextRingWords(context: nil, usage: usage(five: 0.42), bundle: english.bundle, locale: english.locale) == "5h 42%")
    #expect(contextRingWords(context: ContextUse(tokens: 5), usage: nil, bundle: english.bundle, locale: english.locale) == "Context and usage limits")
    #expect(contextRingWords(context: nil, usage: nil, bundle: english.bundle, locale: english.locale) == "Context and usage limits")
}

@Test func whatTheColorAndTheDimmingSayIsSaidInWordsToo() {
    let near = ContextUse(tokens: 186_000, window: 200_000)
    #expect(contextRingWords(context: near, usage: usage(five: 0.94), bundle: english.bundle, locale: english.locale) == "Context 93%, near the limit · 5h 94%, near the limit")
    // exactly 90 % is orange, as on the Usage page's bars; just under is not
    #expect(contextRingWords(context: ContextUse(tokens: 90, window: 100), usage: nil, bundle: english.bundle, locale: english.locale) == "Context 90%, near the limit")
    #expect(contextRingWords(context: ContextUse(tokens: 89, window: 100), usage: nil, bundle: english.bundle, locale: english.locale) == "Context 89%")
    #expect(contextRingWords(context: nil, usage: usage(five: 0.28, stale: true), bundle: english.bundle, locale: english.locale) == "5h 28% · limits last known")
}

@Test func theMetersOfThePopoverSayWhyTheyAreMissing() throws {
    let signedOut = try JSONDecoder().decode(UsageQuota.self, from: Data(#"{"account":"claude-work","displayName":"Work","provider":"claude","status":"signed_out"}"#.utf8))
    let bare = try JSONDecoder().decode(UsageQuota.self, from: Data(#"{"account":"claude-x","provider":"claude","status":"signed_out"}"#.utf8))
    let local = try JSONDecoder().decode(UsageQuota.self, from: Data(#"{"account":"local","provider":"local","status":"ok"}"#.utf8))
    func why(_ account: String, _ quotas: [UsageQuota] = [], failed: Bool = false, checking: Bool = false) -> String {
        contextLimitsWords(account: account, quotas: quotas, failed: failed, checking: checking, bundle: english.bundle, locale: english.locale)
    }
    #expect(why("claude-work", [signedOut, local]) == "Work is signed out." && why("claude-x", [bare]) == "claude-x is signed out.")
    #expect(why("local", [signedOut, local]) == "No limits to show for this account.")
    // a failed ask is not "still checking"
    #expect(why("nobody", failed: true) == "The limits could not be read. Open Usage to see why.")
    #expect(why("nobody", checking: true) == "Checking the limits…")
    #expect(why("nobody") == "No limits to show for this account.")
}
