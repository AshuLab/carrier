import Foundation
import Testing
@testable import CarrierCore

// The Projects page's list: the remote read from the repository, the rows, adding a folder, and the model that follows the file.

private func temporaryFolder() throws -> String {
    let folder = NSTemporaryDirectory() + "carrier-projects-list-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    return folder
}

@Test func aGitHubRemoteIsReadInEveryFormGitUses() {
    for url in ["git@github.com:AshuLab/carrier.git", "https://github.com/AshuLab/carrier", "https://github.com/AshuLab/carrier.git/", "ssh://git@github.com/AshuLab/carrier.git", "https://me@github.com/AshuLab/carrier.git"] {
        #expect(gitHubRepo(fromRemote: url) == "AshuLab/carrier", Comment(rawValue: url))
    }
    for url in ["git@gitlab.com:a/b.git", "https://github.com/AshuLab", "https://github.com/a/b/c", "/Users/me/other", "", "https://example.com/github.com/a/b"] {
        #expect(gitHubRepo(fromRemote: url) == nil, Comment(rawValue: url))
    }
}

@Test func theRemoteIsReadFromTheOriginOfTheRepositoryAndFromNoOtherRemote() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    #expect(originRepo(ofFolder: folder) == nil)
    try FileManager.default.createDirectory(atPath: folder + "/.git", withIntermediateDirectories: true)
    try Data("[remote \"upstream\"]\n\turl = git@github.com:other/thing.git\n[remote \"origin\"]\n\turl = git@github.com:AshuLab/carrier.git\n\tfetch = x\n".utf8).write(to: URL(fileURLWithPath: folder + "/.git/config"))
    #expect(originRepo(ofFolder: folder) == "AshuLab/carrier")
    try Data("[remote \"upstream\"]\n\turl = git@github.com:other/thing.git\n".utf8).write(to: URL(fileURLWithPath: folder + "/.git/config"))
    #expect(originRepo(ofFolder: folder) == nil)
    try Data("[remote \"origin\"]\n\turl = git@gitlab.com:a/b.git\n".utf8).write(to: URL(fileURLWithPath: folder + "/.git/config"))
    #expect(originRepo(ofFolder: folder) == nil)
}

