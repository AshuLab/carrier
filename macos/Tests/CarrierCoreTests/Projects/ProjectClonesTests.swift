import Foundation
import Testing
@testable import CarrierCore

// What the Projects page does with the clones the host runs (docs/specs/projects.md, Scope 4): the row of a clone, and the model that keeps them.

/// A chat host that answers only the clone requests, from a list it keeps as the real one does.
final class CloneHost: ChatHost, @unchecked Sendable {
    private let lock = NSLock()
    private var clones: [ProjectClone]
    var failure: Error?
    private(set) var started: [(repo: String, parent: String?)] = []
    private(set) var asked = 0
    /// What `newProject` was asked, and the entry the real host would write (the file of `registerIn`), so the model finds the project after.
    private(set) var made: [(name: String, parent: String?)] = []
    var registerIn: ProjectsFile?
    init(_ clones: [ProjectClone] = []) {
        self.clones = clones
        writes = nil
    }
    /// The Carrier folder the project requests write, as the fixture host does with the Swift writers (until they go); with none, `changeProjects` is refused as an older host does.
    private let writes: String?
    /// The project requests the model sent, in order.
    private(set) var changes: [ProjectsChange] = []
    init(writing folder: String) {
        clones = []
        writes = folder
    }
    func changeProjects(_ change: ProjectsChange) async throws -> ProjectsChanged {
        lock.withLock { changes.append(change) }
        if let failure { throw failure }
        guard let writes else { throw ControlError.remote(.hostLacks(change.cmd)) }
        let (data, refusal) = applyProjectsChange(change, home: writes)
        if let refusal { throw ControlError.remote(refusal) }
        return try JSONDecoder().decode(ProjectsChanged.self, from: JSONSerialization.data(withJSONObject: data ?? [:]))
    }
    var current: [ProjectClone] { get { lock.withLock { clones } } set { lock.withLock { clones = newValue } } }

    func cloneProject(_ repo: String, into parent: String?) async throws -> ProjectClone {
        if let failure { throw failure }
        let clone = ProjectClone(repo: repo, folder: (parent ?? "/projects") + "/" + repo, state: .cloning)
        lock.withLock { started.append((repo, parent)); clones.append(clone) }
        return clone
    }
    func newProject(_ name: String, into parent: String?) async throws -> String {
        if let failure { throw failure }
        lock.withLock { made.append((name, parent)) }
        let folder = (parent ?? "/projects") + "/local/" + name
        if let registerIn { try registerIn.add(folder: folder) }
        return folder
    }
    func projectClones() async throws -> [ProjectClone] {
        lock.withLock { asked += 1 }
        if let failure { throw failure }
        return current
    }
    /// What `projectDisk` was asked, and what it answers from the folders and the refresh.
    private(set) var diskAsked: [(folders: [String], refresh: ProjectDiskRefresh)] = []
    var diskAnswer: @Sendable ([String], ProjectDiskRefresh) -> ProjectDiskReply = { _, _ in ProjectDiskReply(projects: []) }
    func projectDisk(_ folders: [String], refresh: ProjectDiskRefresh) async throws -> ProjectDiskReply {
        lock.withLock { diskAsked.append((folders, refresh)) }
        if let failure { throw failure }
        return diskAnswer(folders, refresh)
    }
    func dismissClone(_ repo: String) async throws -> [ProjectClone] {
        lock.withLock { clones.removeAll { $0.repo == repo && $0.state == .failed } }
        return current
    }

