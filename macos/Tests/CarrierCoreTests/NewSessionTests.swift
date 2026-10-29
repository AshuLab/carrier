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
    /// What `agentOptions` lists for each agent (one not listed fails), how often it was asked, and the options each `open` carried.
    var offered: [String: [ChatOption]] = [:]
    var optionAsks: [String] = []
    /// What `agentOptions` lists to invoke, and the commands each `send` invoked.
    var commandsOffered: [String: [ChatCommand]] = [:]
    var sentCommands: [String?] = []
    var openedWith: [[String: String]] = []
    var capabilities: Set<ControlClient.Capability> = [.cloneRepo, .createProject, .githubRepos]
    /// What `githubRepos` answers by page (one not listed is an empty last page) and the pages it was asked for.
    var repoPages: [Int: GithubReposPage] = [:]
    var repoCalls: [Int] = []
    var created: [String] = []
    /// What `cloneRepo` asked for, and whether it ended by being cancelled; while `holdClone` is set it waits for `release` or a cancel.
    var clones: [String] = []
    var cloneCancelled = false
    var holdClone = false
    var release = false
    /// Where the host puts what it clones and makes; a test points it at the config's projects folder, which the real host reads at each request.
    var projects: () -> String = { "/projects" }

    func agents() async throws -> [ChatAgent] { agents }
    func list(archived wanted: Bool) async throws -> [ChatSession] { wanted ? archived : active }
    func agentOptions(_ agent: String) async throws -> AgentOffer {
        optionAsks.append(agent)
        guard let listed = offered[agent] else { throw ControlError.remote("the chat host does not support agentOptions") }
        return AgentOffer(options: listed, commands: commandsOffered[agent] ?? [])
    }
    func send(_ id: String, _ text: String, command: String?) async throws {
        sentCommands.append(command)
        try await send(id, text)
    }
    func open(agent: String, folder: String, worktree: WorktreeRequest?, options: [String: String]) async throws -> String {
        openedWith.append(options)
        return try await open(agent: agent, folder: folder, worktree: worktree)
    }
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
    func capabilities() async throws -> Set<ControlClient.Capability> { capabilities }
    func cloneRepo(_ repo: String) async throws -> ClonedRepo {
        clones.append(repo)
        while holdClone && release == false {
            if Task.isCancelled {
                cloneCancelled = true
                throw CancellationError()
            }
            try? await Task.sleep(for: .milliseconds(2))
        }
        if let error = refuse["cloneRepo"] { throw error }
        return ClonedRepo(folder: "\(projects())/\(repo)", repo: repo, fetched: false)
    }
    func createProject(_ name: String) async throws -> String {
        created.append(name)
        if let error = refuse["createProject"] { throw error }
        return "\(projects())/local/\(name)"
    }
    func githubRepos(page: Int) async throws -> GithubReposPage {
        repoCalls.append(page)
        if let error = refuse["githubRepos"] { throw error }
        return repoPages[page] ?? GithubReposPage(repos: [], hasMore: false)
    }
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

// The workspace popover: its sources, the projects folder, the URL step and the clone.

private func projectsRoot(_ names: [String]) throws -> String {
    let root = NSTemporaryDirectory() + "popover-\(UUID().uuidString)"
    for name in names { try FileManager.default.createDirectory(atPath: root + "/" + name, withIntermediateDirectories: true) }
    return root
}

/// The config file in memory: what `readConfig` gives, what `writeConfig` last got, and a way to make it unwritable.
@MainActor private final class FakeConfig {
    var json: Data?
    var writes = 0
    var unwritable = false
    init(_ text: String? = "{\"repos\": [{\"name\": \"acme/web\"}]}") { json = text.map { Data($0.utf8) } }
    func write(_ data: Data) throws {
        if unwritable { throw CocoaError(.fileWriteNoPermission) }
        json = data
        writes += 1
    }
}

@MainActor private func popover(_ host: FakeChat, projects: String = "/nowhere", config: FakeConfig? = nil) async -> NewSessionModel {
    let config = config ?? FakeConfig()
    let model = NewSessionModel(
        host: host, ensureHost: { true }, log: { _ in }, sleep: { _ in }, projectsFolder: { projects },
        readConfig: { config.json }, writeConfig: { try config.write($0) }
    )
    await model.load()
    return model
}

/// Waits (briefly) for something a task started in the background to happen.
@MainActor private func settle(_ done: () -> Bool) async {
    for _ in 0..<500 where done() == false { try? await Task.sleep(for: .milliseconds(2)) }
}

