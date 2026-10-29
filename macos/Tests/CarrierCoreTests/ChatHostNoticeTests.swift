import Testing
@testable import CarrierCore

@Test func nothingMissingIsNoNotice() {
    #expect(chatHostNotice(missing: []) == nil)
}

@Test func theNoticeNamesWhatIsMissingAndWhereToFixIt() throws {
    let one = try #require(chatHostNotice(missing: ["carrier"]))
    #expect(one.title == "The chat host cannot start")
    #expect(one.line == "The app did not find carrier. Install it or set its path in Settings.")
    let both = try #require(chatHostNotice(missing: ["node", "carrier"]))
    #expect(both.line.contains("node and carrier"))
}
