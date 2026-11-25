import Foundation
import Testing
@testable import CarrierCore

// Deleting a project from disk (docs/adr/0040, docs/specs/projects.md Scope 20): what the dialog offers and refuses as pure functions, and the move to the Trash
// on temporary folders with a stand-in for the Trash. The real Trash is tried by hand.

private func session(_ id: String, folder: String, base: String? = nil, state: String = "idle", live: Bool = false, title: String? = "Fix sync") throws -> ChatSession {
    let workspace = base.map { ",\"workspace\":{\"kind\":\"worktree\",\"base\":\"\($0)\",\"branch\":\"carrier/x\"}" } ?? ""
    let name = title.map { "\"\($0)\"" } ?? "null"
    let json = """
        {"id":"\(id)","agent":"codex","harness":"codex","folder":"\(folder)"\(workspace),"title":\(name),"state":"\(state)",
         "createdAt":1,"lastActiveAt":1,"archived":false,"live":\(live)}
        """
    return try JSONDecoder().decode(ChatSession.self, from: Data(json.utf8))
}

private func reply(main: ProjectWorktree.State? = .clean, _ worktrees: [ProjectWorktree] = []) -> ProjectWorktrees {
    ProjectWorktrees(main: .init(path: "/p/app", branch: "main", state: main), worktrees: worktrees)
}

private func worktree(_ name: String, _ state: ProjectWorktree.State, session id: String? = nil) -> ProjectWorktree {
    ProjectWorktree(path: "/w/\(name)", branch: "carrier/\(name)", session: id.map { .init(id: $0) }, lastActiveAt: 0, state: state)
}

@Test func onlyWhatCarrierMadeOffersDeletingFromDisk() {
    #expect(canDeleteFromDisk(origin: "cloned") && canDeleteFromDisk(origin: "created"))
    // a folder the person added is never offered, even one that lies in the projects folder
    #expect(canDeleteFromDisk(origin: "added") == false)
    #expect(canDeleteFromDisk(origin: "") == false)
}

@Test func theOfferSaysWhatMovesWhatItHoldsAndWhenTheSpaceIsFreed() {
    #expect(deleteFromDiskWords(worktrees: 3, bytes: 3_000_000_000, bundle: english.bundle, locale: english.locale) == "Moves its folder and 3 worktrees (3 GB) to the Trash. The space is freed when the Trash is emptied.")
    #expect(deleteFromDiskWords(worktrees: 1, bytes: nil, bundle: english.bundle, locale: english.locale) == "Moves its folder and 1 worktree to the Trash. The space is freed when the Trash is emptied.")
    #expect(deleteFromDiskWords(worktrees: 0, bytes: 2_000_000, bundle: english.bundle, locale: english.locale) == "Moves its folder (2 MB) to the Trash. The space is freed when the Trash is emptied.")
}

@Test func aCleanProjectWithIdleSessionsGoesOnWithNothingToConfirm() throws {
    let check = projectDeletionCheck(
        path: "/p/app", reply: reply([worktree("a", .clean, session: "1"), worktree("b", .merged)]),
        sessions: [try session("1", folder: "/w/a", base: "/p/app"), try session("2", folder: "/p/app"), try session("3", folder: "/elsewhere", state: "working", live: true)],
        bundle: english.bundle, locale: english.locale
    )
    #expect(check == ProjectDeletionCheck(refusals: [], unsaved: []))
    #expect(check.canGoOn && check.needsConfirmation == false)
}

@Test func aSessionOfTheProjectThatIsWorkingWaitingOrOpenRefusesAndSaysWhich() throws {
    let check = projectDeletionCheck(
        path: "/p/app/", reply: reply(),
        sessions: [
            try session("1", folder: "/w/a", base: "/p/app", state: "working", live: true, title: "Add retry"),
            try session("2", folder: "/p/app", state: "waiting_approval", live: true, title: "Spike"),
            try session("3", folder: "/p/app", live: true, title: nil),
            try session("4", folder: "/p/app", state: "preparing"),
            try session("5", folder: "/p/app"),
        ],
        bundle: english.bundle, locale: english.locale
    )
    #expect(check.refusals == ["“Add retry” is working", "“Spike” is waiting for you", "“Untitled session” is open", "“Fix sync” is working"])
    #expect(check.canGoOn == false)
}

@Test func aWorktreeSessionTheListDidNotNameStillRefusesFromTheHostsAnswer() throws {
    let check = projectDeletionCheck(path: "/p/app", reply: reply([worktree("a", .sessionOpen, session: "9"), worktree("b", .sessionOpen, session: "1")]), sessions: [try session("1", folder: "/w/b", base: "/p/app", live: true)], bundle: english.bundle, locale: english.locale)
    #expect(check.refusals == ["“Fix sync” is open", "A session of carrier/a is open"])
}

