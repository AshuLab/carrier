import Testing
@testable import CarrierCore

@Test func theInitialsAreCapitalsOfTheFirstTwoWordsOrTheFirstTwoLetters() {
    #expect(projectInitials("carrier") == "CA")
    #expect(projectInitials("ashu-lab") == "AL")
    #expect(projectInitials("my_cool project") == "MC")
    #expect(projectInitials("web") == "WE")
    #expect(projectInitials("x") == "X")
    #expect(projectInitials("dev/carrier") == "CA")
    #expect(projectInitials("") == "?")
}

@Test func aProjectHasTheSameColourEveryTimeAndItIsInRange() {
    let a = projectColorIndex("/Users/dev/carrier", count: 8)
    #expect(a == projectColorIndex("/Users/dev/carrier", count: 8))
    #expect((0..<8).contains(a))
    #expect(Set(["/a/web", "/a/api", "/a/carrier", "/a/docs", "/a/site", "/a/tools"].map { projectColorIndex($0, count: 8) }).count > 2)
    #expect(projectColorIndex("/x", count: 0) == 0)
}
