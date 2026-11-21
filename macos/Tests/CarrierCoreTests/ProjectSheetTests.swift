import Foundation
import Testing
@testable import CarrierCore

// The shared Add project sheet's pure model: Suggested recent folders, filtering, path recognition, duplicates, the first result, and drops.

private func makeRow(_ path: String, name: String? = nil, repo: String? = nil) -> ProjectRow {
    ProjectRow(path: path, name: name ?? projectFolderName(path), customName: name, repo: repo)
}

@Test func emptyQueryShowsSuggestedRecentFoldersNotAlreadyProjectsEachWithAdd() {
    let home = "/Users/ana"
    let recent = [
        RecentFolder(name: "carrier", path: "/Users/ana/work/carrier"),
        RecentFolder(name: "web", path: "/Users/ana/work/web"),
        RecentFolder(name: "notes", path: "/Users/ana/notes"),
        RecentFolder(name: "notes-dup", path: "/Users/ana/notes/"),
    ]
    let projects = [
        makeRow("~/work/carrier", name: "Carrier"),
    ]

    let state = projectSheetState(mode: .settings, query: "", recent: recent, projects: projects, home: home)

    #expect(state.mode == .settings)
    #expect(state.sections.count == 1)
    #expect(state.sections[0].title == "Suggested")
    #expect(state.items.map(\.title) == ["web", "notes"])
    #expect(state.items.map(\.detail) == ["~/work/web", "~/notes"])
    #expect(state.items.map(\.actionTitle) == ["Add", "Add"])
    #expect(state.firstResult?.path == "/Users/ana/work/web")
}

@Test func typingFiltersSuggestedFoldersByNameOrPath() {
    let home = "/Users/ana"
    let recent = [
        RecentFolder(name: "carrier", path: "/Users/ana/work/carrier"),
        RecentFolder(name: "api", path: "/Users/ana/client/api"),
        RecentFolder(name: "docs", path: "/Users/ana/notes/docs"),
    ]

    let byName = projectSheetState(mode: .settings, query: " API ", recent: recent, projects: [], home: home)
    #expect(byName.items.map(\.title) == ["api"])

    let byFolder = projectSheetState(mode: .settings, query: "notes", recent: recent, projects: [], home: home)
    #expect(byFolder.items.map(\.title) == ["docs"])

    let none = projectSheetState(mode: .settings, query: "missing", recent: recent, projects: [], home: home)
    #expect(none.sections.isEmpty && none.items.isEmpty && none.firstResult == nil)
}

@Test func pathStartingWithTildeOrSlashShowsAddFolderAsFirstResult() {
    let home = "/Users/ana"
    let recent = [
        RecentFolder(name: "carrier", path: "/Users/ana/work/carrier"),
        RecentFolder(name: "web", path: "/Users/ana/work/web"),
    ]

    let tilde = projectSheetState(mode: .settings, query: "~/work/new-app/", recent: recent, projects: [], home: home)
    #expect(tilde.firstResult?.kind == .addPath(path: "/Users/ana/work/new-app"))
    #expect(tilde.firstResult?.title == "Add folder")
    #expect(tilde.firstResult?.detail == "~/work/new-app")
    #expect(tilde.firstResult?.actionTitle == "Add")

    let absolute = projectSheetState(mode: .settings, query: "/srv/code/demo", recent: recent, projects: [], home: home)
    #expect(absolute.firstResult?.kind == .addPath(path: "/srv/code/demo"))
    #expect(absolute.firstResult?.title == "Add folder")
    #expect(absolute.firstResult?.detail == "/srv/code/demo")
    #expect(absolute.firstResult?.actionTitle == "Add")

    let homeRoot = projectSheetState(mode: .settings, query: "~", recent: recent, projects: [], home: home)
    #expect(homeRoot.firstResult?.kind == .addPath(path: "/Users/ana"))
    #expect(homeRoot.firstResult?.detail == "~")

    // When the typed path is also a suggested folder, it is not repeated under Suggested.
    let typedRecent = projectSheetState(mode: .settings, query: "~/work/carrier", recent: recent, projects: [], home: home)
    #expect(typedRecent.items.count == 1)
    #expect(typedRecent.firstResult?.kind == .addPath(path: "/Users/ana/work/carrier"))
}