@Test func uncommittedChangesAndBranchesNotPushedAreListedForTheConfirmation() {
    let check = projectDeletionCheck(path: "/p/app", reply: reply(main: .uncommitted, [worktree("a", .uncommitted), worktree("b", .notPushed), worktree("c", .clean), worktree("d", .merged)]), sessions: [], bundle: english.bundle, locale: english.locale)
    #expect(check.unsaved == ["app has uncommitted changes", "carrier/a has uncommitted changes", "carrier/b has commits that are not pushed"])
    #expect(check.canGoOn && check.needsConfirmation)
    #expect(projectDeletionCheck(path: "/p/app", reply: reply(main: .notPushed), sessions: [], bundle: english.bundle, locale: english.locale).unsaved == ["app has commits that are not pushed"])
}

@Test func aHostThatDoesNotSayWhatTheMainCloneHoldsRefusesInsteadOfGuessing() {
    let check = projectDeletionCheck(path: "/p/app", reply: reply(main: nil), sessions: [], bundle: english.bundle, locale: english.locale)
    #expect(check.canGoOn == false && check.refusals.first?.contains("restart") == true)
}

// The Trash move, on real folders in a temporary directory.

private struct Scratch {
    let root: URL
    let home: String
    let carrier: String
    let trash: URL

    init() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath().appendingPathComponent("trash-tests-\(UUID().uuidString)")
        home = root.appendingPathComponent("home").path
        carrier = home + "/.carrier"
        trash = root.appendingPathComponent("Trash")
        for folder in [home, carrier + "/chat/worktrees", carrier + "/chat/projects", trash.path] { try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true) }
    }

    func remove() { try? FileManager.default.removeItem(at: root) }

    /// A folder with a `.git` and a file in it.
    func project(_ path: String) throws -> String {
        try FileManager.default.createDirectory(atPath: path + "/.git", withIntermediateDirectories: true)
        try "x".write(toFile: path + "/a.txt", atomically: true, encoding: .utf8)
        return path
    }

    /// The stand-in for the Trash: moves into the Trash folder, and refuses the item named `failing`.
    func fakeTrash(failing: String? = nil) -> (URL) throws -> URL {
        { url in
            if url.lastPathComponent == failing { throw CocoaError(.fileWriteNoPermission) }
            let target = self.trash.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: target)
            return target
        }
    }
}

private func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }

@Test func theFolderAndItsWorktreesGoToTheTrashAndNothingElseDoes() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    let project = try scratch.project(scratch.carrier + "/chat/projects/acme/app")
    let one = try scratch.project(scratch.carrier + "/chat/worktrees/acme/app/kerrigan")
    let two = try scratch.project(scratch.carrier + "/chat/worktrees/acme/app/raynor")
    let other = try scratch.project(scratch.carrier + "/chat/projects/acme/other")
    try moveProjectToTrash(path: project, worktrees: [one, two], carrierFolder: scratch.carrier, home: scratch.home, trash: scratch.fakeTrash(), bundle: english.bundle, locale: english.locale)
    #expect([project, one, two].allSatisfy { exists($0) == false })
    #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.trash.path).count == 3)
    #expect(exists(other) && exists(scratch.carrier + "/chat/projects/acme"))
}

@Test func whenOneCannotGoToTheTrashWhatWasMovedIsPutBackAndTheReasonIsReported() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    let project = try scratch.project(scratch.carrier + "/chat/projects/acme/app")
    let one = try scratch.project(scratch.carrier + "/chat/worktrees/acme/app/kerrigan")
    let two = try scratch.project(scratch.carrier + "/chat/worktrees/acme/app/raynor")
    // the project's folder is the last to go: the worktrees that already went come back
    do {
        try moveProjectToTrash(path: project, worktrees: [one, two], carrierFolder: scratch.carrier, home: scratch.home, trash: scratch.fakeTrash(failing: "app"), bundle: english.bundle, locale: english.locale)
        Issue.record("the move should have failed")
    } catch let error as ProjectTrashError {
        #expect(error.words.hasPrefix("Could not move app to the Trash") && error.words.hasSuffix("Nothing was removed."))
    }
    #expect([project, one, two].allSatisfy { exists($0) && exists($0 + "/a.txt") })
    #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.trash.path).isEmpty)
    // a worktree that fails first moves nothing at all
    #expect(throws: ProjectTrashError.self) { try moveProjectToTrash(path: project, worktrees: [one, two], carrierFolder: scratch.carrier, home: scratch.home, trash: scratch.fakeTrash(failing: "kerrigan"), bundle: english.bundle, locale: english.locale) }
    #expect([project, one, two].allSatisfy { exists($0 + "/a.txt") })
}

