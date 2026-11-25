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

    let state = projectSheetState(mode: .settings, query: "", recent: recent, projects: projects, home: home, bundle: english.bundle, locale: english.locale)

    #expect(state.mode == .settings)
    #expect(state.sections.count == 1)
    #expect(state.sections[0].title == "Suggested folders")
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

    let byName = projectSheetState(mode: .settings, query: " API ", recent: recent, projects: [], home: home, bundle: english.bundle, locale: english.locale)
    #expect(byName.items.map(\.title) == ["api"])

    let byFolder = projectSheetState(mode: .settings, query: "notes", recent: recent, projects: [], home: home, bundle: english.bundle, locale: english.locale)
    #expect(byFolder.items.map(\.title) == ["docs"])

    let none = projectSheetState(mode: .settings, query: "missing", recent: recent, projects: [], home: home, bundle: english.bundle, locale: english.locale)
    #expect(none.sections.isEmpty && none.items.isEmpty && none.firstResult == nil)
}

@Test func pathStartingWithTildeOrSlashShowsAddFolderAsFirstResult() {
    let home = "/Users/ana"
    let recent = [
        RecentFolder(name: "carrier", path: "/Users/ana/work/carrier"),
        RecentFolder(name: "web", path: "/Users/ana/work/web"),
    ]

    let tilde = projectSheetState(mode: .settings, query: "~/work/new-app/", recent: recent, projects: [], home: home, bundle: english.bundle, locale: english.locale)
    #expect(tilde.firstResult?.kind == .addPath(path: "/Users/ana/work/new-app"))
    #expect(tilde.firstResult?.title == "Add folder")
    #expect(tilde.firstResult?.detail == "~/work/new-app")
    #expect(tilde.firstResult?.actionTitle == "Add")

    let absolute = projectSheetState(mode: .settings, query: "/srv/code/demo", recent: recent, projects: [], home: home, bundle: english.bundle, locale: english.locale)
    #expect(absolute.firstResult?.kind == .addPath(path: "/srv/code/demo"))
    #expect(absolute.firstResult?.title == "Add folder")
    #expect(absolute.firstResult?.detail == "/srv/code/demo")
    #expect(absolute.firstResult?.actionTitle == "Add")

    let homeRoot = projectSheetState(mode: .settings, query: "~", recent: recent, projects: [], home: home, bundle: english.bundle, locale: english.locale)
    #expect(homeRoot.firstResult?.kind == .addPath(path: "/Users/ana"))
    #expect(homeRoot.firstResult?.detail == "~")

    // When the typed path is also a suggested folder, it is not repeated under Suggested.
    let typedRecent = projectSheetState(mode: .settings, query: "~/work/carrier", recent: recent, projects: [], home: home, bundle: english.bundle, locale: english.locale)
    #expect(typedRecent.items.count == 1)
    #expect(typedRecent.firstResult?.kind == .addPath(path: "/Users/ana/work/carrier"))
}

