import CoreGraphics
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
    let project = try temporaryFolder()
    defer {
        try? FileManager.default.removeItem(atPath: folder)
        try? FileManager.default.removeItem(atPath: project)
    }
    let model = ProjectsModel(file: ProjectsFile(folder: folder)) { _ in nil }
    model.reload()
    #expect(model.rows.isEmpty && model.problems.isEmpty)
    #expect(model.add(folder: project) == .added(project))
    #expect(model.rows.map(\.name) == [(project as NSString).lastPathComponent])
    let written = try Data(contentsOf: ProjectsFile(folder: folder).url)
    #expect(model.add(folder: project) == .existing(project))
    #expect(try Data(contentsOf: ProjectsFile(folder: folder).url) == written)
}

@MainActor @Test func addRefusesAFolderWhoseWorktreeDirectoryIsAnotherProjectsAndNamesIt() throws {
    let carrier = try temporaryFolder()
    let work = try temporaryFolder()
    defer {
        try? FileManager.default.removeItem(atPath: carrier)
        try? FileManager.default.removeItem(atPath: work)
    }
    for name in ["first", "second", "third"] { try FileManager.default.createDirectory(atPath: work + "/" + name, withIntermediateDirectories: true) }
    let repos = [work + "/first": "acme/app", work + "/second": "acme/app", work + "/third": "other/app"]
    let model = ProjectsModel(file: ProjectsFile(folder: carrier)) { repos[$0] }
    model.reload()
    #expect(model.add(folder: work + "/first") == .added(work + "/first"))
    #expect(model.add(folder: work + "/second") == nil)
    #expect(model.failure == "The worktrees of first already use the folder acme/app; two projects cannot share it")
    #expect(model.rows.map(\.name) == ["first"])
    #expect(model.add(folder: work + "/third") == .added(work + "/third"))
    // Locate…: the project being moved does not clash with itself
    #expect(model.addRefusal(folder: work + "/second", replacing: work + "/first") == nil)
    #expect(model.addRefusal(folder: work + "/second", replacing: nil) != nil)
}

@MainActor @Test func locateRefusesAFolderWhoseWorktreeDirectoryIsAnotherProjectsAndNamesIt() throws {
    let carrier = try temporaryFolder()
    let work = try temporaryFolder()
    defer {
        try? FileManager.default.removeItem(atPath: carrier)
        try? FileManager.default.removeItem(atPath: work)
    }
    let gone = work + "/gone", kept = work + "/kept", clash = work + "/clash", free = work + "/free"
    for folder in [kept, clash, free] { try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true) }
    let repos = [gone: "acme/app", kept: "acme/app", clash: "acme/app", free: "other/app"]
    let file = ProjectsFile(folder: carrier)
    try Data(#"{"projects":[{"path":"\#(gone)","origin":"cloned"},{"path":"\#(kept)","name":"Kept","origin":"added"}]}"#.utf8).write(to: file.url)
    let model = ProjectsModel(file: file) { repos[$0] }
    model.reload()
    #expect(model.locate(path: gone, to: clash) == false)
    #expect(model.failure == "The worktrees of Kept already use the folder acme/app; two projects cannot share it")
    #expect(model.rows.map(\.path) == [gone, kept])
    #expect(model.locate(path: gone, to: free))
    #expect(model.rows.map(\.path) == [free, kept])
}

