import Foundation
import Testing
@testable import CarrierCore

// The app's writing of projects.json (docs/adr/0041): one field of one entry changed, every other entry and key kept, the file written whole,
// a file that does not match reported with the field and never written over.

private func temporaryFolder() throws -> String {
    let folder = NSTemporaryDirectory() + "carrier-projects-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    return folder
}

private let twoProjects = #"""
{"projects":[
 {"path":"/a","origin":"cloned","name":"A","icon":{"color":"teal","image":"a.png"},"defaults":{"workIn":"worktree"},"actions":[{"name":"Install","command":"pnpm i","when":"newWorktree","onFail":"stop"}]},
 {"path":"~/b","origin":"added","tags":["x","y"],"hidden":true}
]}
"""#

@Test func editingOneFieldOfOneEntryKeepsEveryOtherEntryAndEveryOtherKeyOfIt() throws {
    let updated = try applyingProjectEdit(path: "/a", key: "pinned", value: true, to: Data(twoProjects.utf8))
    let before = try JSONSerialization.jsonObject(with: Data(twoProjects.utf8)) as! [String: Any]
    let after = try JSONSerialization.jsonObject(with: updated) as! [String: Any]
    var expected = (before["projects"] as! [[String: Any]])
    expected[0]["pinned"] = true
    #expect(NSArray(array: after["projects"] as! [Any]).isEqual(to: expected))
    let entries = try readProjects(updated)
    #expect(entries.map(\.path) == ["/a", "~/b"] && entries[0].pinned && entries[1].tags == ["x", "y"] && entries[1].hidden)
}

@Test func aNilValueTakesTheKeyOutAndNothingElse() throws {
    let updated = try applyingProjectEdit(path: "~/b", key: "hidden", value: nil, to: Data(twoProjects.utf8))
    let entries = try readProjects(updated)
    #expect(entries[1].json["hidden"] == nil && entries[1].tags == ["x", "y"] && entries[0].json["actions"] != nil)
}

@Test func anEditThatWouldMakeTheFileInvalidThrowsNamingTheFieldAndAMissingProjectIsSaid() {
    #expect(throws: ProjectsFileError.invalid([ProjectsProblem(path: "projects.0.name", message: "must not be blank")])) {
        try applyingProjectEdit(path: "/a", key: "name", value: " ", to: Data(twoProjects.utf8))
    }
    #expect(throws: ProjectsFileError.missing("/zzz")) { try applyingProjectEdit(path: "/zzz", key: "pinned", value: true, to: Data(twoProjects.utf8)) }
    #expect(throws: ProjectsFileError.missing("/a")) { try applyingProjectEdit(path: "/a", key: "pinned", value: true, to: nil) }
}

@Test func aFileThatDoesNotMatchIsReportedWithTheFieldAndTheFileIsLeftAsItWas() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let file = ProjectsFile(folder: folder)
    #expect(try file.read().isEmpty)
    let bad = #"{"projects":[{"path":"/a","origin":"added","colour":"red"}]}"#
    try Data(bad.utf8).write(to: file.url)
    #expect(throws: ProjectsFileError.invalid([ProjectsProblem(path: "projects.0.colour", message: "is not a key of projects.json")])) { try file.read() }
    #expect(throws: ProjectsFileError.self) { try file.update(path: "/a", key: "pinned", value: true) }
    #expect(try String(contentsOf: file.url, encoding: .utf8) == bad)
}

@Test func theFileIsWrittenWholeAndRereadBeforeEachEdit() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let file = ProjectsFile(folder: folder)
    try Data(twoProjects.utf8).write(to: file.url)
    try file.update(path: "/a", key: "pinned", value: true)
    // another writer (the host) adds a project between two edits of the app: the second edit keeps it
    var object = try JSONSerialization.jsonObject(with: Data(contentsOf: file.url)) as! [String: Any]
    object["projects"] = (object["projects"] as! [[String: Any]]) + [["path": "/c", "origin": "created"]]
    try JSONSerialization.data(withJSONObject: object).write(to: file.url)
    try file.update(path: "~/b", key: "pinned", value: true)
    let entries = try file.read()
    #expect(entries.map(\.path) == ["/a", "~/b", "/c"] && entries.map(\.pinned) == [true, true, false])
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder) == ["projects.json"])
}

@Test func iconAndTagEditsKeepEveryOtherKeyAndSubkey() throws {
    let withMark = try applyingProjectIconEdit(path: "/a", changes: ["mark": "bolt", "color": "blue"], to: Data(twoProjects.utf8))
    var entries = try readProjects(withMark)
    #expect(entries[0].iconColor == "blue" && entries[0].iconMark == "bolt" && entries[0].iconImage == "a.png")
    #expect(entries[0].json["defaults"] != nil && entries[0].json["actions"] != nil && entries[0].name == "A")
    #expect(entries[1].tags == ["x", "y"] && entries[1].hidden)

    // clearing colour and mark keeps image; clearing everything on an entry with no image drops the icon key
    let cleared = try applyingProjectIconEdit(path: "/a", changes: ["color": nil, "mark": nil], to: withMark)
    entries = try readProjects(cleared)
    #expect(entries[0].iconColor == nil && entries[0].iconMark == nil && entries[0].iconImage == "a.png")

    let secondWithIcon = try applyingProjectIconEdit(path: "~/b", changes: ["color": "red"], to: cleared)
    let secondCleared = try applyingProjectIconEdit(path: "~/b", changes: ["color": nil], to: secondWithIcon)
    #expect(try readProjects(secondCleared)[1].json["icon"] == nil)

    // tag edits keep every other key and remove the tags key when empty
    let tagged = try applyingProjectTagsEdit(path: "/a", to: cleared) { $0 + ["  Swift ", "MACOS", "swift"] }
    entries = try readProjects(tagged)
    #expect(entries[0].tags == ["swift", "macos"] && entries[0].iconImage == "a.png" && entries[0].json["actions"] != nil)

    let untagged = try applyingProjectTagsEdit(path: "/a", to: tagged) { _ in [] }
    #expect(try readProjects(untagged)[0].json["tags"] == nil)
}

@Test func defaultsRoundTripThroughTheFileKeepingEveryOtherKeyAndAValueOnTheDefaultWritesNothing() throws {
    // a value is written under `defaults` and read back; the other keys of the entry and of `defaults` stay
    let set = try applyingProjectDefaultsEdit(path: "/a", changes: ["agent": "claude", "baseBranch": "develop"], to: Data(twoProjects.utf8))
    var entries = try readProjects(set)
    #expect(entries[0].defaults == ProjectDefaults(agent: "claude", workIn: .newWorktree, baseBranch: "develop"))
    #expect(entries[0].iconImage == "a.png" && entries[0].actions.count == 1 && entries[1].hidden)
    // a value left on the default takes its key out, and `defaults` goes with the last one; an entry with none has none
    let base = try applyingProjectDefaultsEdit(path: "/a", changes: ["workIn": "baseFolder"], to: set)
    #expect(try readProjects(base)[0].defaults.workIn == .baseFolder)
    let cleared = try applyingProjectDefaultsEdit(path: "/a", changes: ["agent": nil, "workIn": nil, "baseBranch": nil], to: base)
    entries = try readProjects(cleared)
    #expect(entries[0].json["defaults"] == nil && entries[0].defaults == ProjectDefaults() && entries[0].name == "A")
    #expect(try readProjects(Data(twoProjects.utf8))[1].json["defaults"] == nil)
    // a value the schema does not know is refused and nothing is written
    #expect(throws: ProjectsFileError.self) { try applyingProjectDefaultsEdit(path: "/a", changes: ["workIn": "elsewhere"], to: Data(twoProjects.utf8)) }
}

@MainActor @Test func theModelWritesADefaultAndTakesItOutAgain() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    try Data(twoProjects.utf8).write(to: URL(fileURLWithPath: folder + "/projects.json"))
    let model = ProjectsModel(file: ProjectsFile(folder: folder)) { _ in nil }
    model.reload()
    #expect(model.setDefault(.agent, "claude", path: "/a") && model.rows[0].defaults.agent == "claude" && model.rows[0].defaults.workIn == .newWorktree)
    #expect(model.setDefault(.agent, nil, path: "/a") && model.rows[0].defaults.agent == nil)
}
