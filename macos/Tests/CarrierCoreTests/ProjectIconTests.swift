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

private func projectRowList(_ json: String) throws -> [ProjectRow] {
    projectRows(try readProjects(Data(json.utf8)), remote: { $0 == "/a/app" ? "acme/app" : nil })
}

@Test func theIdentityUsesTheProjectsNameColourMarkAndImageOrFallsBackToTheFolders() throws {
    let projects = try projectRowList(#"""
    {"projects":[
      {"path":"~/work/carrier","origin":"cloned","name":"Carrier App","icon":{"color":"teal","mark":"bolt","image":"c.png"}},
      {"path":"/a/notes","origin":"added","icon":{"color":"orange"}},
      {"path":"/a/plain","origin":"added"}
    ]}
    """#)

    let chosen = projectIdentity(path: NSHomeDirectory() + "/work/carrier", in: projects)
    #expect(chosen.tile == ProjectTile(name: "Carrier App", color: .named(.teal), content: .mark(.bolt), image: "c.png"))
    #expect(chosen.title == "Carrier App")

    let colorOnly = projectIdentity(path: "/a/notes", in: projects)
    #expect(colorOnly.tile == ProjectTile(name: "notes", color: .named(.orange), content: .initials("NO"), image: nil))

    // a project with nothing set and a folder that is not a project look the same: the folder's name and a colour made from it
    let plain = projectIdentity(path: "/a/plain", in: projects)
    let unlisted = projectIdentity(path: "/tmp/plain", in: projects)
    #expect(plain == unlisted)
    #expect(plain == ProjectIdentity(tile: projectTile(name: "plain", colorKey: "plain"), title: "plain"))
    #expect(plain.tile == ProjectTile(name: "plain", color: .hashed(projectColorIndex("plain", count: 24)), content: .initials("PL"), image: nil))
}

@Test func theIdentityIgnoresUnknownColourOrMarkNames() throws {
    let projects = try projectRowList(#"{"projects":[{"path":"/a/app","origin":"added","icon":{"color":"chartreuse","mark":"not-an-icon"}}]}"#)
    #expect(projectIdentity(path: "/a/app", in: projects).tile == ProjectTile(name: "app", color: .hashed(projectColorIndex("app", count: 24)), content: .initials("AP"), image: nil))
}

@Test func anEpicsRepositoryTakesTheIdentityOfTheProjectWhoseOriginItIs() throws {
    let projects = try projectRowList(#"{"projects":[{"path":"/a/app","origin":"added","name":"The App","icon":{"color":"blue","image":"a.png"}}]}"#)
    #expect(projectIdentity(repo: "Acme/App", in: projects)?.tile == ProjectTile(name: "The App", color: .named(.blue), content: .initials("TA"), image: "a.png"))
    #expect(projectIdentity(repo: "acme/other", in: projects) == nil)
    #expect(projectIdentity(repo: "acme/app", in: []) == nil)
}
