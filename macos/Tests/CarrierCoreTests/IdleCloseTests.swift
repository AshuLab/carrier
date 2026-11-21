import Foundation
import Testing
@testable import CarrierCore

private func object(_ data: Data?) throws -> [String: Any] {
    try #require(data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any])
}

@Test func theIdleCloseIsTheFilesAndTenMinutesWhenItHasNoneOrAWrongOne() {
    func close(_ json: String?) -> IdleClose { idleClose(chatJSON: json.map { Data($0.utf8) }) }
    #expect(close(nil) == .tenMinutes && close("{}") == .tenMinutes)
    #expect(close(#"{"idleCloseMinutes":30}"#) == .thirtyMinutes && close(#"{"idleCloseMinutes":60}"#) == .oneHour && close(#"{"idleCloseMinutes":10}"#) == .tenMinutes)
    // what the host would refuse is not what it uses: the row shows the default
    for wrong in ["0", "5", "15", "120", #""30""#, "30.5", "null", "true", "[]"] { #expect(close(#"{"idleCloseMinutes":\#(wrong)}"#) == .tenMinutes, Comment(rawValue: wrong)) }
    #expect(close("nope") == .tenMinutes && close("[1]") == .tenMinutes)
}

@Test func theChoicesAreTheThreeTheHostAcceptsInOrderWithTheirWords() {
    #expect(IdleClose.allCases.map(\.rawValue) == [10, 30, 60])
    #expect(IdleClose.allCases.map(\.title) == ["10 minutes", "30 minutes", "1 hour"])
}

@Test func changingTheIdleCloseKeepsTheOtherKeysAndLeavesTheDefaultOut() throws {
    let file = Data(#"{"agents":{"a":{"harness":"claude"}},"archiveAfterDays":5,"idleCloseMinutes":60}"#.utf8)
    let ten = try object(applyingIdleClose(.tenMinutes, to: file))
    #expect(ten["idleCloseMinutes"] == nil && ten["archiveAfterDays"] as? Int == 5 && ten["agents"] != nil)
    let thirty = try object(applyingIdleClose(.thirtyMinutes, to: Data(#"{"logLevel":"debug"}"#.utf8)))
    #expect(thirty as NSDictionary == ["logLevel": "debug", "idleCloseMinutes": 30])
    #expect(try object(applyingIdleClose(.oneHour, to: nil)) as NSDictionary == ["idleCloseMinutes": 60])
    #expect(try object(applyingIdleClose(.tenMinutes, to: nil)).isEmpty)
    #expect(idleClose(chatJSON: applyingIdleClose(.oneHour, to: file)) == .oneHour)
}

@Test func theIdleCloseIsNotWrittenOverAFileThatCannotBeRead() {
    #expect(applyingIdleClose(.oneHour, to: Data("[1]".utf8)) == nil && applyingIdleClose(.oneHour, to: Data("nope".utf8)) == nil)
}
