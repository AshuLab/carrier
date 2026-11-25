import Foundation
import Testing
@testable import CarrierCore

// The app's reading of projects.json (docs/adr/0041): a file that does not match is reported with the field. The writing is the host's (src/chat/project-edits.ts); the model's
// requests are checked here against the fixture host's code.

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

@Test func aFileThatDoesNotMatchIsReportedWithTheField() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let file = ProjectsFile(folder: folder)
    #expect(try file.read().isEmpty)
    let bad = #"{"projects":[{"path":"/a","origin":"added","colour":"red"}]}"#
    try Data(bad.utf8).write(to: file.url)
    #expect(throws: ProjectsFileError.invalid([ProjectsProblem(path: "projects.0.colour", message: "is not a key of projects.json")])) { try file.read(bundle: english.bundle, locale: english.locale) }
}

@MainActor @Test func theModelWritesADefaultAndTakesItOutAgain() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    try Data(twoProjects.utf8).write(to: URL(fileURLWithPath: folder + "/projects.json"))
    let model = ProjectsModel(host: CloneHost(writing: folder), file: ProjectsFile(folder: folder)) { _ in nil }
    model.reload()
    #expect(await model.setDefault(.agent, "claude", path: "/a") && model.rows[0].defaults.agent == "claude" && model.rows[0].defaults.workIn == .newWorktree)
    #expect(await model.setDefault(.agent, nil, path: "/a") && model.rows[0].defaults.agent == nil)
}

@MainActor @Test func theStartOfAProjectIsWrittenWithItsAgentAndTakenOutWithoutOne() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    try Data(twoProjects.utf8).write(to: URL(fileURLWithPath: folder + "/projects.json"))
    let model = ProjectsModel(host: CloneHost(writing: folder), file: ProjectsFile(folder: folder)) { _ in nil }
    model.reload()
    let start = NewSessionStart(agent: "claude", model: "haiku", effort: "high", access: ["permissionMode": "acceptEdits"])
    #expect(await model.setStart(start, path: "/a"))
    #expect(model.rows[0].defaults == ProjectDefaults(agent: "claude", model: "haiku", effort: "high", access: ["permissionMode": "acceptEdits"], workIn: .newWorktree))
    // another provider's values are not kept; with no agent nothing of the start is, and workIn stays
    #expect(await model.setStart(NewSessionStart(agent: "", model: "haiku", effort: "high"), path: "/a"))
    #expect(model.rows[0].defaults == ProjectDefaults(workIn: .newWorktree))
}
