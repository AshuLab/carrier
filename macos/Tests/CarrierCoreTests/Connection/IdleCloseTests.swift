import Foundation
import Testing
@testable import CarrierCore

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