    func capabilities() async throws -> Set<ControlClient.Capability> { [.projects] }
    func agents() async throws -> [ChatAgent] { [] }
    func open(plan: SessionPlan) async throws -> String { "" }
    func workspace(_ folder: String) async throws -> WorkspaceInfo { WorkspaceInfo(folder: folder, git: false) }
    func fetch(_ folder: String, ifStale: Bool) async throws -> WorkspaceInfo { WorkspaceInfo(folder: folder, git: false) }
    func suggestName(_ folder: String) async throws -> String { "" }
    func checkName(_ folder: String, _ name: String) async throws -> NameCheck { NameCheck(valid: true, free: true) }
    func list(archived: Bool) async throws -> [ChatSession] { [] }
    func resume(_ id: String) async throws {}
    func send(_ id: String, _ text: String) async throws {}
    func send(_ id: String, _ text: String, command: String?) async throws {}
    func interrupt(_ id: String) async throws {}
    func archive(_ id: String, _ archived: Bool) async throws {}
    func delete(_ id: String) async throws {}
    func githubRepos(page: Int) async throws -> GithubReposPage { throw ControlError.closed }
    func deletePreview(_ ids: [String]) async throws -> [SessionDeletePreview] { [] }
    func answer(_ id: String, approval: String, choice: String, answers: [String: String]?) async throws {}
    func events(_ id: String, after: Int, limit: Int) async throws -> ChatEvents { ChatEvents(events: [], cursor: after, options: [], commands: []) }
    func setOption(_ id: String, option: String, value: String) async throws {}
}

private func temporaryFolder() throws -> String {
    let folder = NSTemporaryDirectory() + "carrier-clones-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    return folder
}

@Test func aCloneRowIsNamedAsTheRepositoryShowsGitsProgressAndCannotBeOpened() {
    let running = ProjectRow(clone: ProjectClone(repo: "acme/web", folder: "/p/acme/web", state: .cloning, progress: "Receiving objects: 45%"))
    #expect(running.name == "web" && running.repo == "acme/web" && running.path == "/p/acme/web")
    #expect(running.line == "Receiving objects: 45%" && running.isOpenable == false)
    #expect(ProjectRow(clone: ProjectClone(repo: "acme/web", folder: "/p/acme/web", state: .cloning)).line == "Cloning…")
    let failed = ProjectRow(clone: ProjectClone(repo: "acme/web", folder: "/p/acme/web", state: .failed, error: "git could not clone acme/web"))
    #expect(failed.line == "git could not clone acme/web" && failed.isOpenable == false)
    // a project is open as ever
    #expect(ProjectRow(path: "/p/x", name: "x", repo: nil).isOpenable)
}

@MainActor @Test func startingACloneShowsItInTheListAtOnceAndNeverWritesTheFileOrWatchesIt() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let host = CloneHost()
    let model = ProjectsModel(host: host, file: ProjectsFile(folder: folder)) { _ in nil }
    model.reload()
    let started = try await model.startClone("acme/web", into: "/work")
    #expect(started.folder == "/work/acme/web")
    #expect(host.started.map(\.repo) == ["acme/web"] && host.started.map(\.parent) == ["/work"])
    // it is a row of the list, not yet a project
    #expect(model.cloneRows.map(\.name) == ["web"] && model.rows.isEmpty)
    #expect(FileManager.default.fileExists(atPath: ProjectsFile(folder: folder).url.path) == false)
    // starting it again is the same clone
    try await model.startClone("acme/web", into: nil)
    #expect(model.cloneRows.count == 1)
}

@MainActor @Test func theHostsRefusalReachesTheSheetInItsWordsAndLeavesTheListAlone() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let host = CloneHost()
    host.failure = ControlError.remote(.words("acme/web is already a project"))
    let model = ProjectsModel(host: host, file: ProjectsFile(folder: folder)) { _ in nil }
    await #expect(throws: ControlError.remote(.words("acme/web is already a project"))) { try await model.startClone("acme/web", into: nil) }
    #expect(model.cloneRows.isEmpty)
}

