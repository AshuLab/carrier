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

// MARK: cloning from the sheet (docs/specs/projects.md, Scope 4)

private func github(
    _ repos: [AvailableRepo] = [],
    visibility: [String: RepoCheck] = [:],
    chosen: [String: String] = [:],
    canClone: Bool = true,
    problem: String? = nil
) -> ProjectSheetGithub {
    var known = ProjectSheetGithub(defaultParent: "/Users/ana/Carrier/projects")
    known.repos = repos
    known.visibility = visibility
    known.chosenParents = chosen
    known.canClone = canClone
    known.listingProblem = problem
    known.now = Date(timeIntervalSince1970: 1_800_000_000)
    return known
}

private let myRepos = [
    AvailableRepo(name: "ana/encaja", isPrivate: false, pushedAt: "2027-01-14T07:20:00Z", about: "A tiny habit tracker"),
    AvailableRepo(name: "acme/web", isPrivate: true, pushedAt: nil, about: "The marketing site"),
    AvailableRepo(name: "acme/api", isPrivate: true, pushedAt: nil),
]

@Test func aPastedOwnerSlashNameOrGitHubAddressIsACloneResultThatSaysWhereItGoes() {
    let home = "/Users/ana"
    for pasted in ["acme/new-thing", "https://github.com/acme/new-thing", "github.com/acme/new-thing.git", "  https://github.com/acme/new-thing/ "] {
        let state = projectSheetState(mode: .settings, query: pasted, recent: [], projects: [], github: github(myRepos), home: home)
        let first = state.firstResult
        #expect(first?.kind == .cloneRepo(repo: "acme/new-thing", parent: nil), Comment(rawValue: pasted))
        #expect(first?.title == "Clone acme/new-thing" && first?.actionTitle == "Clone" && first?.isEnabled == true)
        #expect(first?.destination == ProjectSheetDestination(line: "Clones into ~/Carrier/projects/acme/new-thing", parent: "/Users/ana/Carrier/projects", isChosen: false))
    }
}

@Test func choosingAFolderForOneCloneChangesItsDestinationAndNotTheDefaultOrTheOtherRepositories() {
    let known = github(myRepos, chosen: ["acme/new-thing": "/Users/ana/work"])
    let chosen = projectSheetState(mode: .settings, query: "acme/new-thing", recent: [], projects: [], github: known, home: "/Users/ana")
    #expect(chosen.firstResult?.kind == .cloneRepo(repo: "acme/new-thing", parent: "/Users/ana/work"))
    #expect(chosen.firstResult?.destination == ProjectSheetDestination(line: "Clones into ~/work/acme/new-thing", parent: "/Users/ana/work", isChosen: true))
    // the default stays for every other repository
    let other = projectSheetState(mode: .settings, query: "acme/other", recent: [], projects: [], github: known, home: "/Users/ana")
    #expect(other.firstResult?.destination?.parent == "/Users/ana/Carrier/projects" && other.firstResult?.destination?.isChosen == false)
}

@Test func typingFiltersTheListedRepositoriesByNameOrDescriptionWithTheirDescriptionLastPushAndPrivateChip() {
    let state = projectSheetState(mode: .settings, query: "habit", recent: [], projects: [], github: github(myRepos), home: "/Users/ana")
    #expect(state.sections.map(\.title) == ["Your repositories"])
    let row = state.items[0]
    #expect(row.title == "ana/encaja" && row.detail == "A tiny habit tracker" && row.chip == nil)
    #expect(row.pushed == "pushed yesterday")
    #expect(row.kind == .cloneRepo(repo: "ana/encaja", parent: nil) && row.actionTitle == "Clone")

    let byName = projectSheetState(mode: .settings, query: "acme", recent: [], projects: [], github: github(myRepos), home: "/Users/ana")
    #expect(byName.items.map(\.title) == ["acme/web", "acme/api"])
    #expect(byName.items.map(\.chip) == ["Private", "Private"])
    // a typed word that is no address and no repository leaves nothing
    #expect(projectSheetState(mode: .settings, query: "zzz", recent: [], projects: [], github: github(myRepos), home: "/Users/ana").items.isEmpty)
}

