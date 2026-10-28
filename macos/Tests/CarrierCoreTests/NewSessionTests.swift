import Foundation
import Testing
@testable import CarrierCore

// The draft of a new session, driven by a fake chat host: the recent folders, the agent chip's availability, open then send,
// a refused open, a failed send and the sentence's text.

private let opened = "5d1f7c3a-0b6e-4a52-9a1d-3c7e8b2f4a01"

private func session(_ id: String, folder: String, base: String? = nil, at: Int, archived: Bool = false) -> ChatSession {
    let workspace = base.map { ",\"workspace\":{\"kind\":\"worktree\",\"base\":\"\($0)\",\"branch\":\"carrier/x\",\"from\":\"main\",\"path\":\"\(folder)\"}" } ?? ""
    let json = """
    {"id":"\(id)","agent":"claude","harness":"claude","folder":"\(folder)","state":"idle","createdAt":0,"lastActiveAt":\(at),"archived":\(archived),"live":true\(workspace)}
    """
    return try! JSONDecoder().decode(ChatSession.self, from: Data(json.utf8))
}

private final class FakeChat: ChatHost, @unchecked Sendable {
    var agents: [ChatAgent] = [ChatAgent(name: "codex", harness: "codex", found: false), ChatAgent(name: "claude", harness: "claude", found: true)]
    var active: [ChatSession] = []
    var archived: [ChatSession] = []
    var calls: [String] = []
    var refuse: [String: Error] = [:]
    /// What `workspace` says of each folder; one not listed is a clean git folder on main.
    var workspaces: [String: WorkspaceInfo] = [:]
    var fetched: WorkspaceInfo?
    var names = ["brave-marine-aiur", "keen-ghost-char"]
    var taken: [String: NameCheck] = [:]
    var opens: [WorktreeRequest?] = []

    func agents() async throws -> [ChatAgent] { agents }
    func list(archived wanted: Bool) async throws -> [ChatSession] { wanted ? archived : active }
    func open(agent: String, folder: String, worktree: WorktreeRequest?) async throws -> String {
        calls.append("open \(agent) \(folder)")
        opens.append(worktree)
        if let error = refuse["open"] { throw error }
        return opened
    }
    func workspace(_ folder: String) async throws -> WorkspaceInfo {
        if let error = refuse["workspace"] { throw error }
        return workspaces[folder] ?? cleanRepo(folder)
    }
    func fetch(_ folder: String) async throws -> WorkspaceInfo {
        if let error = refuse["fetch"] { throw error }
        return fetched ?? cleanRepo(folder)
    }
    func suggestName(_ folder: String) async throws -> String {
        if let error = refuse["suggestName"] { throw error }
        return names.removeFirst()
    }
    func checkName(_ folder: String, _ name: String) async throws -> NameCheck {
        calls.append("checkName \(name)")
        if let error = refuse["checkName"] { throw error }
        return taken[name] ?? NameCheck(valid: true, free: true)
    }
    func send(_ id: String, _ text: String) async throws {
        calls.append("send \(id) \(text)")
        if let error = refuse["send"] { throw error }
    }
    func events(_ id: String, after: Int, limit: Int) async throws -> ChatEvents { ChatEvents(events: [], cursor: after) }
    func resume(_ id: String) async throws {}
    func interrupt(_ id: String) async throws {}
    func answer(_ id: String, approval: String, choice: String) async throws {}
    func setOption(_ id: String, option: String, value: String) async throws {}
    func archive(_ id: String, _ archived: Bool) async throws {}
    func delete(_ id: String) async throws {}
    func deletePreview(_ ids: [String]) async throws -> [SessionDeletePreview] { [] }
}

private func cleanRepo(_ folder: String) -> WorkspaceInfo {
    WorkspaceInfo(
        folder: folder, branch: "main", defaultBranch: "main",
        branches: [.init(name: "main", remote: false), .init(name: "origin/main", remote: true)]
    )
}