@MainActor @Test func theMenuListsOpenLocalFolderAndGitHubURLOnlyForAHostThatClones() async {
    let host = FakeChat()
    #expect(await popover(host).sources == [.localFolder, .githubURL, .githubRepos, .newProject])
    host.capabilities = [.cloneRepo, .createProject]
    #expect(await popover(host).sources == [.localFolder, .githubURL, .newProject])
    host.capabilities = [.cloneRepo]
    #expect(await popover(host).sources == [.localFolder, .githubURL])
    host.capabilities = [.createProject]
    #expect(await popover(host).sources == [.localFolder, .newProject])
    host.capabilities = [.fetch]
    #expect(await popover(host).sources == [.localFolder])
}

@MainActor @Test func theMenuListsWhatIsInTheProjectsFolderFromDiskAndSaysWhereItIs() async throws {
    let root = try projectsRoot(["AshuLab/carrier", "local/my-idea"])
    defer { try? FileManager.default.removeItem(atPath: root) }
    let model = await popover(FakeChat(), projects: root)
    #expect(model.projects.isEmpty && model.projectsPath == root)
    model.openPicker()
    #expect(model.projects.map(\.name) == ["AshuLab/carrier", "local/my-idea"] && model.step == .menu)
    await model.choose(folder: model.projects[0].path)
    #expect(model.folder == root + "/AshuLab/carrier" && model.workspace?.branch == "main")
}

@MainActor @Test func theUrlStepDrillsInAndBackAndItsButtonWaitsForOneRepository() async {
    let model = await popover(FakeChat())
    model.openPicker()
    model.show(.url)
    #expect(model.step == .url && model.canCloneNow == false && model.cloneButton == "Clone and use")
    model.urlText = "AshuLab"
    #expect(model.canCloneNow == false)
    model.urlText = "https://github.com/AshuLab/carrier.git"
    #expect(model.canCloneNow && model.reference == "AshuLab/carrier")
    model.show(.menu)
    #expect(model.step == .menu)
}

@MainActor @Test func cloningAsksTheHostSaysCloningWhileItRunsAndThenTheDraftShowsTheFolder() async {
    let host = FakeChat()
    host.holdClone = true
    host.fetched = nil
    let model = await popover(host)
    model.show(.url)
    model.urlText = "AshuLab/carrier"
    await model.choose(folder: "/w/api")
    let running = Task { await model.cloneAndUse() }
    await settle { host.clones.isEmpty == false }
    #expect(host.clones == ["AshuLab/carrier"] && model.cloning == "AshuLab/carrier")
    #expect(model.sentence == "Work in carrier Cloning AshuLab/carrier…" && model.folder == nil && model.canSend == false)
    host.release = true
    #expect(await running.value)
    #expect(model.cloning == nil && model.folder == "/projects/AshuLab/carrier" && model.workspace?.branch == "main" && model.urlText.isEmpty)
    #expect(model.sentence == "Work in carrier on the base folder (main)" && model.offersWorktree)
}

@MainActor @Test func aRepositoryAlreadyInTheProjectsFolderIsSaidBeforeAndTheButtonUpdates() async throws {
    let root = try projectsRoot(["AshuLab/carrier"])
    defer { try? FileManager.default.removeItem(atPath: root) }
    let model = await popover(FakeChat(), projects: root)
    model.openPicker()
    model.urlText = "AshuLab/web"
    #expect(model.alreadyThere == false && model.cloneButton == "Clone and use")
    model.urlText = "github.com/ashulab/Carrier"
    #expect(model.alreadyThere && model.cloneButton == "Update and use")
}

@MainActor @Test func aRefusedCloneIsSaidInWordsTheChipStaysOrangeAndTryAgainWorks() async {
    let host = FakeChat()
    host.refuse["cloneRepo"] = ControlError.remote("AshuLab/nope was not found, or your GitHub login cannot see it")
    let model = await popover(host)
    model.show(.url)
    model.urlText = "AshuLab/nope"
    #expect(await model.cloneAndUse() == false)
    #expect(model.cloneProblem == "AshuLab/nope was not found, or your GitHub login cannot see it")
    #expect(model.folder == nil && model.cloning == nil && model.step == .url && model.cloneButton == "Try again" && model.canCloneNow)
    host.refuse["cloneRepo"] = nil
    #expect(await model.cloneAndUse())
    #expect(model.cloneProblem == nil && model.folder == "/projects/AshuLab/nope")
}