@MainActor @Test func aCloneThatEndsBecomesAProjectWhenTheHostStopsListingIt() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let file = ProjectsFile(folder: folder)
    let host = CloneHost([ProjectClone(repo: "acme/web", folder: "/p/acme/web", state: .cloning, progress: "Receiving objects: 10%")])
    let model = ProjectsModel(host: host, file: file) { _ in nil }
    let following = Task { await model.follow(every: .milliseconds(10)) }
    defer { following.cancel() }
    func wait(_ done: () -> Bool) async { for _ in 0..<300 where done() == false { try? await Task.sleep(for: .milliseconds(10)) } }
    await wait { model.cloneRows.first?.line == "Receiving objects: 10%" }
    host.current = [ProjectClone(repo: "acme/web", folder: "/p/acme/web", state: .cloning, progress: "Receiving objects: 80%")]
    await wait { model.cloneRows.first?.line == "Receiving objects: 80%" }
    #expect(model.cloneRows.first?.line == "Receiving objects: 80%")
    // the host writes the entry, then stops listing the clone: the project is there when the clone is gone
    try Data(#"{"projects":[{"path":"/p/acme/web","origin":"cloned"}]}"#.utf8).write(to: file.url, options: .atomic)
    host.current = []
    await wait { model.cloneRows.isEmpty && model.rows.count == 1 }
    #expect(model.cloneRows.isEmpty && model.rows.map(\.path) == ["/p/acme/web"])
}

@MainActor @Test func aFailedCloneStaysWithItsReasonUntilItIsDismissedAndIsNotPolledAgain() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let host = CloneHost([ProjectClone(repo: "acme/web", folder: "/p/acme/web", state: .failed, error: "git could not clone acme/web")])
    let model = ProjectsModel(host: host, file: ProjectsFile(folder: folder)) { _ in nil }
    let following = Task { await model.follow(every: .milliseconds(10)) }
    func wait(_ done: () -> Bool) async { for _ in 0..<300 where done() == false { try? await Task.sleep(for: .milliseconds(10)) } }
    await wait { model.cloneRows.count == 1 }
    #expect(model.cloneRows.first?.line == "git could not clone acme/web")
    // a failure is asked for once: nothing is running, so the page does not keep talking to the host
    try await Task.sleep(for: .milliseconds(150))
    following.cancel()
    #expect(host.asked == 1)
    await model.dismissClone("acme/web")
    #expect(model.cloneRows.isEmpty)
}

@MainActor @Test func aHostThatCannotAnswerLeavesTheKnownClonesAsTheyWere() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let host = CloneHost()
    let model = ProjectsModel(host: host, file: ProjectsFile(folder: folder)) { _ in nil }
    try await model.startClone("acme/web", into: nil)
    host.failure = ControlError.closed
    await model.refreshClones()
    #expect(model.cloneRows.count == 1)
}

// MARK: a new project (docs/specs/projects.md, Scope 5)

@MainActor @Test func aNewProjectIsAskedOfTheHostAndIsInTheListWhenItAnswers() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let file = ProjectsFile(folder: folder)
    let host = CloneHost()
    host.registerIn = file
    let model = ProjectsModel(host: host, file: file) { _ in nil }
    #expect(model.rows.isEmpty)
    let made = try await model.createProject("my-app", into: "/Volumes/work")
    #expect(made == "/Volumes/work/local/my-app")
    #expect(host.made.count == 1 && host.made[0].name == "my-app" && host.made[0].parent == "/Volumes/work")
    // the page can open it at once: the file was read again after the answer
    #expect(model.rows.map(\.path) == ["/Volumes/work/local/my-app"])
}

@MainActor @Test func aRefusedNewProjectThrowsTheHostsWordsAndLeavesTheListAlone() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let host = CloneHost()
    host.failure = ControlError.remote(.words("mine is already a project; choose another name"))
    let model = ProjectsModel(host: host, file: ProjectsFile(folder: folder)) { _ in nil }
    await #expect(throws: ControlError.remote(.words("mine is already a project; choose another name"))) { _ = try await model.createProject("mine", into: nil) }
    #expect(model.rows.isEmpty)
}

@MainActor @Test func aFolderThatIsThereOrAProjectOfTheListTakesTheNameOfANewOne() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let file = ProjectsFile(folder: folder)
    try file.add(folder: folder + "/gone")
    let model = ProjectsModel(host: CloneHost(), file: file) { _ in nil }
    model.reload()
    #expect(model.isTaken(folder + "/gone"), "a project whose folder is gone still holds its path")
    #expect(model.isTaken(folder), "a folder that is there")
    #expect(model.isTaken(folder + "/free") == false)
}