@MainActor @Test func addRefusesFoldersThatCannotBeProjectsWithTheirReasonAndWritesNothing() throws {
    let carrier = try temporaryFolder()
    let work = try temporaryFolder()
    let unreadable = work + "/unreadable"
    defer {
        _ = chmod(unreadable, 0o755)
        try? FileManager.default.removeItem(atPath: carrier)
        try? FileManager.default.removeItem(atPath: work)
    }
    let fm = FileManager.default
    try fm.createDirectory(atPath: carrier + "/engine/repos/acme/app", withIntermediateDirectories: true)
    try fm.createDirectory(atPath: carrier + "/chat/worktrees/acme/wt", withIntermediateDirectories: true)
    let filePath = work + "/file.txt"
    try Data().write(to: URL(fileURLWithPath: filePath))
    try fm.createDirectory(atPath: unreadable, withIntermediateDirectories: true)
    #expect(chmod(unreadable, 0o000) == 0)
    try fm.createDirectory(atPath: work + "/main/.git/worktrees/wt", withIntermediateDirectories: true)
    try Data("../..\n".utf8).write(to: URL(fileURLWithPath: work + "/main/.git/worktrees/wt/commondir"))
    try fm.createDirectory(atPath: work + "/linked-wt", withIntermediateDirectories: true)
    try Data("gitdir: ../main/.git/worktrees/wt\n".utf8).write(to: URL(fileURLWithPath: work + "/linked-wt/.git"))
    let ordinary = work + "/ordinary"
    try fm.createDirectory(atPath: ordinary, withIntermediateDirectories: true)

    let projectsFile = ProjectsFile(folder: carrier)
    let model = ProjectsModel(file: projectsFile) { _ in nil }
    model.reload()

    for (bad, expected) in [
        (carrier + "/engine/repos/acme/app", "Carrier's own engine folder"),
        (carrier + "/chat/worktrees/acme/wt", "Carrier's own chat/worktrees folder"),
        (filePath, "not a folder"),
        (unreadable, "cannot be read"),
        (work + "/linked-wt", "worktree linked to another project"),
    ] {
        #expect(model.add(folder: bad) == nil, Comment(rawValue: bad))
        #expect(model.failure?.contains(expected) == true, Comment(rawValue: "\(bad): \(String(describing: model.failure))"))
        #expect(fm.fileExists(atPath: projectsFile.url.path) == false)
    }

    #expect(model.add(folder: ordinary) == .added(ordinary))
    #expect(model.failure == nil)
    let before = try Data(contentsOf: projectsFile.url)
    #expect(model.add(folder: work + "/linked-wt") == nil)
    #expect(model.failure?.contains("worktree linked to another project") == true)
    #expect(try Data(contentsOf: projectsFile.url) == before)
}

@MainActor @Test func theModelFollowsAnotherProcessWritingTheFile() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let file = ProjectsFile(folder: folder)
    let model = ProjectsModel(host: CloneHost(), file: file) { _ in nil } // a host of its own: `follow` asks it, and a test never asks the machine's
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
    let project = try temporaryFolder()
    defer {
        try? FileManager.default.removeItem(atPath: folder)
        try? FileManager.default.removeItem(atPath: project)
    }
    let file = ProjectsFile(folder: folder)
    let bad = Data("{".utf8)
    try bad.write(to: file.url)
    let model = ProjectsModel(file: file) { _ in nil }
    model.reload()
    #expect(model.problems.map(\.message) == ["is not valid JSON"])
    #expect(model.add(folder: project) == nil)
    #expect(try Data(contentsOf: file.url) == bad)
}

@Test func theNameRuleTrimsAndTurnsBlankIntoNil() {
    #expect(normalizedProjectName("") == nil)
    #expect(normalizedProjectName("   \t\n ") == nil)
    #expect(normalizedProjectName("  Carrier App  ") == "Carrier App")
    #expect(normalizedProjectName("notes") == "notes")
}

@Test func theTagRulesTrimLowercaseDropBlanksAndPreventRepeats() {
    #expect(normalizedProjectTag("  Swift ") == "swift")
    #expect(normalizedProjectTag("   \n") == nil)
    #expect(normalizedProjectTags(["  Swift ", "MACOS", "swift", "  ", "macos", "cli"]) == ["swift", "macos", "cli"])
    #expect(addingProjectTag("  Work ", to: ["swift"]) == ["swift", "work"])
    #expect(addingProjectTag("SWIFT", to: ["swift", "work"]) == ["swift", "work"])
    #expect(addingProjectTag("   ", to: ["swift"]) == ["swift"])
    #expect(removingProjectTag("swift", from: ["swift", "work"]) == ["work"])
}