@MainActor private func draft(_ host: FakeChat, hostStarts: Bool = true, log: @escaping (String) -> Void = { _ in }) async -> NewSessionModel {
    let model = NewSessionModel(host: host, ensureHost: { hostStarts }, log: log, sleep: { _ in })
    await model.load()
    return model
}

@Test func recentFoldersAreTheDistinctBasesMostRecentFirstAtMostEight() {
    let sessions = [
        session("a", folder: "/w/api", at: 10),
        session("b", folder: "/w/web", at: 30),
        session("c", folder: "/w/carrier-wt/x", base: "/w/carrier", at: 20),
        session("d", folder: "/w/api", at: 40, archived: true),
        session("e", folder: "/w/carrier", at: 5),
    ]
    #expect(recentFolders(sessions) == [
        RecentFolder(name: "api", path: "/w/api"), RecentFolder(name: "web", path: "/w/web"), RecentFolder(name: "carrier", path: "/w/carrier"),
    ])
    let many = (0..<12).map { session("s\($0)", folder: "/w/p\($0)", at: $0) }
    #expect(recentFolders(many).count == 8 && recentFolders(many).first?.path == "/w/p11" && recentFolders(many).last?.path == "/w/p4")
}

@MainActor @Test func theDraftOffersTheRecentFoldersOfActiveAndArchivedSessions() async {
    let host = FakeChat()
    host.active = [session("a", folder: "/w/api", at: 10)]
    host.archived = [session("b", folder: "/w/web", at: 20, archived: true)]
    let model = await draft(host)
    #expect(model.recent.map(\.path) == ["/w/web", "/w/api"])
}

@MainActor @Test func anAgentWithNoBinaryIsListedDisabledAndNotInstalledAndTheFirstFoundOneIsChosen() async {
    let model = await draft(FakeChat())
    #expect(model.agents == [AgentChoice(name: "codex", available: false), AgentChoice(name: "claude", available: true)])
    #expect(model.agents.map(\.note) == ["not installed", nil])
    #expect(model.agent == "claude")
}

@MainActor @Test func theSentenceSaysWhereItWorksAndUntilThenToChooseAWorkspace() async {
    let model = await draft(FakeChat())
    #expect(model.sentence == "Work in Choose a workspace… on the base folder")
    await model.choose(folder: "/w/api")
    #expect(model.sentence == "Work in api on the base folder (main)")
}

@MainActor @Test func theBoxCannotSendWithoutAWorkspaceAnAgentAndAMessage() async {
    let host = FakeChat()
    let model = await draft(host)
    model.text = "hello"
    #expect(model.canSend == false)
    #expect(await model.send() == nil && host.calls.isEmpty)
    await model.choose(folder: "/w/api")
    #expect(model.canSend)
    model.text = "  \n"
    #expect(model.canSend == false)
    model.text = "hello"
    model.agent = nil
    #expect(model.canSend == false)
}

@MainActor @Test func sendingOpensTheSessionWithTheAgentAndFolderAndThenSendsTheMessage() async {
    let host = FakeChat()
    let model = await draft(host)
    await model.choose(folder: "/w/api")
    model.text = " fix the bug \n"
    let id = await model.send()
    #expect(id == opened)
    #expect(host.calls == ["open claude /w/api", "send \(opened) fix the bug"])
    #expect(model.text == "" && model.refusal == nil && model.sending == false && model.takeFailure(of: opened) == nil)
}

@MainActor @Test func aRefusedOpenIsSaidInTheDraftAndKeepsTheMessage() async {
    let host = FakeChat()
    host.refuse["open"] = ControlError.remote("claude is not logged in; run claude once to log in")
    let model = await draft(host)
    await model.choose(folder: "/w/api")
    model.text = "hello"
    #expect(await model.send() == nil)
    #expect(model.refusal == "claude is not logged in; run claude once to log in" && model.text == "hello")
    #expect(host.calls == ["open claude /w/api"])
    #expect(signInLine(refusal: model.refusal ?? "") != nil)
}