@MainActor @Test func aCloneThatFailsWhileThePopoverIsClosedKeepsItsReasonWhenItReopens() async {
    let host = FakeChat()
    host.refuse["cloneRepo"] = ControlError.remote("The clone took more than ten minutes and was stopped")
    let model = await popover(host)
    model.openPicker()
    model.show(.url)
    model.urlText = "AshuLab/slow"
    #expect(await model.cloneAndUse() == false)
    // the popover was closed while it ran; reopening it must not wipe why the chip is orange
    model.openPicker()
    #expect(model.step == .url && model.cloneProblem == "The clone took more than ten minutes and was stopped" && model.urlText == "AshuLab/slow" && model.cloneButton == "Try again")
    // the next action starts over
    host.refuse["cloneRepo"] = nil
    #expect(await model.cloneAndUse())
    model.openPicker()
    #expect(model.cloneProblem == nil && model.step == .menu)
}

@MainActor @Test func cancelWhileCloningStopsTheRequestAndLeavesTheDraftWithNoWorkspace() async {
    let host = FakeChat()
    host.holdClone = true
    let model = await popover(host)
    model.show(.url)
    model.urlText = "AshuLab/carrier"
    await model.choose(folder: "/w/api")
    let running = Task { await model.cloneAndUse() }
    await settle { model.cloning != nil }
    model.cancelClone()
    #expect(model.cloning == nil && model.folder == nil)
    #expect(await running.value == false)
    await settle { host.cloneCancelled }
    #expect(host.cloneCancelled && model.folder == nil && model.cloneProblem == nil)
}

@MainActor @Test func theNewProjectStepShowsThePathAndItsButtonStaysOffForANameTheHostWouldRefuse() async throws {
    let root = try projectsRoot(["local/taken", "AshuLab/carrier"])
    defer { try? FileManager.default.removeItem(atPath: root) }
    let model = await popover(FakeChat(), projects: root)
    model.openPicker()
    model.show(.project)
    #expect(model.step == .project && model.projectPath == root + "/local/<name>" && model.canCreateNow == false && model.projectNameWarning == nil)
    for bad in [".", "..", ".hidden", "a/b", "../x", "a b", "-x", String(repeating: "a", count: 101)] {
        model.projectName = bad
        #expect(model.canCreateNow == false && model.projectNameWarning != nil, "\(bad)")
    }
    model.projectName = "Taken"
    #expect(model.canCreateNow == false && model.projectNameWarning == "Taken is already a project; choose another name")
    model.projectName = "my-idea.2"
    #expect(model.canCreateNow && model.projectNameWarning == nil && model.projectPath == root + "/local/my-idea.2")
    model.projectName = String(repeating: "a", count: 100)
    #expect(model.canCreateNow)
}

@MainActor @Test func creatingAProjectChoosesItsFolderAndOffersNoWorktreeUntilItHasACommit() async {
    let host = FakeChat()
    host.workspaces["/projects/local/my-idea"] = WorkspaceInfo(folder: "/projects/local/my-idea", branch: "main")
    let model = await popover(host)
    model.show(.project)
    model.projectName = "my-idea"
    #expect(await model.createAndUse())
    #expect(host.created == ["my-idea"] && model.projectName.isEmpty && model.createProblem == nil)
    #expect(model.folder == "/projects/local/my-idea" && model.workspace?.branches.isEmpty == true)
    #expect(model.sentence == "Work in my-idea in the folder (new project, no commits yet: no worktree)")
    #expect(model.offersWorktree == false && model.warning == nil)
    await model.useWorktree(true)
    #expect(model.worktree == false)
    #expect(model.watchNote == nil && model.watchFailed == false)
}

@MainActor @Test func aProjectTheHostRefusesIsSaidInWordsAndTheDraftKeepsItsWorkspace() async {
    let host = FakeChat()
    host.refuse["createProject"] = ControlError.remote("web is already a project; choose another name")
    let model = await popover(host)
    await model.choose(folder: "/w/api")
    model.show(.project)
    model.projectName = "web"
    #expect(await model.createAndUse() == false)
    #expect(model.createProblem == "web is already a project; choose another name" && model.folder == "/w/api" && model.step == .project && model.creating == false)
    model.show(.menu)
    #expect(model.createProblem == nil)
}

@Test func cancellingTheCloneRequestClosesItsConnection() async throws {
    let closed = ConnectionClosed()
    let server = TestServer { connection in
        connection.send("{\"event\":\"hello\",\"protocol\":1,\"pid\":1,\"startedAt\":0,\"version\":\"x\",\"capabilities\":[\"cloneRepo\"]}\n")
        guard connection.readRequestId() != nil else { return }
        closed.requested()
        // the host answers only when the clone ends; what the app does here is close the connection
        if connection.readLine() == nil { closed.closed() }
    }
    defer { server.stop() }
    let call = Task { try await SocketChatHost(socketPath: { server.path }).cloneRepo("AshuLab/carrier") }
    while closed.isRequested == false { try await Task.sleep(for: .milliseconds(2)) }
    call.cancel()
    for _ in 0..<500 where closed.isClosed == false { try await Task.sleep(for: .milliseconds(2)) }
    #expect(closed.isClosed)
    await #expect(throws: ControlError.closed) { try await call.value }
}

