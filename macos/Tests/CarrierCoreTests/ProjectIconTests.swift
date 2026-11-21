import Foundation
import Testing
@testable import CarrierCore

@Test func theInitialsAreCapitalsOfTheFirstThreeWordsOrTheFirstTwoLetters() {
    #expect(projectInitials("carrier") == "CA")
    #expect(projectInitials("ashu-lab") == "AL")
    #expect(projectInitials("my_cool project") == "MCP")
    #expect(projectInitials("fury_invest-returns-cross") == "FIR")
    #expect(projectInitials("fury_investment-news") == "FIN")
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

@Test func theTileOffersEightColoursAndEightExistingAppIcons() {
    #expect(ProjectColor.allCases.count == 8)
    #expect(projectIconMarks.count == 8)
    #expect(Set(projectIconMarks).count == 8)
    #expect(projectIconMarks.map(\.rawValue) == ["code", "terminal", "cube", "book", "home", "bolt", "brain", "star"])
}

@Test func theTileUsesChosenColourAndMarkOrFallsBackToInitialsAndHashedColour() throws {
    let entries = try readProjects(Data(#"""
    {"projects":[
      {"path":"~/work/carrier","origin":"cloned","name":"Carrier App","icon":{"color":"teal","mark":"bolt","image":"c.png"}},
      {"path":"/a/notes","origin":"added","icon":{"color":"orange"}},
      {"path":"/a/plain","origin":"added"}
    ]}
    """#.utf8))

    let chosen = projectTile(path: NSHomeDirectory() + "/work/carrier", in: entries)
    #expect(chosen == ProjectTile(name: "Carrier App", color: .named(.teal), content: .mark(.bolt), image: "c.png"))

    let colorOnly = projectTile(path: "/a/notes", in: entries)
    #expect(colorOnly == ProjectTile(name: "notes", color: .named(.orange), content: .initials("NO"), image: nil))

    let defaultTile = projectTile(path: "/a/plain", in: entries)
    #expect(defaultTile == ProjectTile(name: "plain", color: .hashed(projectColorIndex("plain", count: 24)), content: .initials("PL"), image: nil))

    let unlisted = projectTile(path: "/tmp/other-repo", in: entries)
    #expect(unlisted == ProjectTile(name: "other-repo", color: .hashed(projectColorIndex("other-repo", count: 24)), content: .initials("OR"), image: nil))
}

@Test func theTileIgnoresUnknownColourOrMarkNames() throws {
    let entries = try readProjects(Data(#"{"projects":[{"path":"/a/app","origin":"added","icon":{"color":"chartreuse","mark":"not-an-icon"}}]}"#.utf8))
    let tile = projectTile(path: "/a/app", in: entries)
    #expect(tile == ProjectTile(name: "app", color: .hashed(projectColorIndex("app", count: 24)), content: .initials("AP"), image: nil))
}