@Test func typedPathMatchingAnExistingProjectShowsAlreadyAProjectOpen() {
    let home = "/Users/ana"
    let existing = makeRow("~/work/carrier", name: "Carrier App")

    for typed in ["/Users/ana/work/carrier", "/Users/ana/work/carrier/", "~/work/carrier"] {
        let state = projectSheetState(mode: .settings, query: typed, recent: [], projects: [existing], home: home)
        #expect(state.firstResult?.kind == .existingProject(existing), Comment(rawValue: typed))
        #expect(state.firstResult?.title == "Carrier App")
        #expect(state.firstResult?.detail == "Already a project · Open")
        #expect(state.firstResult?.actionTitle == "Open")
    }
}

@Test func recentFoldersFromSessionRowsTakesDistinctBasesNewestFirst() {
    let t1 = Date(timeIntervalSince1970: 100)
    let t2 = Date(timeIntervalSince1970: 200)
    let t3 = Date(timeIntervalSince1970: 300)
    let sessions = [
        SessionRow(id: "1", title: "One", workspace: "api", agent: "claude", state: .idle, updatedAt: t1, folder: "/w/api"),
        SessionRow(id: "2", title: "Two", workspace: "carrier", agent: "claude", state: .idle, updatedAt: t3, folder: "/wt/1", base: "/w/carrier"),
        SessionRow(id: "3", title: "Three", workspace: "api", agent: "claude", state: .idle, updatedAt: t2, folder: "/w/api"),
    ]
    let recent = recentFolders(from: sessions)
    #expect(recent == [
        RecentFolder(name: "carrier", path: "/w/carrier"),
        RecentFolder(name: "api", path: "/w/api"),
    ])
}

@MainActor @Test func droppingFoldersAndFilesAddsValidOnesAndRefusesInvalidWithReason() throws {
    let root = NSTemporaryDirectory() + "sheet-drop-\(UUID().uuidString)"
    let carrier = root + "/carrier"
    let folderA = root + "/a"
    let folderB = root + "/b"
    let filePath = root + "/notes.txt"
    defer { try? FileManager.default.removeItem(atPath: root) }

    let fm = FileManager.default
    try fm.createDirectory(atPath: carrier + "/engine", withIntermediateDirectories: true)
    try fm.createDirectory(atPath: folderA, withIntermediateDirectories: true)
    try fm.createDirectory(atPath: folderB, withIntermediateDirectories: true)
    try Data("hi".utf8).write(to: URL(fileURLWithPath: filePath))

    let model = ProjectsModel(file: ProjectsFile(folder: carrier)) { _ in nil }
    model.reload()

    // Single dropped file is refused with its reason and writes nothing.
    let fileDrop = applyDroppedProjectPaths([filePath]) { path in
        (model.add(folder: path), model.failure)
    }
    #expect(fileDrop == .refused("That path is not a folder"))
    #expect(model.rows.isEmpty)

    // Single dropped folder inside Carrier's own folder is refused with its reason.
    let ownDrop = applyDroppedProjectPaths([carrier + "/engine"]) { path in
        (model.add(folder: path), model.failure)
    }
    if case .refused(let reason) = ownDrop {
        #expect(reason.contains("Carrier's own engine folder"))
    } else {
        Issue.record("Expected refusal for Carrier's own folder")
    }
    #expect(model.rows.isEmpty)

    // Single valid folder adds with origin added and opens it.
    let singleValid = applyDroppedProjectPaths([folderA]) { path in
        (model.add(folder: path), model.failure)
    }
    #expect(singleValid == .open(folderA))
    #expect(model.rows.map(\.path) == [folderA])
    #expect(try ProjectsFile(folder: carrier).read().first?.origin == "added")

    // Dropping an existing project opens it without duplicating.
    let duplicateDrop = applyDroppedProjectPaths([folderA]) { path in
        (model.add(folder: path), model.failure)
    }
    #expect(duplicateDrop == .open(folderA))
    #expect(model.rows.count == 1)

    // Dropping multiple folders adds all and returns addedMultiple.
    let multiValid = applyDroppedProjectPaths([folderA, folderB]) { path in
        (model.add(folder: path), model.failure)
    }
    #expect(multiValid == .addedMultiple)
    #expect(model.rows.map(\.path) == [folderA, folderB])

    // Dropping a mix including a file refuses with the reason naming the file.
    let mixed = applyDroppedProjectPaths([folderA, filePath]) { path in
        (model.add(folder: path), model.failure)
    }
    if case .refused(let message) = mixed {
        #expect(message.contains("notes.txt") && message.contains("not a folder"))
    } else {
        Issue.record("Expected refusal for mixed drop containing a file")
    }
}