@MainActor @Test func aSendThatFailsAfterOpenStillSelectsTheSessionAndHandsOverTheFailure() async {
    let host = FakeChat()
    host.refuse["send"] = ControlError.remote("The message is too long")
    let model = await draft(host)
    await model.choose(folder: "/w/api")
    model.text = "hello"
    #expect(await model.send() == opened)
    #expect(model.refusal == nil)
    #expect(model.takeFailure(of: opened) == FailedFirstSend(text: "hello", reason: "The message is too long"))
    #expect(model.takeFailure(of: opened) == nil)
}

@MainActor @Test func aHostThatCannotStartStopsTheSendBeforeOpen() async {
    let host = FakeChat()
    let model = await draft(host, hostStarts: false)
    await model.choose(folder: "/w/api")
    model.text = "hello"
    #expect(await model.send() == nil)
    #expect(model.refusal == hostNotRunning && host.calls.isEmpty && model.text == "hello")
}

@MainActor @Test func aHostThatGoesAwayIsLoggedAndSaidInWords() async {
    let host = FakeChat()
    host.refuse["open"] = ControlError.closed
    var logged: [String] = []
    let model = await draft(host, log: { logged.append($0) })
    await model.choose(folder: "/w/api")
    model.text = "hello"
    #expect(await model.send() == nil)
    #expect(model.refusal == "The chat host is not answering" && logged.count == 1)
}

@MainActor @Test func aFailedFirstSendShowsInTheConversationWithTryAgain() async {
    let conversation = ConversationModel(host: FakeChat(), sessionId: opened)
    conversation.showRefusal(of: "hello", "The message is too long")
    #expect(conversation.refusal == "The message is too long" && conversation.refusedText == "hello")
}

@Test func theClientOpensWithTheAgentAndFolderInsideJSONStringsAndReadsTheNewId() async throws {
    var lines: [String] = []
    let server = TestServer { connection in
        connection.send("{\"event\":\"hello\",\"protocol\":1,\"pid\":1,\"startedAt\":0,\"version\":\"x\",\"capabilities\":[\"open\"]}\n")
        guard let line = connection.readLine(), let id = (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])?["id"] as? Int else { return }
        lines.append(line)
        connection.send("{\"id\":\(id),\"ok\":true,\"data\":{\"session\":{\"id\":\"\(opened)\",\"agent\":\"claude\"},\"options\":[]}}\n")
    }
    defer { server.stop() }
    let id = try await SocketChatHost(socketPath: { server.path }).open(agent: "claude", folder: "/w/\"odd\"\n/dir", worktree: nil)
    #expect(id == opened)
    let sent = try #require(lines.first.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] })
    #expect(sent["cmd"] as? String == "open" && sent["agent"] as? String == "claude" && sent["folder"] as? String == "/w/\"odd\"\n/dir")
}

// MARK: the worktree half

@MainActor @Test func choosingAFolderAsksTheHostWhatItIsAndTheSentenceAndWarningFollow() async {
    let host = FakeChat()
    host.workspaces["/w/dirty"] = WorkspaceInfo(folder: "/w/dirty", branch: "feat/x", defaultBranch: "main", dirty: 2, branches: [.init(name: "feat/x", remote: false)])
    host.workspaces["/w/plain"] = WorkspaceInfo(folder: "/w/plain", git: false)
    let model = await draft(host)
    await model.choose(folder: "/w/dirty")
    #expect(model.sentence == "Work in dirty on the base folder (feat/x)" && model.offersWorktree)
    #expect(model.warning == "2 uncommitted files in the folder. A worktree keeps them out of the agent's way.")
    await model.choose(folder: "/w/plain")
    #expect(model.sentence == "Work in plain in the folder (not a git repository: no worktree)" && model.offersWorktree == false && model.warning == nil)
    // no worktree to switch to
    await model.useWorktree(true)
    #expect(model.worktree == false)
}