@Test func aRowIsNamedAfterItsFolderAndSaysItsRepositoryOrElseItsPath() throws {
    let entries = try readProjects(Data(#"{"projects":[{"path":"/a/web","origin":"added"},{"path":"~/b","name":"Bee","origin":"cloned"}]}"#.utf8))
    let rows = projectRows(entries) { $0 == "~/b" ? "ana/bee" : nil }
    #expect(rows.map(\.name) == ["web", "Bee"])
    #expect(rows.map(\.line) == ["/a/web", "ana/bee"])
    #expect(rows.map(\.colorKey) == ["web", "b"])
    #expect(projectRows([]).isEmpty)
}

@Test func theProblemsOfTheFileAreSaidWithTheFieldNamed() {
    #expect(ProjectsProblem(path: "projects.1.name", message: "must not be blank").text == "projects.json: projects.1.name must not be blank")
    #expect(ProjectsProblem(path: "(file)", message: "is not valid JSON").text == "projects.json is not valid JSON")
}

@Test func addingAFolderWritesAnAddedEntryNamedAfterItAndKeepsEverythingElse() throws {
    let before = Data(#"{"projects":[{"path":"/a","origin":"cloned","tags":["x"],"icon":{"image":"a.png"}}]}"#.utf8)
    let result = try applyingProjectAdd(folder: "/Users/ana/Notes", to: before)
    #expect(result.outcome == .added("/Users/ana/Notes"))
    let entries = try readProjects(try #require(result.write))
    #expect(entries.map(\.path) == ["/a", "/Users/ana/Notes"] && entries[1].name == "Notes" && entries[1].origin == "added")
    #expect(entries[0] == (try readProjects(before))[0])
    // no file at all is an empty list
    #expect(try readProjects(applyingProjectAdd(folder: "/x", to: nil).write).map(\.path) == ["/x"])
}

@Test func addingAFolderThatIsAlreadyAProjectWritesNothingWhateverHowItIsWritten() throws {
    let file = Data(#"{"projects":[{"path":"~/work/a","origin":"added"}]}"#.utf8)
    for folder in [NSHomeDirectory() + "/work/a", NSHomeDirectory() + "/work/a/", "~/work/a"] {
        let result = try applyingProjectAdd(folder: folder, to: file)
        #expect(result.outcome == .existing("~/work/a") && result.write == nil, Comment(rawValue: folder))
    }
}

@Test func aFileThatDoesNotMatchItsSchemaIsNeverWrittenOver() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let file = ProjectsFile(folder: folder)
    let bad = Data(#"{"projects":[{"path":"/a","origin":"added","name":""}]}"#.utf8)
    try bad.write(to: file.url)
    #expect(throws: ProjectsFileError.invalid([ProjectsProblem(path: "projects.0.name", message: "must not be blank")])) { try file.add(folder: "/b") }
    #expect(try Data(contentsOf: file.url) == bad)
}

@MainActor @Test func theModelListsTheFileAndAddsWithoutReopening() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let model = ProjectsModel(file: ProjectsFile(folder: folder)) { _ in nil }
    model.reload()
    #expect(model.rows.isEmpty && model.problems.isEmpty)
    #expect(model.add(folder: "/Users/ana/notes") == .added("/Users/ana/notes"))
    #expect(model.rows.map(\.name) == ["notes"])
    let written = try Data(contentsOf: ProjectsFile(folder: folder).url)
    #expect(model.add(folder: "/Users/ana/notes") == .existing("/Users/ana/notes"))
    #expect(try Data(contentsOf: ProjectsFile(folder: folder).url) == written)
}

@MainActor @Test func theModelFollowsAnotherProcessWritingTheFile() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let file = ProjectsFile(folder: folder)
    let model = ProjectsModel(file: file) { _ in nil }
    let following = Task { await model.follow(every: .milliseconds(10)) }
    defer { following.cancel() }
    func wait(_ done: () -> Bool) async { for _ in 0..<300 where done() == false { try? await Task.sleep(for: .milliseconds(10)) } }
    try Data(#"{"projects":[{"path":"/a/one","origin":"added"}]}"#.utf8).write(to: file.url, options: .atomic)
    await wait { model.rows.count == 1 }
    #expect(model.rows.map(\.name) == ["one"])
    try Data(#"{"projects":[{"path":"/a/one","origin":"added"},{"path":"/a/two","origin":"added"}]}"#.utf8).write(to: file.url, options: .atomic)
    await wait { model.rows.count == 2 }
    #expect(model.rows.map(\.name) == ["one", "two"])
    // a file that stops matching shows its problem and no rows; mended, the rows come back
    try Data(#"{"projects":[{"path":"/a/one","origin":"nope"}]}"#.utf8).write(to: file.url, options: .atomic)
    await wait { model.problems.isEmpty == false }
    #expect(model.rows.isEmpty && model.problems.map(\.path) == ["projects.0.origin"])
    try Data(#"{"projects":[]}"#.utf8).write(to: file.url, options: .atomic)
    await wait { model.problems.isEmpty }
    #expect(model.rows.isEmpty && model.problems.isEmpty)
}

@MainActor @Test func aFileThatDoesNotMatchBlocksAddAndTheModelWritesNothing() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let file = ProjectsFile(folder: folder)
    let bad = Data("{".utf8)
    try bad.write(to: file.url)
    let model = ProjectsModel(file: file) { _ in nil }
    model.reload()
    #expect(model.problems.map(\.message) == ["is not valid JSON"])
    #expect(model.add(folder: "/a") == nil)
    #expect(try Data(contentsOf: file.url) == bad)
}