@Test func withNothingTypedTheRepositoriesFollowTheSuggestedFolders() {
    let state = projectSheetState(mode: .settings, query: "", recent: [RecentFolder(name: "web", path: "/Users/ana/web")], projects: [], github: github(myRepos), home: "/Users/ana")
    #expect(state.sections.map(\.title) == ["Suggested", "Your repositories"])
    #expect(state.items.count == 4)
    // with no GitHub knowledge (an older host, or Settings before it loaded) the sheet is the folder sheet it was
    #expect(projectSheetState(mode: .settings, query: "", recent: [RecentFolder(name: "web", path: "/Users/ana/web")], projects: [], home: "/Users/ana").sections.map(\.title) == ["Suggested"])
}

@Test func aRepositoryThatIsAlreadyAProjectShowsOpenInsteadOfClone() {
    let project = makeRow("/Users/ana/Carrier/projects/acme/web", name: "Web", repo: "acme/web")
    let typed = projectSheetState(mode: .settings, query: "ACME/web", recent: [], projects: [project], github: github(myRepos), home: "/Users/ana")
    #expect(typed.firstResult?.kind == .existingProject(project) && typed.firstResult?.actionTitle == "Open" && typed.firstResult?.detail == "Already a project · Open")
    let listed = projectSheetState(mode: .settings, query: "acme", recent: [], projects: [project], github: github(myRepos), home: "/Users/ana")
    #expect(listed.items.map(\.actionTitle) == ["Open", "Clone"])
    // the repository that is pasted is not listed again below
    #expect(typed.items.filter { $0.title.contains("acme/web") || $0.title == "Web" }.count == 1)
}

@Test func aRepositoryTheLoginCannotSeeIsOrangeWithCloneOffAndAListedOneIsNeverChecked() {
    let missing = projectSheetState(mode: .settings, query: "acme/secret", recent: [], projects: [], github: github(myRepos, visibility: ["acme/secret": .notVisible]), home: "/Users/ana")
    #expect(missing.firstResult?.problem == "Your GitHub login can't see this repository. Check the name, or sign in with another account.")
    #expect(missing.firstResult?.isEnabled == false)
    // still being checked, or seen: Clone is on
    #expect(projectSheetState(mode: .settings, query: "acme/secret", recent: [], projects: [], github: github(visibility: ["acme/secret": .checking]), home: "/Users/ana").firstResult?.isEnabled == true)
    #expect(projectSheetState(mode: .settings, query: "acme/secret", recent: [], projects: [], github: github(visibility: ["acme/secret": .visible]), home: "/Users/ana").firstResult?.isEnabled == true)
    // one in the person's own listing is seen by that login, whatever an old check said
    let listed = projectSheetState(mode: .settings, query: "acme/web", recent: [], projects: [], github: github(myRepos, visibility: ["acme/web": .notVisible]), home: "/Users/ana")
    #expect(listed.firstResult?.isEnabled == true)
    // the words of the host's refusal are what tell this one from a failure of gh
    #expect(isRepoNotVisible("acme/secret was not found, or your GitHub login cannot see it"))
    #expect(isRepoNotVisible("gh is not signed in to GitHub; run \"gh auth login\"") == false)
}

@Test func aMissingOrSignedOutGhShowsTheHostsOwnWordsAndCloneIsOff() {
    let words = "gh is not signed in to GitHub; run \"gh auth login\""
    let state = projectSheetState(mode: .settings, query: "acme/secret", recent: [], projects: [], github: github(visibility: ["acme/secret": .problem(words)], problem: words), home: "/Users/ana")
    #expect(state.firstResult?.problem == words && state.firstResult?.isEnabled == false)
    #expect(state.notice == words)
}

@Test func aHostWithoutTheProjectsCapabilitySaysItIsOlderAndToRestartIt() {
    let state = projectSheetState(mode: .settings, query: "acme/new-thing", recent: [], projects: [], github: github(myRepos, canClone: false), home: "/Users/ana")
    #expect(state.firstResult?.problem == projectsNeedNewerHost && state.firstResult?.isEnabled == false)
    #expect(projectSheetState(mode: .settings, query: "acme", recent: [], projects: [], github: github(myRepos, canClone: false), home: "/Users/ana").items.allSatisfy { $0.isEnabled == false })
}

@Test func aPathIsNeverTakenForARepositoryAndKeepsItsAddFolderResult() {
    let state = projectSheetState(mode: .settings, query: "~/work/acme/web", recent: [], projects: [], github: github(myRepos), home: "/Users/ana")
    #expect(state.firstResult?.kind == .addPath(path: "/Users/ana/work/acme/web"))
    #expect(state.items.contains { $0.kind.isRepository } == false)
}