@MainActor @Test func aFolderTheHostWillNotReadIsSaidInWordsAndTheDraftStillWorksInIt() async {
    let host = FakeChat()
    host.refuse["workspace"] = ControlError.remote("That folder is inside Carrier's own folders")
    let model = await draft(host)
    await model.choose(folder: "/w/api")
    #expect(model.workspaceProblem == "That folder is inside Carrier's own folders" && model.workspace == nil)
    #expect(model.sentence == "Work in api on the base folder" && model.offersWorktree == false)
}

@MainActor @Test func switchingToAWorktreeTakesTheHostsSuggestedNameAndTheCheckedOutBranch() async {
    let host = FakeChat()
    let model = await draft(host)
    await model.choose(folder: "/w/api")
    await model.useWorktree(true)
    #expect(model.worktree && model.worktreeName == "brave-marine-aiur" && model.nameState == .free && model.startBranch == "main")
    #expect(model.sentence == "Work in api in a new worktree carrier/brave-marine-aiur from main")
    // the uncommitted files are kept out of the way by the worktree: no warning in this mode
    #expect(model.warning == nil)
    // back to the base folder and again: the name stays
    await model.useWorktree(false)
    await model.useWorktree(true)
    #expect(model.worktreeName == "brave-marine-aiur")
}

@MainActor @Test func theRollAsksForAnotherNameAndAFailureIsSaidAsTheNamesState() async {
    let host = FakeChat()
    let model = await draft(host)
    await model.choose(folder: "/w/api")
    await model.useWorktree(true)
    await model.rollName()
    #expect(model.worktreeName == "keen-ghost-char" && model.nameState == .free)
    host.refuse["suggestName"] = ControlError.remote("Every name that was tried (50) is already taken; type one instead")
    await model.rollName()
    #expect(model.nameState == .problem("Every name that was tried (50) is already taken; type one instead") && model.canSend == false)
}

@MainActor @Test func aTypedNameIsCheckedAfterAPauseAndATakenOneShowsTheHostsReason() async {
    let host = FakeChat()
    host.taken["fix-login"] = NameCheck(valid: true, free: false, reason: "A branch called carrier/fix-login already exists")
    var waits: [Duration] = []
    let model = NewSessionModel(host: host, sleep: { waits.append($0) })
    await model.load()
    await model.choose(folder: "/w/api")
    await model.useWorktree(true)
    // the suggestion is the host's own: it is not asked about again
    await model.verifyName()
    #expect(host.calls.contains("checkName brave-marine-aiur") == false && waits.isEmpty)
    model.worktreeName = "fix-login"
    await model.verifyName()
    #expect(waits == [.milliseconds(400)] && host.calls.last == "checkName fix-login")
    #expect(model.nameState == .problem("A branch called carrier/fix-login already exists"))
    model.text = "hi"
    #expect(model.canSend == false)
    model.worktreeName = "fix-logout"
    await model.verifyName()
    #expect(model.nameState == .free && model.canSend)
}

@MainActor @Test func aNameTypedOverWhileItWasBeingCheckedDropsTheOlderAnswer() async {
    let host = FakeChat()
    host.taken["one"] = NameCheck(valid: true, free: false, reason: "taken")
    var typeOver: (() -> Void)?
    let model = NewSessionModel(host: host, sleep: { _ in typeOver?() })
    await model.load()
    await model.choose(folder: "/w/api")
    await model.useWorktree(true)
    typeOver = { model.worktreeName = "two" }
    model.worktreeName = "one"
    // the person types "two" during the pause: the answer about "one" is not shown, and "two" is checked when the view asks again
    await model.verifyName()
    #expect(model.nameState == .checking)
    typeOver = nil
    await model.verifyName()
    #expect(model.nameState == .free)
}

@MainActor @Test func theHostCannotBeAskedToCheckANameIsSaidInWords() async {
    let host = FakeChat()
    let model = await draft(host)
    await model.choose(folder: "/w/api")
    await model.useWorktree(true)
    model.worktreeName = "typed"
    host.refuse["checkName"] = ControlError.closed
    await model.verifyName()
    #expect(model.nameState == .problem("The chat host is not answering"))
}