private final class ConnectionClosed: @unchecked Sendable {
    private let lock = NSLock()
    private var asked = false
    private var gone = false
    func requested() { lock.lock(); asked = true; lock.unlock() }
    func closed() { lock.lock(); gone = true; lock.unlock() }
    var isRequested: Bool { lock.lock(); defer { lock.unlock() }; return asked }
    var isClosed: Bool { lock.lock(); defer { lock.unlock() }; return gone }
}

/// A host that is not there until `ensureHost` runs: its agents are refused before and answered after.
private final class LateChat: ChatHost, @unchecked Sendable {
    var up = false
    var agentCalls = 0
    func agents() async throws -> [ChatAgent] {
        agentCalls += 1
        guard up else { throw ControlError.closed }
        return [ChatAgent(name: "claude", harness: "claude", found: true)]
    }
    func list(archived: Bool) async throws -> [ChatSession] { [] }
    func open(agent: String, folder: String, worktree: WorktreeRequest?) async throws -> String { opened }
    func workspace(_ folder: String) async throws -> WorkspaceInfo { cleanRepo(folder) }
    func fetch(_ folder: String) async throws -> WorkspaceInfo { cleanRepo(folder) }
    func suggestName(_ folder: String) async throws -> String { "x" }
    func checkName(_ folder: String, _ name: String) async throws -> NameCheck { NameCheck(valid: true, free: true) }
    func send(_ id: String, _ text: String) async throws {}
    func events(_ id: String, after: Int, limit: Int) async throws -> ChatEvents { ChatEvents(events: [], cursor: after) }
    func resume(_ id: String) async throws {}
    func interrupt(_ id: String) async throws {}
    func answer(_ id: String, approval: String, choice: String) async throws {}
    func setOption(_ id: String, option: String, value: String) async throws {}
    func archive(_ id: String, _ archived: Bool) async throws {}
    func delete(_ id: String) async throws {}
    func capabilities() async throws -> Set<ControlClient.Capability> { [] }
    func cloneRepo(_ repo: String) async throws -> ClonedRepo { throw ControlError.closed }
    func createProject(_ name: String) async throws -> String { throw ControlError.closed }
    func githubRepos(page: Int) async throws -> GithubReposPage { throw ControlError.closed }
    func deletePreview(_ ids: [String]) async throws -> [SessionDeletePreview] { [] }
}

@MainActor @Test func openingTheDraftStartsAHostThatIsNotThereAndOffersItsAgents() async {
    let host = LateChat()
    let model = NewSessionModel(host: host, ensureHost: { host.up = true; return true }, log: { _ in }, sleep: { _ in })
    await model.load()
    #expect(host.agentCalls == 2 && model.agents.map(\.name) == ["claude"] && model.agent == "claude")

    // one that does not come up is asked once, says nothing and leaves the draft empty
    let dead = LateChat()
    let none = NewSessionModel(host: dead, ensureHost: { false }, log: { _ in }, sleep: { _ in })
    await none.load()
    #expect(dead.agentCalls == 1 && none.agents.isEmpty)
}

// "Let Carrier watch this repo": on by default, off with the reason, and the config write after the clone.

@MainActor @Test func theWatchBoxIsOnByDefaultAndOffWithItsReasonForAWatchedRepoOrAFolderNameClash() async {
    let model = await popover(FakeChat())
    model.show(.url)
    model.urlText = "AshuLab/carrier"
    #expect(model.watch && model.watching && model.watchProblem == nil)
    model.urlText = "acme/web"
    #expect(model.watching == false && model.watchProblem == "acme/web is already watched")
    model.urlText = "other/web"
    #expect(model.watching == false && model.watchProblem?.contains("same folder name as acme/web") == true)
}