@Test func aRowCarriesItsTilePinAndTagsFromTheEntry() throws {
    let entries = try readProjects(Data(#"""
    {"projects":[
      {"path":"/a/carrier","origin":"cloned","name":"Carrier","pinned":true,"tags":["swift"],"icon":{"color":"teal","mark":"bolt"}},
      {"path":"/a/notes","origin":"added"}
    ]}
    """#.utf8))
    let rows = projectRows(entries) { _ in nil }
    #expect(rows[0].pinned && rows[0].tags == ["swift"] && rows[0].customName == "Carrier")
    #expect(rows[0].tile == ProjectTile(name: "Carrier", color: .named(.teal), content: .mark(.bolt)))
    #expect(rows[1].pinned == false && rows[1].tags.isEmpty && rows[1].customName == nil && rows[1].folderName == "notes")
    #expect(rows[1].tile == ProjectTile(name: "notes", color: .hashed(projectColorIndex("notes", count: 24)), content: .initials("NO")))
}

@MainActor @Test func editingIdentityWritesAtOnceKeepsUnknownKeysAndReflectsExternalChanges() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let file = ProjectsFile(folder: folder)
    let initial = #"""
    {"projects":[
      {"path":"/a/carrier","origin":"cloned","name":"Old Name","icon":{"image":"keep.png"},"defaults":{"workIn":"worktree"},"actions":[{"name":"Install","command":"pnpm i","when":"newWorktree"}]}
    ]}
    """#
    try Data(initial.utf8).write(to: file.url)
    let model = ProjectsModel(file: file) { _ in nil }
    model.reload()

    // blank name is not written and emptying goes back to the folder's name
    #expect(model.setName("   ", path: "/a/carrier"))
    #expect(model.rows[0].customName == nil && model.rows[0].name == "carrier")
    #expect(try file.read()[0].name == nil)

    #expect(model.setName("  My Carrier  ", path: "/a/carrier"))
    #expect(model.rows[0].name == "My Carrier" && model.rows[0].customName == "My Carrier")

    // pin, tags, and icon colour/mark (setting colour or mark clears any image)
    #expect(model.setPinned(true, path: "/a/carrier"))
    // hiding writes `hidden` and only that; showing again takes the key out
    #expect(model.setHidden(true, path: "/a/carrier") && model.rows[0].hidden)
    #expect(try file.read()[0].json["hidden"] as? Bool == true && file.read()[0].pinned)
    #expect(model.setHidden(false, path: "/a/carrier") && model.rows[0].hidden == false)
    #expect(try file.read()[0].json["hidden"] == nil)
    #expect(model.addTag("  Swift ", path: "/a/carrier"))
    #expect(model.addTag("SWIFT", path: "/a/carrier"))
    #expect(model.addTag("macOS", path: "/a/carrier"))
    #expect(model.setIconColor(.teal, path: "/a/carrier"))
    #expect(model.setIconMark(.terminal, path: "/a/carrier"))
    #expect(model.rows[0].pinned && model.rows[0].tags == ["swift", "macos"])
    #expect(model.rows[0].tile == ProjectTile(name: "My Carrier", color: .named(.teal), content: .mark(.terminal), image: nil))

    // other keys on the entry are preserved
    let entry = try #require(try file.read().first)
    #expect(entry.iconImage == nil)
    #expect(entry.json["defaults"] != nil && entry.json["actions"] != nil)

    // removing a tag and resetting icon
    #expect(model.removeTag("swift", path: "/a/carrier"))
    #expect(model.resetIcon(path: "/a/carrier"))
    #expect(model.rows[0].tags == ["macos"])
    #expect(model.rows[0].iconColor == nil && model.rows[0].iconMark == nil && model.rows[0].iconImage == nil)

    // external edit while following shows on the model
    let following = Task { await model.follow(every: .milliseconds(10)) }
    defer { following.cancel() }
    let external = #"{"projects":[{"path":"/a/carrier","origin":"cloned","name":"From Disk","pinned":false,"tags":["external"],"icon":{"color":"purple","mark":"star"}}]}"#
    try Data(external.utf8).write(to: file.url, options: .atomic)
    for _ in 0..<300 where model.rows.first?.name != "From Disk" { try? await Task.sleep(for: .milliseconds(10)) }
    #expect(model.rows[0].name == "From Disk")
    #expect(model.rows[0].pinned == false && model.rows[0].tags == ["external"])
    #expect(model.rows[0].tile == ProjectTile(name: "From Disk", color: .named(.purple), content: .mark(.star)))
}

@MainActor @Test func choosingAnImageCopiesItAndChoosingColorOrMarkAfterwardsClearsAndDeletesIt() throws {
    let folder = try temporaryFolder()
    let sourceDir = try temporaryFolder()
    defer {
        try? FileManager.default.removeItem(atPath: folder)
        try? FileManager.default.removeItem(atPath: sourceDir)
    }
    let file = ProjectsFile(folder: folder)
    let store = ProjectIconStore(folder: folder)
    try Data(#"{"projects":[{"path":"/a/carrier","origin":"cloned","icon":{"color":"teal","mark":"bolt"}}]}"#.utf8).write(to: file.url)
    let model = ProjectsModel(file: file) { _ in nil }
    model.reload()

    func writePNG(_ name: String) throws -> URL {
        let url = URL(fileURLWithPath: sourceDir + "/" + name)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: nil, width: 400, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let cg = try #require(context.makeImage())
        let data = try ProjectIconStore.pngData(from: cg, maxPixelSize: 400)
        try data.write(to: url)
        return url
    }

    let firstSource = try writePNG("one.png")
    #expect(model.setIconImage(from: firstSource, path: "/a/carrier"))
    let firstImage = try #require(model.rows[0].iconImage)
    #expect(store.existingURL(for: firstImage) != nil)
    // color and mark remain on the entry so a missing file falls back to them
    #expect(model.rows[0].tile == ProjectTile(name: "carrier", color: .named(.teal), content: .mark(.bolt), image: firstImage))

    // deleting the original keeps the copy
    try FileManager.default.removeItem(at: firstSource)
    #expect(store.existingURL(for: firstImage) != nil)

    // choosing a colour afterwards clears the image and deletes its copy
    #expect(model.setIconColor(.orange, path: "/a/carrier"))
    #expect(model.rows[0].iconImage == nil)
    #expect(model.rows[0].iconColor == .orange)
    #expect(store.existingURL(for: firstImage) == nil)

    // choosing an image then a mark afterwards clears the image and deletes its copy
    let secondSource = try writePNG("two.png")
    #expect(model.setIconImage(from: secondSource, path: "/a/carrier"))
    let secondImage = try #require(model.rows[0].iconImage)
    #expect(store.existingURL(for: secondImage) != nil)
    #expect(model.setIconMark(.star, path: "/a/carrier"))
    #expect(model.rows[0].iconImage == nil && model.rows[0].iconMark == .star)
    #expect(store.existingURL(for: secondImage) == nil)

    // choosing an image then resetting clears color, mark and image and deletes the copy
    #expect(model.setIconImage(from: secondSource, path: "/a/carrier"))
    let thirdImage = try #require(model.rows[0].iconImage)
    #expect(model.resetIcon(path: "/a/carrier"))
    #expect(model.rows[0].iconColor == nil && model.rows[0].iconMark == nil && model.rows[0].iconImage == nil)
    #expect(store.existingURL(for: thirdImage) == nil)

    // an invalid image file records a failure and does not write
    let badFile = URL(fileURLWithPath: sourceDir + "/bad.png")
    try Data("not an image".utf8).write(to: badFile)
    #expect(model.setIconImage(from: badFile, path: "/a/carrier") == false)
    #expect(model.failure != nil)
    #expect(model.rows[0].iconImage == nil)
}

@Test func theListFiltersBySearchTagAndLocalOnlyGroupsByTagAndOrdersPinnedFirstThenByName() {
    let table = [
        ProjectRow(path: "/p/zeta", name: "Zeta", repo: "acme/zeta", pinned: false, tags: ["swift", "cli"]),
        ProjectRow(path: "/p/alpha", name: "Alpha", repo: "acme/alpha", pinned: false, tags: ["web", "swift"]),
        ProjectRow(path: "/p/beta", name: "Beta", repo: nil, pinned: true, tags: ["swift"]),
        ProjectRow(path: "/p/notes", name: "Notes", repo: nil, pinned: false, tags: []),
        ProjectRow(path: "/p/docs", name: "Docs", repo: "org/handbook", pinned: true, tags: []),
    ]

    #expect(projectTagsInUse(table) == ["cli", "swift", "web"])
    #expect(projectTagsInUse([]) == [])

    // default: one group, pinned first (Beta, Docs), then by name (Alpha, Notes, Zeta)
    #expect(projectList(table) == [
        ProjectGroup(id: "all", title: nil, rows: [table[2], table[4], table[1], table[3], table[0]]),
    ])

    // search matches name, remote and tag (case-insensitive, trimmed)
    #expect(projectList(table, query: "  handbook  ").flatMap(\.rows).map(\.name) == ["Docs"])
    #expect(projectList(table, query: "CLI").flatMap(\.rows).map(\.name) == ["Zeta"])
    #expect(projectList(table, query: "alp").flatMap(\.rows).map(\.name) == ["Alpha"])
    #expect(projectList(table, query: "does-not-exist").isEmpty)

    // filter by tag and by local only (no GitHub remote)
    #expect(projectList(table, filter: .tag("swift")).flatMap(\.rows).map(\.name) == ["Beta", "Alpha", "Zeta"])
    #expect(projectList(table, filter: .tag("web")).flatMap(\.rows).map(\.name) == ["Alpha"])
    #expect(projectList(table, filter: .localOnly).flatMap(\.rows).map(\.name) == ["Beta", "Notes"])
    #expect(projectList(table, query: "beta", filter: .localOnly).flatMap(\.rows).map(\.name) == ["Beta"])
    #expect(projectList(table, query: "handbook", filter: .localOnly).isEmpty)

    // the Hidden chip shows only the hidden ones, and hiding leaves the project in every other view of the list
    let withHidden = table + [ProjectRow(path: "/p/old", name: "Old", repo: nil, hidden: true)]
    #expect(projectList(withHidden, filter: .hidden).flatMap(\.rows).map(\.name) == ["Old"])
    #expect(projectList(table, filter: .hidden).isEmpty)
    #expect(projectList(withHidden).flatMap(\.rows).map(\.name).contains("Old"))
    #expect(projectList(withHidden, filter: .localOnly).flatMap(\.rows).map(\.name) == ["Beta", "Notes", "Old"])

    // grouped by tag: each appears under its first tag only, untagged last, pinned first inside each group
    #expect(projectList(table, groupBy: .tag) == [
        ProjectGroup(id: "tag:swift", title: "swift", rows: [table[2], table[0]]),
        ProjectGroup(id: "tag:web", title: "web", rows: [table[1]]),
        ProjectGroup(id: "untagged", title: "untagged", rows: [table[4], table[3]]),
    ])

    // grouped by tag + filter: empty groups are omitted
    #expect(projectList(table, filter: .localOnly, groupBy: .tag) == [
        ProjectGroup(id: "tag:swift", title: "swift", rows: [table[2]]),
        ProjectGroup(id: "untagged", title: "untagged", rows: [table[3]]),
    ])
}

@MainActor @Test func changingTheDefaultCloneFolderWritesChatJsonAndRefusesCarrierFolders() throws {
    let carrier = try temporaryFolder()
    let target = try temporaryFolder()
    defer {
        try? FileManager.default.removeItem(atPath: carrier)
        try? FileManager.default.removeItem(atPath: target)
    }
    var chatJSON: Data? = Data(#"{"logLevel":"debug"}"#.utf8)
    let model = ProjectsModel(
        file: ProjectsFile(folder: carrier),
        remote: { _ in nil },
        readChatConfig: { chatJSON },
        writeChatConfig: { chatJSON = $0 },
        home: "/Users/ana"
    )
    #expect(model.projectsPath == carrier + "/chat/projects")

    // Refuses Carrier's own folder and leaves the current path unchanged.
    model.changeProjectsFolder(to: carrier + "/engine")
    #expect(model.projectsFolderProblem?.contains("Carrier's own engine folder") == true)
    #expect(model.projectsPath == carrier + "/chat/projects")

    // Valid folder writes projectsFolder while preserving other keys.
    model.changeProjectsFolder(to: target)
    #expect(model.projectsFolderProblem == nil)
    #expect(model.projectsPath == target)
    let saved = try #require(chatJSON.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
    #expect(saved["projectsFolder"] as? String == target && saved["logLevel"] as? String == "debug")
}

// MARK: last active and its order

private func session(_ base: String, _ ago: TimeInterval, now: Date) -> SessionRow {
    SessionRow(id: UUID().uuidString, title: "t", workspace: "w", agent: "a", state: .idle, updatedAt: now.addingTimeInterval(-ago), folder: base + "/wt", base: base)
}

@Test func lastActiveIsTheNewestSessionOfTheProjectsBaseFolderWrittenAnyWayAndNilForNone() throws {
    let root = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: root) }
    try FileManager.default.createDirectory(atPath: root + "/real", withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(atPath: root + "/link", withDestinationPath: root + "/real")
    let now = Date()
    let rows = [ProjectRow(path: root + "/real", name: "real", repo: nil), ProjectRow(path: root + "/other", name: "other", repo: nil), ProjectRow(path: "/Users/x/none", name: "none", repo: nil)]
    let sessions = [
        session(root + "/real/", 500, now: now),  // trailing slash
        session(root + "/link", 100, now: now),  // through a symlink
        session(root + "/real", 900, now: now),
        session(root + "/other", 700, now: now),
        session(root + "/real/inside", 1, now: now),  // a folder inside is not the project's base folder
    ]
    let joined = projectsWithLastActive(rows, sessions: sessions)
    #expect(joined.map(\.lastActive) == [now.addingTimeInterval(-100), now.addingTimeInterval(-700), nil])
    #expect(projectsWithLastActive(rows, sessions: []).allSatisfy { $0.lastActive == nil })
}

@Test func theFileHoldsNoActivityTime() throws {
    let before = Data(#"{"projects":[{"path":"/a","origin":"added","pinned":true}]}"#.utf8)
    let entries = try readProjects(before)
    let joined = projectsWithLastActive(projectRows(entries) { _ in nil }, sessions: [session("/a", 5, now: Date())])
    #expect(joined[0].lastActive != nil)
    // the entry and the file are what they were: activity is on the row and nowhere else
    #expect(try readProjects(before) == entries && Set(entries[0].json.keys) == ["path", "origin", "pinned"])
}

@Test func theListSortsByNameOrLastActivePinnedFirstAndNeverActiveLast() {
    let now = Date()
    func row(_ name: String, _ ago: TimeInterval?, pinned: Bool = false) -> ProjectRow {
        ProjectRow(path: "/p/\(name)", name: name, repo: nil, pinned: pinned, lastActive: ago.map { now.addingTimeInterval(-$0) })
    }
    let table = [row("beta", 50), row("alpha", nil), row("gamma", 10), row("delta", 900, pinned: true), row("eps", nil, pinned: true)]
    func names(_ order: ProjectOrder) -> [String] { projectList(table, order: order).flatMap(\.rows).map(\.name) }
    #expect(names(ProjectOrder()) == ["delta", "eps", "alpha", "beta", "gamma"])
    #expect(names(ProjectOrder(key: .name, ascending: false)) == ["eps", "delta", "gamma", "beta", "alpha"])
    #expect(names(ProjectOrder(key: .lastActive, ascending: false)) == ["delta", "eps", "gamma", "beta", "alpha"])
    #expect(names(ProjectOrder(key: .lastActive, ascending: true)) == ["delta", "eps", "beta", "gamma", "alpha"])
}

@Test func clickingATitleSortsByItAndASecondClickReverses() {
    var order = ProjectOrder()
    #expect(order == ProjectOrder(key: .name, ascending: true))
    order = order.clicked(.lastActive)
    #expect(order == ProjectOrder(key: .lastActive, ascending: false))
    order = order.clicked(.lastActive)
    #expect(order == ProjectOrder(key: .lastActive, ascending: true))
    order = order.clicked(.name)
    #expect(order == ProjectOrder(key: .name, ascending: true))
    #expect(order.clicked(.name) == ProjectOrder(key: .name, ascending: false))
}

@MainActor @Test func removingAProjectTakesOnlyItsEntryAndItsImageAndLeavesTheEngineConfigFolderAndWorktreesAlone() throws {
    let carrier = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: carrier) }
    let project = carrier + "/work/app", worktree = carrier + "/chat/worktrees/acme/app/one"
    for folder in [project, worktree] { try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true) }
    try Data("keep".utf8).write(to: URL(fileURLWithPath: worktree + "/file.txt"))
    // a watched project: the engine's file names its repository
    let engine = Data(#"{"repos":["acme/app"]}"#.utf8)
    let places = CarrierPlaces(folder: carrier)
    try engine.write(to: URL(fileURLWithPath: places.engineConfig))
    let file = ProjectsFile(folder: carrier)
    let store = ProjectIconStore(folder: carrier)
    try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
    for name in ["gone.png", "shared.png"] { try Data("x".utf8).write(to: store.directory.appendingPathComponent(name)) }
    let initial = #"""
    {"projects":[
      {"path":"\#(project)","origin":"cloned","icon":{"image":"gone.png"},"actions":[{"name":"i","command":"pnpm i","when":"newWorktree"}]},
      {"path":"/b/other","origin":"added","tags":["x"],"icon":{"image":"shared.png"}}
    ]}
    """#
    try Data(initial.utf8).write(to: file.url)
    let model = ProjectsModel(file: file) { _ in "acme/app" }
    model.reload()

    #expect(model.remove(path: project))
    #expect(model.rows.map(\.path) == ["/b/other"])
    #expect(try file.read()[0].tags == ["x"])
    #expect(store.existingURL(for: "gone.png") == nil && store.existingURL(for: "shared.png") != nil)
    #expect(try Data(contentsOf: URL(fileURLWithPath: places.engineConfig)) == engine)
    #expect(FileManager.default.fileExists(atPath: project) && FileManager.default.fileExists(atPath: worktree + "/file.txt"))
    // gone already: nothing to remove, nothing written
    #expect(model.remove(path: project) == false)
    #expect(try file.read().count == 1)
}

@Test func aProjectWhoseFolderIsGoneIsNotFoundAndOneThatIsThereIsReady() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let entries = try readProjects(Data(#"{"projects":[{"path":"\#(folder)","origin":"added"},{"path":"\#(folder)/gone","origin":"added"},{"path":"~/nowhere-carrier-test","origin":"added"}]}"#.utf8))
    let rows = projectRows(entries) { _ in nil }
    #expect(rows.map(\.status) == [.ready, .notFound, .notFound])
    #expect(rows.map(\.status.text) == [nil, "Folder not found", "Folder not found"])
    // a file is not a folder to open
    try Data("x".utf8).write(to: URL(fileURLWithPath: folder + "/file"))
    #expect(projectRows(try readProjects(Data(#"{"projects":[{"path":"\#(folder)/file","origin":"added"}]}"#.utf8))) { _ in nil }.map(\.status) == [.notFound])
}

@Test func locatingReplacesOnlyThePathAndRefusesAnotherProjectsFolder() throws {
    let json = Data(#"""
    {"projects":[
      {"path":"/old/app","name":"App","origin":"cloned","pinned":true,"tags":["x"],"icon":{"color":"blue"},"defaults":{"workIn":"worktree"},"actions":[{"name":"i","command":"pnpm i","when":"newWorktree"}]},
      {"path":"/b/other","origin":"added"}
    ]}
    """#.utf8)
    let written = try applyingProjectLocation(path: "/old/app", to: "/new/app", in: json)
    var expected = try #require(JSONSerialization.jsonObject(with: json) as? [String: Any])
    var projects = try #require(expected["projects"] as? [[String: Any]])
    projects[0]["path"] = "/new/app"
    expected["projects"] = projects
    #expect(NSDictionary(dictionary: try #require(JSONSerialization.jsonObject(with: written) as? [String: Any])).isEqual(to: expected))
    #expect(throws: ProjectsFileError.self) { try applyingProjectLocation(path: "/old/app", to: "/b/other/", in: json) }
    #expect(throws: ProjectsFileError.missing("/nope")) { try applyingProjectLocation(path: "/nope", to: "/new/app", in: json) }
}

@MainActor @Test func locateChecksTheFolderThenPointsTheProjectAtItAndKeepsTheRest() throws {
    let carrier = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: carrier) }
    let moved = carrier + "/moved/app", taken = carrier + "/taken"
    for folder in [moved, taken] { try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true) }
    let file = ProjectsFile(folder: carrier)
    let gone = carrier + "/gone/app"
    try Data(#"{"projects":[{"path":"\#(gone)","name":"App","origin":"cloned","tags":["x"]},{"path":"\#(taken)","origin":"added"}]}"#.utf8).write(to: file.url)
    let model = ProjectsModel(file: file) { _ in nil }
    model.reload()
    #expect(model.rows.first?.status == .notFound)

    // a folder that does not exist, a file and another project's folder write nothing
    #expect(model.locate(path: gone, to: carrier + "/still/gone") == false)
    #expect(model.failure == "That folder does not exist")
    #expect(model.locate(path: gone, to: taken) == false)
    #expect(model.failure == "That folder is already a project")
    #expect(model.rows.map(\.path) == [gone, taken])

    #expect(model.locate(path: gone, to: moved))
    #expect(model.failure == nil)
    #expect(model.rows.map(\.path) == [moved, taken])
    #expect(model.rows[0].name == "App" && model.rows[0].tags == ["x"] && model.rows[0].status == .ready)
}

@Test func theListSaysWhichProjectsCarrierWatchesAndAChipShowsOnlyThose() {
    let rows = [
        ProjectRow(path: "/p/web", name: "Web", repo: "Acme/Web"),
        ProjectRow(path: "/p/api", name: "Api", repo: "acme/api"),
        ProjectRow(path: "/p/notes", name: "Notes", repo: nil),
    ]
    let marked = projectsWithWatched(rows, repos: ["acme/web", "other/thing"])
    #expect(marked.map(\.carrierText) == ["Watching", "Not watched", "Not watched"])
    #expect(projectList(marked, filter: .watched).flatMap(\.rows).map(\.name) == ["Web"])
    #expect(projectList(marked, query: "api", filter: .watched).isEmpty)
    #expect(projectList(marked).flatMap(\.rows).count == 3)
    // an unreadable engine config watches nothing
    #expect(projectsWithWatched(rows, repos: nil).allSatisfy { $0.watched == false })
}