@MainActor @Test func theBranchToStartFromCanBePickedAndFetchNowRefreshesTheLists() async {
    let host = FakeChat()
    host.fetched = WorkspaceInfo(
        folder: "/w/api", branch: "main", defaultBranch: "main", branches: [.init(name: "main", remote: false), .init(name: "origin/main", remote: true), .init(name: "origin/new", remote: true)],
        fetchedAt: 1_792_007_200_000)
    let model = await draft(host)
    await model.choose(folder: "/w/api")
    await model.useWorktree(true)
    #expect(model.picker(query: "")?.remote.map(\.name) == ["origin/main"] && model.picker(query: "")?.fetched == "Never fetched")
    model.choose(startBranch: "origin/main")
    #expect(model.startBranch == "origin/main" && model.sentence.hasSuffix("from origin/main"))
    await model.fetchNow()
    #expect(model.picker(query: "")?.remote.map(\.name) == ["origin/main", "origin/new"] && model.fetchProblem == nil)
    #expect(model.startBranch == "origin/main", "a pick survives the fetch")
    host.refuse["fetch"] = ControlError.remote("The fetch of origin failed")
    await model.fetchNow()
    #expect(model.fetchProblem == "The fetch of origin failed" && model.fetching == false)
}

@MainActor @Test func aDetachedFolderWithNoDefaultBranchAsksForTheBranchBeforeSending() async {
    let host = FakeChat()
    host.workspaces["/w/api"] = WorkspaceInfo(folder: "/w/api", branches: [.init(name: "x", remote: false)])
    let model = await draft(host)
    await model.choose(folder: "/w/api")
    await model.useWorktree(true)
    model.text = "hi"
    #expect(model.startBranch == nil && model.canSend == false && model.sentence.hasSuffix("from …"))
    model.choose(startBranch: "x")
    #expect(model.canSend)
}

@MainActor @Test func sendingInAWorktreeOpensWithTheWorktreeRequestAndTheBaseFolderWithNone() async {
    let host = FakeChat()
    let model = await draft(host)
    await model.choose(folder: "/w/api")
    model.text = "one"
    #expect(await model.send() == opened)
    await model.useWorktree(true)
    model.choose(startBranch: "origin/main")
    model.worktreeName = "my-fix"
    model.text = "two"
    #expect(await model.send() == opened)
    #expect(host.opens == [nil, WorktreeRequest(from: "origin/main", name: "my-fix")])
    #expect(host.calls == ["open claude /w/api", "send \(opened) one", "open claude /w/api", "send \(opened) two"])
}

@MainActor @Test func aRefusedWorktreeIsSaidInTheDraftAndKeepsTheMessageAndTheChoice() async {
    let host = FakeChat()
    host.refuse["open"] = ControlError.remote("A folder for that worktree already exists")
    let model = await draft(host)
    await model.choose(folder: "/w/api")
    await model.useWorktree(true)
    model.text = "hello"
    #expect(await model.send() == nil)
    #expect(model.refusal == "A folder for that worktree already exists" && model.text == "hello" && model.worktree && model.worktreeName == "brave-marine-aiur")
}

@MainActor @Test func choosingAnotherFolderStartsTheWorktreeChoiceOver() async {
    let host = FakeChat()
    let model = await draft(host)
    await model.choose(folder: "/w/api")
    await model.useWorktree(true)
    model.choose(startBranch: "origin/main")
    await model.choose(folder: "/w/web")
    #expect(model.worktree == false && model.worktreeName.isEmpty && model.startBranch == "main" && model.nameState == .suggesting)
}

// MARK: the client