@Test func typedPathMatchingAnExistingProjectShowsAlreadyAProjectOpen() {
    let home = "/Users/ana"
    let existing = makeRow("~/work/carrier", name: "Carrier App")

    for typed in ["/Users/ana/work/carrier", "/Users/ana/work/carrier/", "~/work/carrier"] {
        let state = projectSheetState(mode: .settings, query: typed, recent: [], projects: [existing], home: home, bundle: english.bundle, locale: english.locale)
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

@MainActor @Test func droppingFoldersAndFilesAddsValidOnesAndRefusesInvalidWithReason() async throws {
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

    let model = ProjectsModel(host: CloneHost(writing: carrier), file: ProjectsFile(folder: carrier)) { _ in nil }
    model.reload()

    // Single dropped file is refused with its reason and writes nothing.
    let fileDrop = await applyDroppedProjectPaths([filePath]) { path in
        (await model.add(folder: path), model.failure)
    }
    #expect(fileDrop == .refused("That path is not a folder"))
    #expect(model.rows.isEmpty)

    // Single dropped folder inside Carrier's own folder is refused with its reason.
    let ownDrop = await applyDroppedProjectPaths([carrier + "/engine"]) { path in
        (await model.add(folder: path), model.failure)
    }
    if case .refused(let reason) = ownDrop {
        #expect(reason.contains("Carrier's own engine folder"))
    } else {
        Issue.record("Expected refusal for Carrier's own folder")
    }
    #expect(model.rows.isEmpty)

    // Single valid folder adds with origin added and opens it.
    let singleValid = await applyDroppedProjectPaths([folderA]) { path in
        (await model.add(folder: path), model.failure)
    }
    #expect(singleValid == .open(folderA))
    #expect(model.rows.map(\.path) == [folderA])
    #expect(try ProjectsFile(folder: carrier).read().first?.origin == "added")

    // Dropping an existing project opens it without duplicating.
    let duplicateDrop = await applyDroppedProjectPaths([folderA]) { path in
        (await model.add(folder: path), model.failure)
    }
    #expect(duplicateDrop == .open(folderA))
    #expect(model.rows.count == 1)

    // Dropping multiple folders adds all and returns addedMultiple.
    let multiValid = await applyDroppedProjectPaths([folderA, folderB]) { path in
        (await model.add(folder: path), model.failure)
    }
    #expect(multiValid == .addedMultiple)
    #expect(model.rows.map(\.path) == [folderA, folderB])

    // Dropping a mix including a file refuses with the reason naming the file.
    let mixed = await applyDroppedProjectPaths([folderA, filePath]) { path in
        (await model.add(folder: path), model.failure)
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
        let state = projectSheetState(mode: .settings, query: pasted, recent: [], projects: [], github: github(myRepos), home: home, bundle: english.bundle, locale: english.locale)
        let first = state.firstResult
        #expect(first?.kind == .cloneRepo(repo: "acme/new-thing", parent: nil), Comment(rawValue: pasted))
        #expect(first?.title == "Clone acme/new-thing" && first?.actionTitle == "Clone" && first?.isEnabled == true)
        #expect(first?.destination == ProjectSheetDestination(line: "Clones into ~/Carrier/projects/acme/new-thing", parent: "/Users/ana/Carrier/projects", isChosen: false))
    }
}

@Test func choosingAFolderForOneCloneChangesItsDestinationAndNotTheDefaultOrTheOtherRepositories() {
    let known = github(myRepos, chosen: ["acme/new-thing": "/Users/ana/work"])
    let chosen = projectSheetState(mode: .settings, query: "acme/new-thing", recent: [], projects: [], github: known, home: "/Users/ana", bundle: english.bundle, locale: english.locale)
    #expect(chosen.firstResult?.kind == .cloneRepo(repo: "acme/new-thing", parent: "/Users/ana/work"))
    #expect(chosen.firstResult?.destination == ProjectSheetDestination(line: "Clones into ~/work/acme/new-thing", parent: "/Users/ana/work", isChosen: true))
    // the default stays for every other repository
    let other = projectSheetState(mode: .settings, query: "acme/other", recent: [], projects: [], github: known, home: "/Users/ana", bundle: english.bundle, locale: english.locale)
    #expect(other.firstResult?.destination?.parent == "/Users/ana/Carrier/projects" && other.firstResult?.destination?.isChosen == false)
}

@Test func typingFiltersTheListedRepositoriesByNameOrDescriptionWithTheirDescriptionLastPushAndPrivateChip() {
    let state = projectSheetState(mode: .settings, query: "habit", recent: [], projects: [], github: github(myRepos), home: "/Users/ana", bundle: english.bundle, locale: english.locale)
    #expect(state.sections.map(\.title) == ["Your repositories"])
    let row = state.items[0]
    #expect(row.title == "ana/encaja" && row.detail == "A tiny habit tracker" && row.chip == nil)
    #expect(row.pushed == "pushed yesterday")
    #expect(row.kind == .cloneRepo(repo: "ana/encaja", parent: nil) && row.actionTitle == "Clone")

    let byName = projectSheetState(mode: .settings, query: "acme", recent: [], projects: [], github: github(myRepos), home: "/Users/ana", bundle: english.bundle, locale: english.locale)
    #expect(byName.items.map(\.title) == ["acme/web", "acme/api"])
    #expect(byName.items.map(\.chip) == ["Private", "Private"])
    // a typed word that is no address and no repository leaves nothing
    #expect(projectSheetState(mode: .settings, query: "zzz", recent: [], projects: [], github: github(myRepos), home: "/Users/ana", bundle: english.bundle, locale: english.locale).items.isEmpty)
}

@Test func withNothingTypedTheRepositoriesFollowTheSuggestedFolders() {
    let state = projectSheetState(mode: .settings, query: "", recent: [RecentFolder(name: "web", path: "/Users/ana/web")], projects: [], github: github(myRepos), home: "/Users/ana", bundle: english.bundle, locale: english.locale)
    #expect(state.sections.map(\.title) == ["Suggested folders", "Your repositories"])
    #expect(state.items.count == 4)
    // with no GitHub knowledge (an older host, or Settings before it loaded) the sheet is the folder sheet it was
    #expect(projectSheetState(mode: .settings, query: "", recent: [RecentFolder(name: "web", path: "/Users/ana/web")], projects: [], home: "/Users/ana", bundle: english.bundle, locale: english.locale).sections.map(\.title) == ["Suggested folders"])
}

@Test func aRepositoryThatIsAlreadyAProjectShowsOpenInsteadOfClone() {
    let project = makeRow("/Users/ana/Carrier/projects/acme/web", name: "Web", repo: "acme/web")
    let typed = projectSheetState(mode: .settings, query: "ACME/web", recent: [], projects: [project], github: github(myRepos), home: "/Users/ana", bundle: english.bundle, locale: english.locale)
    #expect(typed.firstResult?.kind == .existingProject(project) && typed.firstResult?.actionTitle == "Open" && typed.firstResult?.detail == "Already a project · Open")
    let listed = projectSheetState(mode: .settings, query: "acme", recent: [], projects: [project], github: github(myRepos), home: "/Users/ana", bundle: english.bundle, locale: english.locale)
    #expect(listed.items.map(\.actionTitle) == ["Open", "Clone"])
    // the repository that is pasted is not listed again below
    #expect(typed.items.filter { $0.title.contains("acme/web") || $0.title == "Web" }.count == 1)
}

@Test func aRepositoryTheLoginCannotSeeIsOrangeWithCloneOffAndAListedOneIsNeverChecked() {
    let missing = projectSheetState(mode: .settings, query: "acme/secret", recent: [], projects: [], github: github(myRepos, visibility: ["acme/secret": .notVisible]), home: "/Users/ana", bundle: english.bundle, locale: english.locale)
    #expect(missing.firstResult?.problem == "Your GitHub login can't see this repository. Check the name, or sign in with another account.")
    #expect(missing.firstResult?.isEnabled == false)
    // still being checked, or seen: Clone is on
    #expect(projectSheetState(mode: .settings, query: "acme/secret", recent: [], projects: [], github: github(visibility: ["acme/secret": .checking]), home: "/Users/ana", bundle: english.bundle, locale: english.locale).firstResult?.isEnabled == true)
    #expect(projectSheetState(mode: .settings, query: "acme/secret", recent: [], projects: [], github: github(visibility: ["acme/secret": .visible]), home: "/Users/ana", bundle: english.bundle, locale: english.locale).firstResult?.isEnabled == true)
    // one in the person's own listing is seen by that login, whatever an old check said
    let listed = projectSheetState(mode: .settings, query: "acme/web", recent: [], projects: [], github: github(myRepos, visibility: ["acme/web": .notVisible]), home: "/Users/ana", bundle: english.bundle, locale: english.locale)
    #expect(listed.firstResult?.isEnabled == true)
    // the code of the host's refusal tells this one from a failure of gh, whatever the words say
    #expect(isRepoNotVisible(Refusal(code: "github.repoNotFound", params: ["repo": "acme/secret"], text: "other words")))
    #expect(isRepoNotVisible(Refusal(code: "github.notSignedIn", text: "acme/secret was not found, or your GitHub login cannot see it")) == false)
    // no code, no decision: the words are not read
    #expect(isRepoNotVisible(.words("acme/secret was not found, or your GitHub login cannot see it")) == false)
}

@Test func aMissingOrSignedOutGhShowsTheHostsOwnWordsAndCloneIsOff() {
    let words = "gh is not signed in to GitHub; run \"gh auth login\""
    let state = projectSheetState(mode: .settings, query: "acme/secret", recent: [], projects: [], github: github(visibility: ["acme/secret": .problem(words)], problem: words), home: "/Users/ana", bundle: english.bundle, locale: english.locale)
    #expect(state.firstResult?.problem == words && state.firstResult?.isEnabled == false)
    #expect(state.notice == words)
}

@Test func aHostWithoutTheProjectsCapabilitySaysItIsOlderAndToRestartIt() {
    let state = projectSheetState(mode: .settings, query: "acme/new-thing", recent: [], projects: [], github: github(myRepos, canClone: false), home: "/Users/ana", bundle: english.bundle, locale: english.locale)
    #expect(state.firstResult?.problem == projectsNeedNewerHost && state.firstResult?.isEnabled == false)
    #expect(projectSheetState(mode: .settings, query: "acme", recent: [], projects: [], github: github(myRepos, canClone: false), home: "/Users/ana", bundle: english.bundle, locale: english.locale).items.allSatisfy { $0.isEnabled == false })
}

@Test func aPathIsNeverTakenForARepositoryAndKeepsItsAddFolderResult() {
    let state = projectSheetState(mode: .settings, query: "~/work/acme/web", recent: [], projects: [], github: github(myRepos), home: "/Users/ana", bundle: english.bundle, locale: english.locale)
    #expect(state.firstResult?.kind == .addPath(path: "/Users/ana/work/acme/web"))
    #expect(state.items.contains { $0.kind.isRepository } == false)
}

// MARK: New project… (docs/specs/projects.md, Scope 5)

@Test func theNewProjectFormShowsTheDefaultFolderThenTheOneChosenForThisProject() {
    var form = NewProjectForm(defaultParent: "/Users/ana/Carrier/projects")
    #expect(form.folder == "/Users/ana/Carrier/projects/local/<name>")
    #expect(form.destinationLine(home: "/Users/ana") == "Creates ~/Carrier/projects/local/<name>")
    form.name = "my-app"
    #expect(form.folder == "/Users/ana/Carrier/projects/local/my-app")
    form.chosenParent = "/Volumes/work"
    #expect(form.folder == "/Volumes/work/local/my-app" && form.defaultParent == "/Users/ana/Carrier/projects")
    #expect(form.destinationLine(home: "/Users/ana") == "Creates /Volumes/work/local/my-app")
}

@Test func aNameThatIsNotLettersNumbersDotsAndDashesIsRefusedWithTheReason() {
    var form = NewProjectForm(defaultParent: "/p")
    let free: (String) -> Bool = { _ in false }
    // nothing typed yet: no complaint, and Create is off
    #expect(form.problem(taken: free) == nil && form.canCreate(taken: free) == false)
    let refused: [(String, String)] = [
        ("my app", "Use only letters, digits, _, . and -"),
        ("a/b", "Use only letters, digits, _, . and -"),
        ("café", "Use only letters, digits, _, . and -"),
        (".hidden", "A name starts with a letter, a digit or _"),
        ("-x", "A name starts with a letter, a digit or _"),
        (String(repeating: "a", count: 101), "A name has at most 100 characters"),
    ]
    for (name, reason) in refused {
        form.name = name
        #expect(form.problem(taken: free) == reason, "\(name)")
        #expect(form.canCreate(taken: free) == false)
    }
    for name in ["my-app", "app.2", "_x", "A1", String(repeating: "a", count: 100)] {
        form.name = name
        #expect(form.problem(taken: free) == nil && form.canCreate(taken: free), "\(name)")
    }
}

@Test func aNameWhoseFolderIsThereIsRefusedWithTheReason() {
    var form = NewProjectForm(defaultParent: "/p")
    form.name = "mine"
    let taken: (String) -> Bool = { $0 == "/p/local/mine" }
    #expect(form.problem(taken: taken) == "mine is already a project; choose another name")
    #expect(form.canCreate(taken: taken) == false)
    // the folder chosen for this project is the one looked at
    form.chosenParent = "/elsewhere"
    #expect(form.problem(taken: taken) == nil && form.canCreate(taken: taken))
}

// MARK: the sheet in New session mode (docs/specs/projects.md, Scope 10, 12 and 23)

@Test func inNewSessionTheProjectsThatAreNotHiddenComeFirstWithTheirTileNameAndFolderAndTheSuggestedFoldersAreOnlyWhatIsNotAProject() {
    let home = "/Users/ana"
    let web = ProjectRow(path: "/Users/ana/work/web", name: "Site", repo: nil, iconColor: .teal)
    let hidden = ProjectRow(path: "/Users/ana/work/old", name: "Old", repo: nil, hidden: true)
    let recent = [RecentFolder(name: "web", path: "/Users/ana/work/web"), RecentFolder(name: "old", path: "/Users/ana/work/old"), RecentFolder(name: "notes", path: "/Users/ana/notes")]

    let state = projectSheetState(mode: .newSession, query: "", recent: recent, projects: [web, hidden], github: github(myRepos), home: home, bundle: english.bundle, locale: english.locale)

    #expect(state.sections.map(\.title) == ["Projects", "Suggested folders", "Your repositories"])
    let first = state.items[0]
    #expect(first.kind == .existingProject(web) && first.title == "Site" && first.detail == "~/work/web" && first.tile == web.tile && first.actionTitle == "Use")
    // a hidden project is not listed, and its folder is not suggested: it is a project
    #expect(state.sections[1].items.map(\.title) == ["notes"])
    #expect(state.items.contains { $0.title == "Old" } == false)
    #expect(state.firstResult == first)
    // typing filters the projects by name, folder and repository
    #expect(projectSheetState(mode: .newSession, query: "site", recent: recent, projects: [web, hidden], home: home, bundle: english.bundle, locale: english.locale).items.map(\.title) == ["Site"])
    #expect(projectSheetState(mode: .newSession, query: "work/web", recent: recent, projects: [web, hidden], home: home, bundle: english.bundle, locale: english.locale).items.map(\.title) == ["Site"])
}

@Test func inNewSessionAHiddenProjectIsNotListedNorItsFolderSuggestedWhileAShownOneIs() {
    let shown = ProjectRow(path: "/Users/ana/work/web", name: "Web", repo: nil)
    let hidden = ProjectRow(path: "/Users/ana/work/old", name: "Old", repo: nil, hidden: true)
    let recent = [RecentFolder(name: "old", path: "/Users/ana/work/old"), RecentFolder(name: "web", path: "/Users/ana/work/web")]
    for query in ["", "old", "web"] {
        let state = projectSheetState(mode: .newSession, query: query, recent: recent, projects: [shown, hidden], home: "/Users/ana", bundle: english.bundle, locale: english.locale)
        #expect(state.items.contains { $0.title == "Old" || $0.detail == "~/work/old" } == false, Comment(rawValue: query))
        #expect(state.items.contains { $0.kind == .suggestedFolder(RecentFolder(name: "old", path: "/Users/ana/work/old")) } == false)
    }
    let listed = projectSheetState(mode: .newSession, query: "", recent: recent, projects: [shown, hidden], home: "/Users/ana", bundle: english.bundle, locale: english.locale)
    #expect(listed.items.map(\.title) == ["Web"])
}

@Test func aHiddenProjectIsStillTheProjectAPathOrItsRepositoryNames() {
    let hidden = ProjectRow(path: "/Users/ana/work/old", name: "Old", repo: "acme/web", hidden: true)
    let byPath = projectSheetState(mode: .newSession, query: "/Users/ana/work/old", recent: [], projects: [hidden], home: "/Users/ana", bundle: english.bundle, locale: english.locale)
    #expect(byPath.firstResult?.kind == .existingProject(hidden))
    let byRepo = projectSheetState(mode: .newSession, query: "acme/web", recent: [], projects: [hidden], github: github(myRepos), home: "/Users/ana", bundle: english.bundle, locale: english.locale)
    #expect(byRepo.firstResult?.kind == .existingProject(hidden))
}

@Test func inSettingsAHiddenProjectIsStillAlreadyAProjectByPathAndRepositoryAndItsFolderIsNotSuggested() {
    let hidden = ProjectRow(path: "/Users/ana/work/old", name: "Old", repo: "acme/web", hidden: true)
    let recent = [RecentFolder(name: "old", path: "/Users/ana/work/old")]
    #expect(projectSheetState(mode: .settings, query: "", recent: recent, projects: [hidden], home: "/Users/ana", bundle: english.bundle, locale: english.locale).items.isEmpty)
    let byPath = projectSheetState(mode: .settings, query: "/Users/ana/work/old", recent: recent, projects: [hidden], home: "/Users/ana", bundle: english.bundle, locale: english.locale)
    #expect(byPath.firstResult?.kind == .existingProject(hidden) && byPath.firstResult?.detail == "Already a project · Open")
    let byRepo = projectSheetState(mode: .settings, query: "acme/web", recent: [], projects: [hidden], github: github(myRepos), home: "/Users/ana", bundle: english.bundle, locale: english.locale)
    #expect(byRepo.firstResult?.kind == .existingProject(hidden))
}

@Test func inNewSessionARepositoryToCloneSaysItIsClonedWhenTheFirstMessageIsSentOffersNoOtherFolderAndOffersToWatchIt() {
    let state = projectSheetState(mode: .newSession, query: "acme/new-thing", recent: [], projects: [], github: github(myRepos), home: "/Users/ana", bundle: english.bundle, locale: english.locale)
    let first = state.firstResult
    #expect(first?.kind == .cloneRepo(repo: "acme/new-thing", parent: nil) && first?.actionTitle == "Use")
    #expect(first?.destination == ProjectSheetDestination(line: "Cloned into ~/Carrier/projects/acme/new-thing when you send the first message", parent: "/Users/ana/Carrier/projects", isChosen: false, canChoose: false))
    #expect(first?.watch == ProjectSheetWatch(problem: nil))
    var known = github(myRepos)
    known.watched = ["acme/new-thing"]
    #expect(projectSheetState(mode: .newSession, query: "acme/new-thing", recent: [], projects: [], github: known, home: "/Users/ana", bundle: english.bundle, locale: english.locale).firstResult?.watch?.problem == "acme/new-thing is already watched")
}

@Test func theModesAgreeOnWhatActsAtOnce() {
    #expect(ProjectSheetMode.settings.actsAtOnce && ProjectSheetMode.newSession.actsAtOnce == false)
    #expect(ProjectSheetMode.settings.includesExistingProjects == false && ProjectSheetMode.newSession.includesExistingProjects)
    #expect(ProjectSheetMode.newSession.title(bundle: english.bundle, locale: english.locale) == "Choose where to work" && ProjectSheetMode.settings.title(bundle: english.bundle, locale: english.locale) == "Add project")
}
