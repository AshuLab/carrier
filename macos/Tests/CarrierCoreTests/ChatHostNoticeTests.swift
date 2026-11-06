import Testing
@testable import CarrierCore

@Test func nothingMissingIsNoNotice() {
    #expect(chatHostNotice(missing: []) == nil)
}

@Test func theNoticeNamesWhatIsMissingAndWhereToFixIt() throws {
    let one = try #require(chatHostNotice(missing: ["carrier"]))
    #expect(one.title == "The chat host cannot start")
    #expect(one.line == "The app did not find carrier. Run brew install ashulab/tap/carrier in Terminal.")
    let both = try #require(chatHostNotice(missing: ["node", "carrier"]))
    #expect(both.line.contains("node and carrier") && both.line.contains("brew install ashulab/tap/carrier"))
    #expect(try #require(chatHostNotice(missing: ["node"])).line.contains("brew") == false)
}