@Test func whatIsNotTheProjectsOwnIsRefusedAndNothingMoves() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    let project = try scratch.project(scratch.carrier + "/chat/projects/acme/app")
    let worktree = try scratch.project(scratch.carrier + "/chat/worktrees/acme/app/kerrigan")
    let outside = try scratch.project(scratch.home + "/Documents/notes")
    let notGit = scratch.home + "/Documents/plain"
    try FileManager.default.createDirectory(atPath: notGit, withIntermediateDirectories: true)
    let link = scratch.home + "/link"
    try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: project)
    func refusal(_ path: String, _ worktrees: [String] = []) -> String? { projectTrashRefusal(path: path, worktrees: worktrees, carrierFolder: scratch.carrier, home: scratch.home, bundle: english.bundle, locale: english.locale) }

    #expect(refusal(project, [worktree]) == nil)
    #expect(refusal(scratch.home)?.contains("home folder") == true)
    #expect(refusal(scratch.root.path)?.contains("holds Carrier's own") == true)
    #expect(refusal(scratch.carrier) != nil)
    #expect(refusal(scratch.carrier + "/chat/worktrees/acme") != nil)
    #expect(refusal("/") != nil && refusal("/tmp") != nil)
    #expect(refusal("relative/app") != nil)
    #expect(refusal(scratch.home + "/missing") == "That folder does not exist")
    #expect(refusal(notGit)?.contains("not a git repository") == true)
    #expect(refusal(link)?.contains("link") == true)
    // a worktree that is not under Carrier's worktrees folder, is the project itself, or is outside everything
    #expect(refusal(project, [outside])?.contains("not a worktree Carrier made") == true)
    #expect(refusal(project, [project]) != nil)
    #expect(refusal(project, [scratch.carrier + "/chat/worktrees"]) != nil)
    #expect(refusal(project, [scratch.home]) != nil)

    for (path, worktrees) in [(scratch.home, []), (outside, [outside]), (notGit, []), (link, [])] as [(String, [String])] {
        #expect(throws: ProjectTrashError.self) { try moveProjectToTrash(path: path, worktrees: worktrees, carrierFolder: scratch.carrier, home: scratch.home, trash: scratch.fakeTrash(), bundle: english.bundle, locale: english.locale) }
    }
    #expect([project, worktree, outside, notGit, scratch.home].allSatisfy(exists))
    #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.trash.path).isEmpty)
}

// The model: the project leaves the list only when its folders went to the Trash.

@MainActor @Test func theProjectLeavesTheListOnlyWhenItsFoldersWentToTheTrash() async throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    let project = try scratch.project(scratch.carrier + "/chat/projects/acme/app")
    let worktree = try scratch.project(scratch.carrier + "/chat/worktrees/acme/app/kerrigan")
    let file = ProjectsFile(folder: scratch.carrier)
    let model = ProjectsModel(host: CloneHost(writing: file.folder), file: file, remote: { _ in nil }, home: scratch.home)
    try FileManager.default.createDirectory(at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"{"projects":[{"path":"\#(project)","origin":"cloned"}]}"#.utf8).write(to: file.url, options: .atomic)
    model.reload()
    #expect(model.rows.map { $0.path } == [project])

    // the Trash refuses: the entry stays, so do the folders
    await #expect(throws: ProjectTrashError.self) { try await model.deleteFromDisk(path: project, worktrees: [worktree], trash: scratch.fakeTrash(failing: "app")) }
    #expect(model.rows.map { $0.path } == [project] && exists(project) && exists(worktree))

    try await model.deleteFromDisk(path: project, worktrees: [worktree], trash: scratch.fakeTrash())
    #expect(model.rows.isEmpty && exists(project) == false && exists(worktree) == false)
}

@MainActor @Test func theRowsKnowHowTheProjectCameToBeSoTheDialogOffersDeletingOnlyForWhatCarrierMade() async throws {
    let folder = NSTemporaryDirectory() + "carrier-origin-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let file = ProjectsFile(folder: folder)
    let added = folder + "/added"
    try FileManager.default.createDirectory(atPath: added, withIntermediateDirectories: true)
    _ = try file.add(folder: added)
    let rows = projectRows(try file.read()) { _ in nil }
    #expect(rows.map { $0.origin } == ["added"] && canDeleteFromDisk(origin: rows[0].origin) == false)

    // a project the person added is refused by the model too, whatever the dialog offered
    let model = ProjectsModel(host: CloneHost(writing: file.folder), file: file, remote: { _ in nil })
    model.reload()
    var trashed = 0
    await #expect(throws: ProjectTrashError.self) { try await model.deleteFromDisk(path: added, worktrees: [], trash: { trashed += 1; return $0 }) }
    #expect(trashed == 0 && FileManager.default.fileExists(atPath: added))
}
