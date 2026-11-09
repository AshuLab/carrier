import Foundation
import Testing

@testable import CarrierCore

private func decode(_ extra: String) throws -> ChatSession {
    try JSONDecoder().decode(ChatSession.self, from: Data("""
        {"id":"s1","agent":"claude","harness":"claude","folder":"/Users/dev/web","title":"Fix login","state":"idle","createdAt":1,"lastActiveAt":2,
         "archived":false,"live":false\(extra)}
        """.utf8))
}

@Test func aSessionRowCarriesWhatTheHostSaysOfHowItWent() throws {
    let row = sessionRows([try decode(#","lastMessage":"Fixed it","turns":3,"model":"claude-haiku-5-5""#)])[0]
    #expect(row.lastMessage == "Fixed it" && row.turns == 3 && row.model == "claude-haiku-5-5")
}

@Test func aHostOrAReplyThatLeavesThemOutGivesNoMessageNoTurnsNoModel() throws {
    let row = sessionRows([try decode("")])[0]
    #expect(row.lastMessage == nil && row.turns == 0 && row.model == nil)
    let unanswered = sessionRows([try decode(#","lastMessage":null,"turns":0,"model":null"#)])[0]
    #expect(unanswered.lastMessage == nil)
}