@Test func theFixtureHostAnswersTheWorktreeRequestsFromTheGoldenFiles() async throws {
    let server = try FixtureServer(fixtures: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures").path)
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.chatSocketPath })
    let git = try await host.workspace("/Users/dev/carrier")
    #expect(git.git && git.dirty == 3 && git.branch == "main")
    #expect(try await host.workspace("/Users/dev/web").branch == nil)
    #expect(try await host.workspace("/Users/dev/notes").git == false)
    #expect(try await host.workspace("/somewhere/else").git == false)
    #expect(try await host.fetch("/Users/dev/carrier").fetchedAt == 1_792_007_200_000)
    await #expect(throws: ControlError.remote("That folder is not a git repository")) { try await host.fetch("/Users/dev/notes") }
    await #expect(throws: ControlError.remote("The fetch of origin failed")) { try await host.fetch("/Users/dev/work/web") }
    #expect(try await host.suggestName("/Users/dev/carrier") == "brave-marine-aiur")
    #expect(try await host.suggestName("/Users/dev/carrier") == "keen-ghost-char")
    #expect(try await host.checkName("/Users/dev/carrier", "fix-login") == NameCheck(valid: true, free: false, reason: "A branch called carrier/fix-login already exists"))
    #expect(try await host.checkName("/Users/dev/carrier", "free-name") == NameCheck(valid: true, free: true))
}

@Test func openingInAWorktreeThroughTheFixtureHostMakesASessionThatIsListedWithItsBranch() async throws {
    let server = try FixtureServer(fixtures: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures").path)
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.chatSocketPath })
    let id = try await host.open(agent: "claude", folder: "/Users/dev/carrier", worktree: WorktreeRequest(from: "origin/main", name: "my-fix"))
    let made = try #require(try await host.list(archived: false).first { $0.id == id })
    #expect(made.workspace == ChatSession.Workspace(base: "/Users/dev/carrier", branch: "carrier/my-fix") && made.folder.hasSuffix("/my-fix"))
    try await host.send(id, "hello")
    #expect(try await host.events(id, after: 0, limit: 10).events.count == 1)
    // refused as the host does
    await #expect(throws: ControlError.remote("The branch to start from is not one this repository lists")) {
        try await host.open(agent: "claude", folder: "/Users/dev/carrier", worktree: WorktreeRequest(from: "nope", name: "x"))
    }
    await #expect(throws: ControlError.remote("A branch called carrier/fix-login already exists")) {
        try await host.open(agent: "claude", folder: "/Users/dev/carrier", worktree: WorktreeRequest(from: "main", name: "fix-login"))
    }
    await #expect(throws: ControlError.remote("Worktrees need a git repository")) {
        try await host.open(agent: "claude", folder: "/Users/dev/notes", worktree: WorktreeRequest(from: "main"))
    }
}

@Test func theClientPutsTheWorktreeRequestOnTheWireInsideJSONStrings() async throws {
    var lines: [String] = []
    let server = TestServer { connection in
        connection.send("{\"event\":\"hello\",\"protocol\":1,\"pid\":1,\"startedAt\":0,\"version\":\"x\",\"capabilities\":[\"open\"]}\n")
        guard let line = connection.readLine(), let id = (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])?["id"] as? Int else { return }
        lines.append(line)
        connection.send("{\"id\":\(id),\"ok\":true,\"data\":{\"session\":{\"id\":\"\(opened)\"},\"options\":[]}}\n")
    }
    defer { server.stop() }
    _ = try await SocketChatHost(socketPath: { server.path }).open(agent: "claude", folder: "/w/api", worktree: WorktreeRequest(from: "origin/feat\"x\"", name: "my-fix"))
    let sent = try #require(lines.first.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] })
    #expect(sent["worktree"] as? [String: String] == ["from": "origin/feat\"x\"", "name": "my-fix"])
}

@Test func aSessionInTheBaseFolderIsListedByTheRealHostAsKindFolderAndDecodesWithNoWorkspace() throws {
    let json = """
    {"id":"a","agent":"claude","harness":"claude","folder":"/w/api","workspace":{"kind":"folder"},"title":null,"state":"idle","createdAt":1,"lastActiveAt":2,"archived":false,"live":false}
    """
    #expect(try JSONDecoder().decode(ChatSession.self, from: Data(json.utf8)).workspace == nil)
}