@MainActor @Test func cloningWithTheBoxOnAddsTheRepoToTheConfigKeepingEverythingElseAndSaysItListensFromTheNextStart() async throws {
    let config = FakeConfig("""
    {"note": "kept", "limits": {"maxReviews": 7}, "repos": [{"name": "acme/web", "agents": {"author": {"profile": "p"}}}]}
    """)
    let model = await popover(FakeChat(), config: config)
    model.show(.url)
    model.urlText = "https://github.com/AshuLab/carrier"
    #expect(await model.cloneAndUse())
    let saved = try #require(config.json)
    let file = try #require(try JSONSerialization.jsonObject(with: saved) as? [String: Any])
    let repos = try #require(file["repos"] as? [[String: Any]])
    #expect(repos.map { $0["name"] as? String } == ["acme/web", "AshuLab/carrier"] && repos[0]["agents"] != nil && repos[1].keys.sorted() == ["name"])
    #expect(file["note"] as? String == "kept" && (file["limits"] as? [String: Any])?["maxReviews"] as? Int == 7)
    #expect(model.watchNote == "Carrier will listen to AshuLab/carrier from its next start." && model.watchFailed == false)
    #expect(model.folder == "/projects/AshuLab/carrier")
}

@MainActor @Test func theConfigIsReadAgainJustBeforeTheWrite() async throws {
    let host = FakeChat()
    host.holdClone = true
    let config = FakeConfig()
    let model = await popover(host, config: config)
    model.show(.url)
    model.urlText = "AshuLab/carrier"
    let running = Task { await model.cloneAndUse() }
    await settle { host.clones.isEmpty == false }
    // another tab saves while the clone runs
    config.json = Data(#"{"repos": [{"name": "acme/web"}, {"name": "vemec/encaja"}], "pollIntervalMinutes": 3}"#.utf8)
    host.release = true
    #expect(await running.value)
    let saved = try #require(config.json)
    #expect(configRepoNames(json: saved) == ["acme/web", "vemec/encaja", "AshuLab/carrier"])
    #expect(String(decoding: saved, as: UTF8.self).contains("pollIntervalMinutes"))
}

@MainActor @Test func withTheBoxOffOrNotAllowedTheCloneGoesAheadAndTheConfigIsNotTouched() async {
    let config = FakeConfig()
    let model = await popover(FakeChat(), config: config)
    model.show(.url)
    model.urlText = "AshuLab/carrier"
    model.watch = false
    #expect(await model.cloneAndUse())
    #expect(config.writes == 0 && model.watchNote == nil)
    model.show(.url)
    model.urlText = "acme/web"
    let boxOff = await model.cloneAndUse()
    #expect(model.watch == false && boxOff)
    model.watch = true
    model.show(.url)
    model.urlText = "acme/web"
    #expect(model.watching == false)
    let notAllowed = await model.cloneAndUse()
    #expect(notAllowed)
    #expect(config.writes == 0 && model.watchNote == nil && model.folder == "/projects/acme/web")
}

@MainActor @Test func aConfigThatCannotBeWrittenDoesNotUndoTheCloneAndTheDraftSaysSo() async {
    for config in [FakeConfig("[1]"), FakeConfig(nil), { let c = FakeConfig(); c.unwritable = true; return c }()] {
        let model = await popover(FakeChat(), config: config)
        model.show(.url)
        model.urlText = "AshuLab/carrier"
        #expect(await model.cloneAndUse())
        #expect(model.folder == "/projects/AshuLab/carrier" && model.watchFailed)
        #expect(model.watchNote?.hasPrefix("AshuLab/carrier could not be added to Carrier's list: ") == true)
        #expect(config.writes == 0)
    }
}

@MainActor @Test func theNoteGoesWhenAnotherFolderIsChosen() async {
    let model = await popover(FakeChat())
    model.show(.url)
    model.urlText = "AshuLab/carrier"
    _ = await model.cloneAndUse()
    #expect(model.watchNote != nil)
    await model.choose(folder: "/elsewhere")
    #expect(model.watchNote == nil && model.watchFailed == false)
}

// The footer's Change…: the config write, the refusals, and the next request using the new folder.

@MainActor @Test func changingTheProjectsFolderWritesChatJsonAndTheNextCloneAndNewProjectGoThereWithTheOldFolderUntouchedAndTheEngineConfigAlone() async throws {
    let old = try projectsRoot(["AshuLab/carrier"])
    let new = try projectsRoot([])
    defer { for path in [old, new] { try? FileManager.default.removeItem(atPath: path) } }
    let engine = FakeConfig("{\"repos\": [{\"name\": \"acme/web\"}]}")
    let chat = FakeConfig("{\"projectsFolder\": \"\(old)\", \"logLevel\": \"debug\"}")
    let host = FakeChat()
    host.projects = { projectsFolder(chatJSON: chat.json, carrierFolder: "/Users/x/.carrier", home: NSHomeDirectory()) }
    let model = NewSessionModel(
        host: host, ensureHost: { true }, log: { _ in }, sleep: { _ in }, projectsFolder: host.projects,
        readConfig: { engine.json }, writeConfig: { try engine.write($0) },
        readChatConfig: { chat.json }, writeChatConfig: { try chat.write($0) }, carrierFolder: "/Users/x/.carrier"
    )
    await model.load()
    model.openPicker()
    #expect(model.projectsPath == old && model.projects.map(\.name) == ["AshuLab/carrier"])
    model.changeProjectsFolder(to: new)
    #expect(model.projectsFolderProblem == nil && model.projectsPath == new && model.projects.isEmpty && chat.writes == 1 && engine.writes == 0)
    #expect(String(decoding: chat.json ?? Data(), as: UTF8.self).contains("logLevel"))
    #expect(FileManager.default.fileExists(atPath: old + "/AshuLab/carrier"))
    model.show(.url)
    model.urlText = "acme/web"
    #expect(await model.cloneAndUse())
    #expect(model.folder == new + "/acme/web" && host.clones == ["acme/web"])
    model.show(.project)
    model.projectName = "idea"
    #expect(await model.createAndUse())
    #expect(model.folder == new + "/local/idea")
}

@MainActor private func chatPopover(_ chat: FakeConfig, engine: FakeConfig? = nil, folder: String = "/data/carrier") -> NewSessionModel {
    let engine = engine ?? FakeConfig()
    return NewSessionModel(
        host: FakeChat(), ensureHost: { true }, log: { _ in }, sleep: { _ in },
        projectsFolder: { projectsFolder(chatJSON: chat.json, carrierFolder: folder, home: NSHomeDirectory()) },
        readConfig: { engine.json }, writeConfig: { try engine.write($0) },
        readChatConfig: { chat.json }, writeChatConfig: { try chat.write($0) }, carrierFolder: folder
    )
}

@MainActor @Test func aFolderInsideTheEngineOrTheChatsOwnFoldersIsRefusedBeforeAnythingIsWrittenAndTheOldOneStands() async throws {
    let chat = FakeConfig("{\"projectsFolder\": \"/srv/p\"}")
    let model = chatPopover(chat)
    for folder in ["/data/carrier/engine", "/data/carrier/engine/worktrees/x", "/data/carrier/chat/state", "/data/carrier/chat/worktrees/a", "relative/path"] {
        model.changeProjectsFolder(to: folder)
        #expect(model.projectsFolderProblem?.hasSuffix("The projects folder stays /srv/p.") == true, "\(folder)")
        #expect(chat.writes == 0 && model.projectsPath == "/srv/p")
    }
    #expect(model.projectsFolderProblem == "The projects folder must be an absolute path. The projects folder stays /srv/p.")
    model.changeProjectsFolder(to: "/data/carrier/engine")
    #expect(model.projectsFolderProblem?.contains("Carrier's own engine folder") == true)
    model.openPicker()
    #expect(model.projectsFolderProblem == nil)
}

@MainActor @Test func aChatJsonThatCannotBeReadOrWrittenLeavesTheOldFolderAndSaysSoAndOneThatIsNotThereIsMade() async {
    let unwritable = FakeConfig("{\"projectsFolder\": \"/srv/p\"}")
    unwritable.unwritable = true
    for chat in [FakeConfig("[1]"), unwritable] {
        let model = chatPopover(chat)
        let before = model.projectsPath
        model.changeProjectsFolder(to: "/srv/other")
        #expect(model.projectsFolderProblem?.hasSuffix("The projects folder stays \(before).") == true && model.projectsPath == before && chat.writes == 0)
    }
    let absent = FakeConfig(nil)
    let engine = FakeConfig()
    let model = chatPopover(absent, engine: engine)
    model.changeProjectsFolder(to: "/srv/other")
    #expect(model.projectsFolderProblem == nil && model.projectsPath == "/srv/other" && absent.writes == 1 && engine.writes == 0)
}

// My GitHub repositories: the paged list over `AvailableReposList`, the search, the tag and the watch box, the clone of a row.

private func page(_ names: [String], more: Bool, login: String? = nil) -> GithubReposPage {
    GithubReposPage(repos: names.map { AvailableRepo(name: $0, isPrivate: $0.hasPrefix("AshuLab/")) }, hasMore: more, login: login)
}

@MainActor @Test func theRepositoriesStepReadsPageOneWithTheLoginAndLoadMoreAddsTheNextPageInOrder() async {
    let host = FakeChat()
    host.repoPages = [1: page(["AshuLab/carrier", "acme/web"], more: true, login: "vemec"), 2: page(["vemec/encaja", "acme/web"], more: false)]
    let model = await popover(host)
    await model.showRepos()
    #expect(model.step == .repos && model.login == "vemec" && host.repoCalls == [1])
    #expect(model.repoList.repos.map(\.name) == ["AshuLab/carrier", "acme/web"] && model.repoList.hasMore && model.repoList.blocked == false)
    await model.loadRepos()
    #expect(host.repoCalls == [1, 2] && model.login == "vemec")
    // a repo that moved onto the next page keeps its first place
    #expect(model.repoList.repos.map(\.name) == ["AshuLab/carrier", "acme/web", "vemec/encaja"] && model.repoList.hasMore == false)
}

@MainActor @Test func aPageThatFailsAfterTheFirstKeepsWhatIsLoadedAndTheNextAskTriesItAgain() async {
    let host = FakeChat()
    host.repoPages = [1: page(["AshuLab/carrier"], more: true, login: "vemec"), 2: page(["vemec/encaja"], more: false)]
    let model = await popover(host)
    await model.showRepos()
    host.refuse["githubRepos"] = ControlError.remote("GitHub could not be reached; check the network connection")
    await model.loadRepos()
    #expect(model.reposReason == "GitHub could not be reached; check the network connection" && model.repoList.blocked == false)
    #expect(model.repoList.repos.map(\.name) == ["AshuLab/carrier"] && model.repoList.hasMore && model.login == "vemec")
    host.refuse["githubRepos"] = nil
    await model.loadRepos()
    #expect(host.repoCalls == [1, 2, 2] && model.reposReason == nil && model.repoList.repos.map(\.name) == ["AshuLab/carrier", "vemec/encaja"])
}

@MainActor @Test func aFirstPageThatFailsSaysWhyInWordsAndOpeningTheStepAgainStartsOver() async {
    let host = FakeChat()
    host.refuse["githubRepos"] = ControlError.remote("gh is not signed in to GitHub; run \"gh auth login\"")
    let model = await popover(host)
    await model.showRepos()
    #expect(model.repoList.blocked && model.reposReason == "gh is not signed in to GitHub; run \"gh auth login\"" && model.login == nil)
    host.refuse["githubRepos"] = nil
    host.repoPages = [1: page(["AshuLab/carrier"], more: false, login: "vemec")]
    model.show(.menu)
    await model.showRepos()
    #expect(model.repoList.blocked == false && model.reposReason == nil && model.login == "vemec" && host.repoCalls == [1, 1])
}

@MainActor @Test func theSearchFiltersWhatIsLoadedAndTheRowsCarryTheWatchedTagAndTheReasonTheBoxWouldNotApply() async {
    let host = FakeChat()
    host.repoPages = [1: page(["AshuLab/carrier", "acme/web", "other/web", "vemec/Encaja"], more: false, login: "vemec")]
    let model = await popover(host)  // the config watches acme/web
    await model.showRepos()
    let rows = model.repoRows()
    #expect(rows.map(\.name) == ["AshuLab/carrier", "acme/web", "other/web", "vemec/Encaja"])
    #expect(rows.map(\.watched) == [false, true, false, false] && rows.map(\.isPrivate) == [true, false, false, false])
    #expect(rows[0].cannotWatch == nil && rows[1].cannotWatch == nil && rows[2].cannotWatch?.contains("same folder name as acme/web") == true)
    model.reposQuery = " ENCAJA "
    #expect(model.repoRows().map(\.name) == ["vemec/Encaja"])
    model.reposQuery = "nothing"
    #expect(model.repoRows().isEmpty)
}

@MainActor @Test func choosingARowClonesItLikeTheUrlStepAndAddsItToTheConfigWithTheBoxOn() async throws {
    let host = FakeChat()
    host.repoPages = [1: page(["AshuLab/carrier"], more: false, login: "vemec")]
    let config = FakeConfig()
    let model = await popover(host, config: config)
    await model.showRepos()
    #expect(await model.cloneAndUse(repo: "AshuLab/carrier"))
    #expect(host.clones == ["AshuLab/carrier"] && model.folder == "/projects/AshuLab/carrier" && model.cloning == nil)
    #expect(configRepoNames(json: try #require(config.json)) == ["acme/web", "AshuLab/carrier"])
    #expect(model.watchNote == "Carrier will listen to AshuLab/carrier from its next start.")
}

@MainActor @Test func aRowClonesWithoutTouchingTheConfigWhenTheBoxIsOffOrTheRepoIsWatchedOrClashes() async {
    let host = FakeChat()
    host.repoPages = [1: page(["AshuLab/carrier", "acme/web", "other/web"], more: false)]
    let config = FakeConfig()
    let model = await popover(host, config: config)
    await model.showRepos()
    model.watch = false
    #expect(await model.cloneAndUse(repo: "AshuLab/carrier"))
    model.watch = true
    model.show(.repos)
    #expect(await model.cloneAndUse(repo: "acme/web") && model.watchProblem(for: "acme/web") == "acme/web is already watched")
    #expect(await model.cloneAndUse(repo: "other/web"))
    #expect(config.writes == 0 && model.watchNote == nil && model.folder == "/projects/other/web")
}

@MainActor @Test func aRefusedCloneFromTheListStaysOnTheStepWithItsReasonAndTheListIntact() async {
    let host = FakeChat()
    host.repoPages = [1: page(["AshuLab/carrier"], more: false, login: "vemec")]
    host.refuse["cloneRepo"] = ControlError.remote("The clone took more than ten minutes and was stopped")
    let model = await popover(host)
    await model.showRepos()
    #expect(await model.cloneAndUse(repo: "AshuLab/carrier") == false)
    #expect(model.step == .repos && model.cloneProblem == "The clone took more than ten minutes and was stopped" && model.folder == nil)
    #expect(model.repoList.repos.count == 1 && model.login == "vemec")
}

@MainActor @Test func theStepCannotBeOpenedWhileACloneRuns() async {
    let host = FakeChat()
    host.holdClone = true
    let model = await popover(host)
    model.show(.url)
    model.urlText = "AshuLab/carrier"
    let running = Task { await model.cloneAndUse() }
    await settle { model.cloning != nil }
    await model.showRepos()
    #expect(model.step == .url && host.repoCalls.isEmpty)
    host.release = true
    #expect(await running.value)
}

// MARK: the agent's options before a session exists

private let claudeOptions = [
    ChatOption(id: "model", label: "Model", values: [.init(id: "default", label: "Default"), .init(id: "haiku", label: "Haiku", version: "claude-haiku-5-5")], current: "default"),
    ChatOption(id: "effort", label: "Reasoning effort", values: [.init(id: "low", label: "low"), .init(id: "high", label: "high")], current: "high"),
]

@MainActor @Test func theDraftListsWhatTheChosenAgentOffersAndSendsWhatWasChosen() async {
    let host = FakeChat()
    host.offered["claude"] = claudeOptions
    let model = await draft(host)
    await model.choose(folder: "/w/api")
    #expect(model.agent == "claude" && model.shownOptions.isEmpty)
    await model.loadOptions()
    #expect(host.optionAsks == ["claude"] && optionsPill(model.shownOptions) == "Default · high")
    // a value that is listed is taken, one that is not is not, and what is chosen shows on top of the agent's own values
    model.choose(option: "model", value: "haiku")
    model.choose(option: "model", value: "gpt-5")
    model.choose(option: "speed", value: "fast")
    #expect(model.chosenOptions == ["model": "haiku"] && optionsPill(model.shownOptions) == "Haiku · high")
    model.text = "hello"
    _ = await model.send()
    #expect(host.openedWith == [["model": "haiku"]])
}

@MainActor @Test func aHostThatCannotListLeavesTheDraftWithoutOptionsAndAsksAgainLater() async {
    let host = FakeChat()
    var logged: [String] = []
    let model = await draft(host, log: { logged.append($0) })
    await model.loadOptions()
    #expect(model.shownOptions.isEmpty && model.loadingOptions == false && logged.count == 1)
    host.offered["claude"] = claudeOptions
    await model.loadOptions()
    #expect(host.optionAsks == ["claude", "claude"] && model.shownOptions.count == 2)
    // asking for the same agent again is not another request
    await model.loadOptions()
    #expect(host.optionAsks.count == 2)
}

@MainActor @Test func aFirstMessageThatStartsWithTheNameOfAListedCommandInvokesIt() async {
    let host = FakeChat()
    host.offered["claude"] = claudeOptions
    host.commandsOffered["claude"] = [ChatCommand(id: "review", name: "review", description: "Review a change", argumentHint: "<pr>")]
    let model = await draft(host)
    await model.choose(folder: "/w/api")
    await model.loadOptions()
    #expect(model.agentCommands.map(\.name) == ["review"])
    model.text = "/review 42"
    _ = await model.send()
    #expect(host.sentCommands == ["review"] && host.calls.last == "send \(opened) 42")
    // a slash that names none is a message like any other
    host.calls = []
    model.text = "/nope here"
    _ = await model.send()
    #expect(host.sentCommands == ["review"] && host.calls.last == "send \(opened) /nope here")
}
