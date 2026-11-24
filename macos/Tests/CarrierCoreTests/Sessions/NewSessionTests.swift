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
    /// Each `fetch` asked: the folder and whether it asked for the freshness window; `fetchGate` holds the answer until the test lets it go.
    var fetches: [(folder: String, ifStale: Bool)] = []
    var fetchGate: (() async -> Void)?
    var names = ["brave-marine-aiur", "keen-ghost-char"]
    /// Holds the answer of `suggestName` until the test lets it go.
    var suggestGate: (() async -> Void)?
    var taken: [String: NameCheck] = [:]
    /// The plan of each `open`.
    var plans: [SessionPlan] = []
    /// What `agentOptions` lists for each agent (one not listed fails) and how often it was asked.
    var offered: [String: [ChatOption]] = [:]
    var optionAsks: [String] = []
    /// What `agentOptions` lists to invoke.
    var commandsOffered: [String: [ChatCommand]] = [:]
    var capabilities: Set<ControlClient.Capability> = [.repoBranches, .createProject, .githubRepos, .plan]
    /// What `health` answers, and the `refresh` flags it was asked with.
    var healthReply = HostHealth(git: .ready, gh: .ready, agents: [])
    var healthAsks: [Bool] = []
    /// What `githubRepos` answers by page (one not listed is an empty last page) and the pages it was asked for.
    var repoPages: [Int: GithubReposPage] = [:]
    var repoCalls: [Int] = []
    /// What `repoBranches` answers by repository (one not listed is refused as for a repository the login cannot see) and what it was asked for.
    var branchesOf: [String: RepoBranches] = [:]
    var branchCalls: [String] = []
    /// The projects folder the draft reads; a test points it at the config's projects folder.
    var projects: () -> String = { "/projects" }

    func agents() async throws -> [ChatAgent] { agents }
    func list(archived wanted: Bool) async throws -> [ChatSession] { wanted ? archived : active }
    /// What a test gives `sessionUpdates` by hand, in place of the list every few milliseconds.
    var given: AsyncStream<SessionsUpdate>?
    /// The list again every few milliseconds, as the host's link gives it every few seconds.
    func sessionUpdates() async -> AsyncStream<SessionsUpdate> {
        if let given = given { return given }
        return AsyncStream { continuation in
            let task = Task {
                while Task.isCancelled == false {
                    let listed = await MainActor.run { self.active }
                    continuation.yield(SessionsUpdate(active: listed, archived: []))
                    try? await Task.sleep(for: .milliseconds(5))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    /// The asks are recorded under a lock: a draft and the model picker may ask while the app's warm-up does.
    private let asksLock = NSLock()
    /// How many asks were waiting for their answer at once, at most.
    private var asksOpen = 0
    private(set) var mostAsksOpen = 0
    func agentOptions(_ agent: String) async throws -> AgentOffer {
        asksLock.withLock { optionAsks.append(agent); asksOpen += 1; mostAsksOpen = max(mostAsksOpen, asksOpen) }
        defer { asksLock.withLock { asksOpen -= 1 } }
        try await Task.sleep(for: .milliseconds(20)) // an answer takes time: asks that overlap show
        guard let listed = offered[agent] else { throw ControlError.remote(.hostLacks("agentOptions")) }
        return AgentOffer(options: listed, commands: commandsOffered[agent] ?? [])
    }
    func open(plan: SessionPlan) async throws -> String {
        calls.append("open \(plan.agent) \(plan.folder ?? "")")
        plans.append(plan)
        if let error = refuse["open"] { throw error }
        return opened
    }
    func workspace(_ folder: String) async throws -> WorkspaceInfo {
        if let error = refuse["workspace"] { throw error }
        return workspaces[folder] ?? cleanRepo(folder)
    }
    func fetch(_ folder: String, ifStale: Bool) async throws -> WorkspaceInfo {
        fetches.append((folder, ifStale))
        await fetchGate?()
        if let error = refuse["fetch"] { throw error }
        return fetched ?? cleanRepo(folder)
    }
    func suggestName(_ folder: String) async throws -> String {
        await suggestGate?()
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
    func answer(_ id: String, approval: String, choice: String, answers: [String: String]?) async throws {}
    func setOption(_ id: String, option: String, value: String) async throws {}
    func archive(_ id: String, _ archived: Bool) async throws {}
    func delete(_ id: String) async throws {}
    func capabilities() async throws -> Set<ControlClient.Capability> { capabilities }
    func repoBranches(_ repo: String) async throws -> RepoBranches {
        branchCalls.append(repo)
        if let error = refuse["repoBranches"] { throw error }
        guard let listed = branchesOf[repo] else { throw ControlError.remote(.words("\(repo) was not found, or your GitHub login cannot see it")) }
        return listed
    }
    func githubRepos(page: Int) async throws -> GithubReposPage {
        repoCalls.append(page)
        if let error = refuse["githubRepos"] { throw error }
        return repoPages[page] ?? GithubReposPage(repos: [], hasMore: false)
    }
    func cloneProject(_ repo: String, into parent: String?) async throws -> ProjectClone {
        calls.append("cloneProject \(repo)")
        throw ControlError.remote(.words("a draft never clones"))
    }
    func newProject(_ name: String, into parent: String?) async throws -> String {
        calls.append("newProject \(name)")
        throw ControlError.remote(.words("a draft never makes a project"))
    }
    func deletePreview(_ ids: [String]) async throws -> [SessionDeletePreview] { [] }
    func health(refresh: Bool) async throws -> HostHealth {
        healthAsks.append(refresh)
        if let error = refuse["health"] { throw error }
        return healthReply
    }
}

private func cleanRepo(_ folder: String) -> WorkspaceInfo {
    WorkspaceInfo(
        folder: folder, branch: "main", defaultBranch: "main",
        branches: [.init(name: "main", remote: false), .init(name: "origin/main", remote: true)]
    )
}

@MainActor private func draft(
    _ host: FakeChat, hostStarts: Bool = true, offers: AgentOfferStore? = nil, log: @escaping (String) -> Void = { _ in }
) async -> NewSessionModel {
    let model = NewSessionModel(host: host, offers: offers, ensureHost: { hostStarts }, log: log, sleep: { _ in })
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
    #expect(model.agents == [AgentChoice(name: "codex", harness: "codex", state: .missing), AgentChoice(name: "claude", harness: "claude", state: .ready)])
    #expect(model.agents.map(\.note) == ["not installed", nil])
    #expect(model.agent == "claude")
}

@MainActor @Test func theSentenceSaysWhereItWorksAndUntilThenToChooseAWorkspace() async {
    let model = await draft(FakeChat())
    #expect(model.sentence == "Work in Choose a workspace… on the base folder")
    await model.choose(folder: "/w/api")
    #expect(model.sentence == "Work in api on the base folder (main)")
}

@MainActor @Test func aWorkspacePlusOpensTheDraftWithThatFolderChosenAndEveryLoadAfterItIsBlank() async {
    let model = await draft(FakeChat())
    model.start(in: "/w/api")
    #expect(model.starts == 1)
    await model.load()
    #expect(model.folder == "/w/api")
    await model.load()
    #expect(model.folder == nil)
}

@MainActor @Test func aSessionsNewSessionOnItsBranchOpensTheDraftWithAWorktreeCutFromThatBranch() async {
    let host = FakeChat()
    host.workspaces["/w/api"] = WorkspaceInfo(
        folder: "/w/api", branch: "main", defaultBranch: "main",
        branches: [.init(name: "main", remote: false), .init(name: "carrier/fix-x", remote: false), .init(name: "origin/carrier/only-remote", remote: true)])
    let model = await draft(host)
    model.start(in: "/w/api", branch: "carrier/fix-x")
    await model.load()
    #expect(model.folder == "/w/api" && model.worktree && model.startBranch == "carrier/fix-x" && model.startTab == .local)
    // a branch only the remote has is cut from the remote side
    model.start(in: "/w/api", branch: "carrier/only-remote")
    await model.load()
    #expect(model.worktree && model.startBranch == "carrier/only-remote" && model.startTab == .remote)
    // a branch the folder no longer has leaves the draft as the project sets it, and the next load is blank
    model.start(in: "/w/api", branch: "gone")
    await model.load()
    #expect(model.folder == "/w/api" && model.worktree == false && model.startBranch == "main")
    await model.load()
    #expect(model.folder == nil)
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

@MainActor @Test func sendingMakesOneOpenWithThePlanAndNothingElse() async {
    let host = FakeChat()
    let model = await draft(host)
    await model.choose(folder: "/w/api")
    model.text = " fix the bug \n"
    let id = await model.send()
    #expect(id == opened)
    #expect(host.calls == ["open claude /w/api"])
    #expect(host.plans == [SessionPlan(agent: "claude", folder: "/w/api", text: "fix the bug")])
    #expect(model.text == "" && model.refusal == nil && model.sending == false)
    // the message goes to the conversation that shows the session, once
    #expect(model.takeFirstMessage(of: opened) == "fix the bug" && model.takeFirstMessage(of: opened) == nil)
}

@MainActor @Test func aRefusedOpenIsSaidInTheDraftAndKeepsTheMessage() async {
    let host = FakeChat()
    host.refuse["open"] = ControlError.remote(Refusal(code: "agent.notLoggedIn", params: ["agent": "claude"], text: "claude is not logged in; run claude once to log in"))
    let model = await draft(host)
    await model.choose(folder: "/w/api")
    model.text = "hello"
    #expect(await model.send() == nil)
    #expect(model.refusal?.text == "claude is not logged in; run claude once to log in" && model.text == "hello")
    #expect(host.calls == ["open claude /w/api"])
    #expect(signInLine(refusal: model.refusal ?? .words("")) != nil)
}

@MainActor @Test func aHostThatDoesNotListPlanIsSaidToBeOlderAndSendsNothing() async {
    let host = FakeChat()
    host.capabilities = [.cloneRepo]
    let model = await draft(host)
    await model.choose(folder: "/w/api")
    model.text = "hello"
    #expect(model.hostOlder && model.canSend == false && NewSessionModel.olderHostNotice.contains("Restart"))
    #expect(await model.send() == nil)
    #expect(host.calls.isEmpty && model.text == "hello")
}

@MainActor @Test func theSendAsksTheHostForPlanAgainSoAHostReplacedByAnOlderOneIsFoundOut() async {
    let host = FakeChat()
    let model = await draft(host)
    await model.choose(folder: "/w/api")
    model.text = "hello"
    #expect(model.hostOlder == false && model.canSend)
    host.capabilities = []
    #expect(await model.send() == nil)
    #expect(model.hostOlder && host.calls.isEmpty && model.text == "hello")
}

@MainActor @Test func aHostThatCannotStartStopsTheSendBeforeOpen() async {
    let host = FakeChat()
    let model = await draft(host, hostStarts: false)
    await model.choose(folder: "/w/api")
    model.text = "hello"
    #expect(await model.send() == nil)
    #expect(model.refusal == .hostNotRunning && host.calls.isEmpty && model.text == "hello")
}

@MainActor @Test func aHostThatGoesAwayIsLoggedAndSaidInWords() async {
    let host = FakeChat()
    host.refuse["open"] = ControlError.closed
    var logged: [String] = []
    let model = await draft(host, log: { logged.append($0) })
    await model.choose(folder: "/w/api")
    model.text = "hello"
    #expect(await model.send() == nil)
    #expect(model.refusal == .hostNotAnswering && logged.count == 1)
}

@Test func theClientOpensWithThePlanInsideJSONStringsAndReadsTheNewId() async throws {
    var lines: [String] = []
    let server = TestServer { connection in
        connection.send("{\"event\":\"hello\",\"protocol\":1,\"pid\":1,\"startedAt\":0,\"version\":\"x\",\"capabilities\":[\"plan\"]}\n")
        guard let line = connection.readLine(), let id = (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])?["id"] as? Int else { return }
        lines.append(line)
        connection.send("{\"id\":\(id),\"ok\":true,\"data\":{\"session\":{\"id\":\"\(opened)\",\"agent\":\"claude\"},\"options\":[]}}\n")
    }
    defer { server.stop() }
    let plan = SessionPlan(agent: "claude", folder: "/w/\"odd\"\n/dir", options: ["model": "haiku"], text: "say \"hi\"\nthen stop")
    let id = try await SocketChatHost(socketPath: { server.path }).open(plan: plan)
    #expect(id == opened)
    let sent = try #require(lines.first.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] })
    #expect(sent["cmd"] as? String == "open" && sent.keys.sorted() == ["cmd", "id", "plan"])
    let wired = try #require(sent["plan"] as? [String: Any])
    #expect(wired["agent"] as? String == "claude" && wired["text"] as? String == "say \"hi\"\nthen stop" && wired["options"] as? [String: String] == ["model": "haiku"])
    #expect(wired["workspace"] as? [String: String] == ["kind": "folder", "folder": "/w/\"odd\"\n/dir"] && wired["branch"] == nil && wired["worktree"] == nil)
}

@Test func aProjectPlanGoesOnTheWireWithItsNameAndNoBranchNorWorktree() async throws {
    var lines: [String] = []
    let server = TestServer { connection in
        connection.send("{\"event\":\"hello\",\"protocol\":1,\"pid\":1,\"startedAt\":0,\"version\":\"x\",\"capabilities\":[\"plan\"]}\n")
        guard let line = connection.readLine(), let id = (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])?["id"] as? Int else { return }
        lines.append(line)
        connection.send("{\"id\":\(id),\"ok\":true,\"data\":{\"session\":{\"id\":\"\(opened)\",\"agent\":\"claude\"},\"options\":[]}}\n")
    }
    defer { server.stop() }
    _ = try await SocketChatHost(socketPath: { server.path }).open(plan: SessionPlan(agent: "claude", workspace: .newProject("my-app"), text: "hi"))
    let sent = try #require(lines.first.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] })
    let wired = try #require(sent["plan"] as? [String: Any])
    #expect(wired["workspace"] as? [String: String] == ["kind": "project", "name": "my-app"] && wired["branch"] == nil && wired["worktree"] == nil)
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
    host.refuse["workspace"] = ControlError.remote(.words("That folder is inside Carrier's own folders"))
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
    // the setting says Remote when the file says nothing, so the branch is cut from its copy on origin
    #expect(model.sentence == "Work in api in a new worktree carrier/brave-marine-aiur from origin/main")
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
    host.refuse["suggestName"] = ControlError.remote(.words("Every name that was tried (50) is already taken; type one instead"))
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
    host.refuse["fetch"] = ControlError.remote(.words("The fetch of origin failed"))
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
    await model.choose(folder: "/w/api")
    await model.useWorktree(true)
    model.choose(startBranch: "origin/main")
    model.worktreeName = "my-fix"
    model.text = "two"
    #expect(await model.send() == opened)
    #expect(host.plans.map(\.worktree) == [nil, WorktreeRequest(from: "origin/main", name: "my-fix")] && host.plans.map(\.text) == ["one", "two"])
    #expect(host.calls == ["open claude /w/api", "open claude /w/api"])
}

@MainActor @Test func pickingAnotherBranchSaysTheFolderBranchWillChangeAndSendsItInThePlan() async {
    let host = FakeChat()
    host.workspaces["/w/clean"] = WorkspaceInfo(folder: "/w/clean", branch: "main", dirty: 0, branches: [.init(name: "main", remote: false), .init(name: "feat/x", remote: false)])
    let model = await draft(host)
    await model.choose(folder: "/w/clean")
    // nothing picked, or the checked-out branch picked: the folder keeps its branch and says nothing
    #expect(branchStep(model) == nil && model.branchChange == nil)
    model.choose(startBranch: "main")
    #expect(branchStep(model) == nil)
    model.choose(startBranch: "feat/x")
    #expect(branchStep(model)?.parts == [.text("Switches the folder from "), .code("main"), .text(" to "), .code("feat/x"), .text(" when you send.")])
    #expect(model.warning == nil)
    model.text = "go"
    #expect(await model.send() == opened)
    #expect(host.plans.map(\.branch) == ["feat/x"] && host.plans.map(\.worktree) == [nil])
}

/// The step that says the folder's branch will be switched, nil when it will not.
@MainActor private func branchStep(_ model: NewSessionModel) -> SendStep? { model.sendSteps.first { $0.title == "Change the folder's branch" } }

@MainActor @Test func aFolderWithUncommittedChangesWarnsThatTheBranchChangeWillFailAndSendingIsStillAllowed() async {
    let host = FakeChat()
    host.workspaces["/w/dirty"] = WorkspaceInfo(folder: "/w/dirty", branch: "main", dirty: 2, branches: [.init(name: "main", remote: false), .init(name: "feat/x", remote: false)])
    let model = await draft(host)
    await model.choose(folder: "/w/dirty")
    // no change picked: the worktree way out is offered
    #expect(model.warning == "2 uncommitted files in the folder. A worktree keeps them out of the agent's way.")
    model.choose(startBranch: "feat/x")
    #expect(branchStep(model)?.parts == [.text("Switches the folder from "), .code("main"), .text(" to "), .code("feat/x"), .text(" when you send.")])
    #expect(model.warning == "2 uncommitted files in the folder, so changing its branch will fail and it keeps the branch it is on. Save the work first, or use a worktree.")
    model.text = "go"
    #expect(model.canSend)
    // a worktree is cut from the pick and changes no folder: no branch change, and the pick is the worktree's start
    await model.useWorktree(true)
    #expect(branchStep(model) == nil && model.warning == nil)
    model.worktreeName = "my-fix"
    #expect(await model.send() == opened)
    #expect(host.plans.map(\.branch) == [nil] && host.plans.map(\.worktree) == [WorktreeRequest(from: "feat/x", name: "my-fix")])
}

@Test func thePlanPutsTheBranchOnTheWireWithNoWorktree() async throws {
    var lines: [String] = []
    let server = TestServer { connection in
        connection.send("{\"event\":\"hello\",\"protocol\":1,\"pid\":1,\"startedAt\":0,\"version\":\"x\",\"capabilities\":[\"plan\"]}\n")
        guard let line = connection.readLine(), let id = (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])?["id"] as? Int else { return }
        lines.append(line)
        connection.send("{\"id\":\(id),\"ok\":true,\"data\":{\"session\":{\"id\":\"\(opened)\"},\"options\":[]}}\n")
    }
    defer { server.stop() }
    _ = try await SocketChatHost(socketPath: { server.path }).open(plan: SessionPlan(agent: "claude", folder: "/w/api", branch: "feat/x", text: "hi"))
    let sent = try #require(lines.first.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] })
    let wired = try #require(sent["plan"] as? [String: Any])
    #expect(wired["branch"] as? String == "feat/x" && wired["worktree"] == nil)
}

@MainActor @Test func aRefusedWorktreeIsSaidInTheDraftAndKeepsTheMessageAndTheChoice() async {
    let host = FakeChat()
    host.refuse["open"] = ControlError.remote(.words("A folder for that worktree already exists"))
    let model = await draft(host)
    await model.choose(folder: "/w/api")
    await model.useWorktree(true)
    model.text = "hello"
    #expect(await model.send() == nil)
    #expect(model.refusal?.text == "A folder for that worktree already exists" && model.text == "hello" && model.worktree && model.worktreeName == "brave-marine-aiur")
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

@MainActor @Test func theDraftIsBlankAfterLoadWhateverWasChosenBefore() async {
    let host = FakeChat()
    let model = await draft(host)
    await model.choose(folder: "/w/api")
    await model.useWorktree(true)
    model.choose(startBranch: "origin/main")
    model.text = "half a thought"
    await model.load()
    #expect(model.folder == nil && model.workspace == nil && model.worktree == false && model.worktreeName.isEmpty && model.picked == nil && model.text.isEmpty)
    #expect(model.sentence == "Work in Choose a workspace… on the base folder")
}

@MainActor @Test func theClearButtonDropsTheWorkspaceAndWhatDependsOnItButKeepsTheText() async {
    let host = FakeChat()
    let model = await draft(host)
    await model.choose(folder: "/w/api")
    await model.useWorktree(true)
    model.choose(startBranch: "origin/main")
    model.text = "hello"
    model.clearWorkspace()
    #expect(model.folder == nil && model.workspace == nil && model.worktree == false && model.worktreeName.isEmpty && model.picked == nil && model.canSend == false)
    #expect(model.text == "hello")
}

@MainActor @Test func afterASendTheDraftIsBlankSoTheNextSendDoesNotCarryTheOldWorkspaceOrWorktree() async {
    let host = FakeChat()
    let model = await draft(host)
    await model.choose(folder: "/w/api")
    await model.useWorktree(true)
    model.text = "first"
    #expect(await model.send() == opened)
    #expect(model.folder == nil && model.worktree == false && model.worktreeName.isEmpty && model.text.isEmpty)
    model.text = "second"
    #expect(model.canSend == false)
    #expect(await model.send() == nil)
    #expect(host.calls.filter { $0.hasPrefix("open") }.count == 1)
}

// MARK: the client

@Test func theFixtureHostAnswersTheWorktreeRequestsFromTheGoldenFiles() async throws {
    let server = try FixtureServer(fixtures: testPaths().fixtures.path)
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.chatSocketPath })
    let git = try await host.workspace("/Users/dev/carrier")
    #expect(git.git && git.dirty == 3 && git.branch == "main")
    #expect(try await host.workspace("/Users/dev/web").branch == nil)
    #expect(try await host.workspace("/Users/dev/notes").git == false)
    #expect(try await host.workspace("/somewhere/else").git == false)
    #expect(try await host.fetch("/Users/dev/carrier", ifStale: false).fetchedAt == 1_792_007_200_000)
    #expect(try await host.fetch("/Users/dev/carrier", ifStale: true).branches.first?.behind == 12, "the fixture host takes ifStale and answers as a current one")
    await #expect(throws: ControlError.remote(Refusal(code: "workspace.notGit", text: "That folder is not a git repository"))) { try await host.fetch("/Users/dev/notes", ifStale: true) }
    await #expect(throws: ControlError.remote(Refusal(code: "workspace.fetchFailed", text: "The fetch of origin failed"))) { try await host.fetch("/Users/dev/work/web", ifStale: true) }
    #expect(try await host.suggestName("/Users/dev/carrier") == "brave-marine-aiur")
    #expect(try await host.suggestName("/Users/dev/carrier") == "keen-ghost-char")
    #expect(try await host.checkName("/Users/dev/carrier", "fix-login") == NameCheck(valid: true, free: false, reason: "A branch called carrier/fix-login already exists"))
    #expect(try await host.checkName("/Users/dev/carrier", "free-name") == NameCheck(valid: true, free: true))
}

@Test func openingInAWorktreeThroughTheFixtureHostMakesASessionThatIsListedWithItsBranch() async throws {
    let server = try FixtureServer(fixtures: testPaths().fixtures.path)
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.chatSocketPath })
    func plan(_ folder: String, _ worktree: WorktreeRequest?) -> SessionPlan { SessionPlan(agent: "claude", folder: folder, worktree: worktree, text: "hello") }
    let id = try await host.open(plan: plan("/Users/dev/carrier", WorktreeRequest(from: "origin/main", name: "my-fix")))
    let made = try #require(try await host.list(archived: false).first { $0.id == id })
    #expect(made.workspace == ChatSession.Workspace(base: "/Users/dev/carrier", branch: "carrier/my-fix", from: "origin/main") && made.folder.hasSuffix("/my-fix"))
    #expect(try await host.events(id, after: 0, limit: 10).events.map(\.kind) == ["step", "step", "user"])
    // refused as the host does
    await #expect(throws: ControlError.remote(Refusal(code: "worktree.startNotListed", text: "The branch to start from is not one this repository lists"))) {
        try await host.open(plan: plan("/Users/dev/carrier", WorktreeRequest(from: "nope", name: "x")))
    }
    await #expect(throws: ControlError.remote(Refusal(code: "worktree.name.branchExists", text: "A branch called carrier/fix-login already exists"))) {
        try await host.open(plan: plan("/Users/dev/carrier", WorktreeRequest(from: "main", name: "fix-login")))
    }
    await #expect(throws: ControlError.remote(Refusal(code: "worktree.notGit", text: "Worktrees need a git repository"))) {
        try await host.open(plan: plan("/Users/dev/notes", WorktreeRequest(from: "main")))
    }
}

@Test func theClientPutsTheWorktreeRequestOnTheWireInsideJSONStrings() async throws {
    var lines: [String] = []
    let server = TestServer { connection in
        connection.send("{\"event\":\"hello\",\"protocol\":1,\"pid\":1,\"startedAt\":0,\"version\":\"x\",\"capabilities\":[\"plan\"]}\n")
        guard let line = connection.readLine(), let id = (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])?["id"] as? Int else { return }
        lines.append(line)
        connection.send("{\"id\":\(id),\"ok\":true,\"data\":{\"session\":{\"id\":\"\(opened)\"},\"options\":[]}}\n")
    }
    defer { server.stop() }
    _ = try await SocketChatHost(socketPath: { server.path }).open(plan: SessionPlan(agent: "claude", folder: "/w/api", worktree: WorktreeRequest(from: "origin/feat\"x\"", name: "my-fix"), text: "hi"))
    let sent = try #require(lines.first.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] })
    let wired = try #require(sent["plan"] as? [String: Any])
    #expect(wired["branch"] as? String == "origin/feat\"x\"" && wired["worktree"] as? [String: String] == ["name": "my-fix"])
}

@Test func aSessionInTheBaseFolderIsListedByTheRealHostAsKindFolderAndDecodesWithNoWorkspace() throws {
    let json = """
    {"id":"a","agent":"claude","harness":"claude","folder":"/w/api","workspace":{"kind":"folder"},"title":null,"state":"idle","createdAt":1,"lastActiveAt":2,"archived":false,"live":false}
    """
    #expect(try JSONDecoder().decode(ChatSession.self, from: Data(json.utf8)).workspace == nil)
}

// The sheet New session opens: what choosing fills, the repository chosen, the watch choice and the clone when the message is sent.

private func projectsRoot(_ names: [String]) throws -> String {
    let root = NSTemporaryDirectory() + "chooser-\(UUID().uuidString)"
    for name in names { try FileManager.default.createDirectory(atPath: root + "/" + name, withIntermediateDirectories: true) }
    return root
}

/// The config file in memory, and the engine that changes it: what `readConfig` gives, what `send` was asked (`sent`), what the engine answers, and a way to make it refuse.
private final class FakeConfig {
    var json: Data?
    var sent: [EngineConfigChange] = []
    var writes: Int { sent.count }
    var unwritable = false
    var reply = EngineConfigReply(engine: .applied)
    var failure: Error?
    init(_ text: String? = "{\"repos\": [{\"name\": \"acme/web\"}]}") { json = text.map { Data($0.utf8) } }
    /// The engine: it keeps a repo's own fields and every other key, as `setWatchedRepos` does.
    var send: SendEngineConfig {
        { [self] change in
            if unwritable { throw ControlError.remote(.words("the config file is not writable")) }
            if let failure { throw failure }
            guard case .watchedRepos(let names) = change else { throw ControlError.badLine }
            var file = (try? JSONSerialization.jsonObject(with: json ?? Data())) as? [String: Any] ?? [:]
            let kept = file["repos"] as? [[String: Any]] ?? []
            file["repos"] = names.map { name in kept.first { $0["name"] as? String == name } ?? ["name": name] }
            json = try? JSONSerialization.data(withJSONObject: file)
            sent.append(change)
            return reply
        }
    }
}

@MainActor private func chosenDraft(_ host: FakeChat, projects: String = "/nowhere", config: FakeConfig? = nil) async -> NewSessionModel {
    let config = config ?? FakeConfig()
    let model = NewSessionModel(
        host: host, ensureHost: { true }, log: { _ in }, sleep: { _ in }, projectsFolder: { projects },
        readConfig: { config.json }, send: config.send, status: ReloadStatus(reload: { .nobody })
    )
    await model.load()
    return model
}

/// Waits (briefly) for something a task started in the background to happen.
@MainActor private func settle(_ done: () -> Bool) async {
    for _ in 0..<500 where done() == false { try? await Task.sleep(for: .milliseconds(2)) }
}

/// What the sheet New session opens lists for `query`, as the app draws it, with the projects the test gives and the person's repositories.
@MainActor private func sheet(_ model: NewSessionModel, _ query: String = "", projects: [ProjectRow] = [], repos: [String] = []) -> ProjectSheetState {
    var github = ProjectSheetGithub(defaultParent: model.projectsPath)
    github.repos = repos.map { AvailableRepo(name: $0, isPrivate: false) }
    github.watched = model.watched
    return projectSheetState(mode: .newSession, query: query, recent: model.recent, projects: projects, github: github, home: "/Users/nobody")
}

@MainActor @Test func theSheetListsTheProjectsThatAreNotHiddenFirstThenSuggestedFoldersThenTheRepositories() async {
    let host = FakeChat()
    host.active = [session("a", folder: "/w/api", at: 3), session("b", folder: "/w/web", at: 2), session("c", folder: "/w/old", at: 1)]
    let model = await chosenDraft(host)
    model.openPicker()
    let projects = [
        ProjectRow(path: "/w/api", name: "API", repo: "acme/api"),
        ProjectRow(path: "/w/old", name: "Old", repo: nil, hidden: true),
    ]
    let state = sheet(model, projects: projects, repos: ["acme/web", "vemec/encaja"])
    #expect(state.sections.map(\.title) == ["Projects", "Suggested folders", "Your repositories"])
    // the project shows with its tile, name and folder; the hidden one and its folder are not offered; a project's folder is not suggested again
    #expect(state.sections[0].items.map(\.title) == ["API"] && state.sections[0].items.map(\.detail) == ["/w/api"])
    #expect(state.sections[0].items[0].tile == projects[0].tile)
    #expect(state.sections[1].items.map(\.title) == ["web"])
    #expect(state.sections[2].items.map(\.title) == ["acme/web", "vemec/encaja"])
    #expect(state.items.map(\.actionTitle) == ["Use", "Use", "Use", "Use"])
}

@MainActor @Test func choosingFromTheSheetOnlyFillsThePlanAndNothingIsClonedMadeOrWrittenBeforeTheFirstMessage() async throws {
    let root = try projectsRoot([])
    defer { try? FileManager.default.removeItem(atPath: root) }
    let host = FakeChat()
    host.branchesOf["acme/web"] = RepoBranches(defaultBranch: "main", branches: ["main"])
    let config = FakeConfig()
    let model = await chosenDraft(host, projects: root, config: config)
    model.openPicker()
    let project = ProjectRow(path: "/w/api", name: "API", repo: "acme/api")

    // a project and a suggested folder fill the plan with a folder
    await model.choose(try #require(sheet(model, projects: [project]).sections.first?.items.first))
    #expect(model.folder == "/w/api" && model.repo == nil && model.newProject == nil)
    await model.choose(try #require(sheet(model, "/Users/nobody/elsewhere").firstResult))
    #expect(model.folder == "/Users/nobody/elsewhere" && model.repo == nil)

    // a repository to clone fills it with a repository and says when it is cloned: the destination is the projects folder, and Choose… is not offered
    let repo = try #require(sheet(model, "acme/web").firstResult)
    #expect(repo.destination?.line == "Cloned into \(root)/acme/web when you send the first message" && repo.destination?.canChoose == false)
    await model.choose(repo)
    #expect(model.repo == "acme/web" && model.toClone && model.folder == root + "/acme/web")

    // a new project fills it with a new project
    model.choose(newProject: "my-idea")
    #expect(model.newProject == "my-idea" && model.folder == root + "/local/my-idea" && model.repo == nil)

    // nothing was asked of the host but what the draft shows, nothing was cloned or made, and nothing was written
    #expect(host.calls.isEmpty && config.writes == 0)
    #expect(FileManager.default.fileExists(atPath: root + "/acme") == false && FileManager.default.fileExists(atPath: root + "/local") == false)
    #expect(host.plans.isEmpty)

    // the first message is what sends the plan
    model.text = "hello"
    #expect(await model.send() == opened)
    #expect(host.plans == [SessionPlan(agent: "claude", workspace: .newProject("my-idea"), text: "hello")])
}

@MainActor @Test func aFolderThatIsNotAProjectOffersAddAsProjectWhichWritesAnAddedEntryAndThenGoes() async throws {
    let carrier = NSTemporaryDirectory() + "carrier-" + UUID().uuidString
    let folder = NSTemporaryDirectory() + "plain-" + UUID().uuidString
    try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(atPath: carrier)
        try? FileManager.default.removeItem(atPath: folder)
    }
    let file = ProjectsFile(folder: carrier)
    let model = NewSessionModel(host: FakeChat(), ensureHost: { true }, log: { _ in }, sleep: { _ in }, projects: ProjectsModel(host: FakeChat(), file: file) { _ in nil })
    #expect(model.offersAddAsProject == false) // nothing chosen
    await model.choose(folder: folder)
    #expect(model.offersAddAsProject)
    model.addAsProject()
    #expect(model.offersAddAsProject == false && model.addProjectProblem == nil)
    let entries = try file.read()
    #expect(entries.map(\.path) == [folder] && entries[0].origin == "added")
    // a project chosen again, or one that was added elsewhere, offers nothing
    await model.choose(folder: folder)
    #expect(model.offersAddAsProject == false)
}

@MainActor @Test func aRepositoryOrANewProjectOffersNoAddAsProjectAndAFileThatCannotBeWrittenSaysWhy() async throws {
    let carrier = NSTemporaryDirectory() + "carrier-" + UUID().uuidString
    let folder = NSTemporaryDirectory() + "plain-" + UUID().uuidString
    try FileManager.default.createDirectory(atPath: carrier, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(atPath: carrier)
        try? FileManager.default.removeItem(atPath: folder)
    }
    let file = ProjectsFile(folder: carrier)
    let model = NewSessionModel(host: FakeChat(), ensureHost: { true }, log: { _ in }, sleep: { _ in }, projectsFolder: { "/nowhere" }, projects: ProjectsModel(host: FakeChat(), file: file) { _ in nil })
    model.choose(newProject: "my-idea")
    #expect(model.offersAddAsProject == false) // the host registers a new project itself
    await model.choose(repo: "acme/web")
    #expect(model.offersAddAsProject == false)
    try Data("{ nope".utf8).write(to: file.url)
    await model.choose(folder: folder)
    #expect(model.offersAddAsProject)
    model.addAsProject()
    #expect(model.addProjectProblem != nil && model.offersAddAsProject)
    #expect(try String(contentsOf: file.url, encoding: .utf8) == "{ nope")
}

@MainActor @Test func aRepositoryToCloneOffersToWatchItOnByDefaultAndSaysWhyItCannotBe() async throws {
    let model = await chosenDraft(FakeChat())  // the config watches acme/web
    model.openPicker()
    let fresh = try #require(sheet(model, "AshuLab/carrier").firstResult)
    #expect(fresh.watch == ProjectSheetWatch(problem: nil) && model.watch)
    await model.choose(fresh)
    #expect(model.watching)
    model.watch = false
    #expect(model.watching == false)
    #expect(try #require(sheet(model, "acme/web").firstResult).watch?.problem == "acme/web is already watched")
    #expect(try #require(sheet(model, "other/web").firstResult).watch?.problem?.contains("same folder name as acme/web") == true)
    // a folder and a project have no such choice, and Settings' sheet does not offer it
    #expect(try #require(sheet(model, "/Users/nobody/x").firstResult).watch == nil)
    let settings = projectSheetState(mode: .settings, query: "AshuLab/carrier", recent: [], projects: [], github: ProjectSheetGithub(defaultParent: "/p"))
    #expect(settings.firstResult?.watch == nil && settings.firstResult?.destination?.canChoose == true)
}

@MainActor @Test func choosingARepositoryToCloneOnlyFillsThePlanWithGitHubsBranchesAndTouchesNothing() async {
    let host = FakeChat()
    host.branchesOf["AshuLab/carrier"] = RepoBranches(defaultBranch: "main", branches: ["main", "feat/x"])
    let config = FakeConfig()
    let model = await chosenDraft(host, config: config)
    await model.choose(folder: "/w/api")
    await model.choose(repo: "AshuLab/carrier")
    // nothing was cloned, nothing was written, and nothing was asked of the folder, which is not there
    #expect(config.writes == 0 && host.branchCalls == ["AshuLab/carrier"])
    #expect(model.repo == "AshuLab/carrier" && model.toClone && model.folder == "/nowhere/AshuLab/carrier")
    #expect(model.workspace?.branches.map(\.name) == ["main", "feat/x"] && model.workspace?.branch == "main" && model.startBranch == "main")
    #expect(model.picker(query: "")?.local.map(\.name) == ["main", "feat/x"])
    #expect(model.sentence == "Work in carrier on the base folder (main)" && model.offersWorktree && model.canSend == false)
    #expect(model.sendSteps == [SendStep(
        icon: .download, title: "Download the repository", parts: [.text("When you send, Carrier downloads "), .code("AshuLab/carrier"), .text(" from GitHub into "), .code(model.projectsPath), .text(". Only this first time: later sessions reuse that copy.")], help: "/nowhere/AshuLab/carrier")])
    // a fresh clone has no uncommitted changes, and nothing is said of the folder's branch
    #expect(model.warning == nil && branchStep(model) == nil)
    model.choose(startBranch: "feat/x")
    #expect(branchStep(model) == nil && model.warning == nil)
}

@MainActor @Test func aWorktreeForARepositoryToCloneGetsAGeneratedNameAtOnceAndTheHostIsNotAskedForOne() async {
    let host = FakeChat()
    host.branchesOf["AshuLab/carrier"] = RepoBranches(defaultBranch: "main", branches: ["main", "feat/x"])
    let model = await chosenDraft(host)
    await model.choose(repo: "AshuLab/carrier")
    await model.useWorktree(true)
    #expect(model.worktree && model.nameState == .free && host.names.count == 2)
    #expect(model.worktreeName.split(separator: "-").count == 3)
    model.choose(startBranch: "feat/x")
    model.text = "hello"
    #expect(model.canSend)
    await model.verifyName()
    await model.fetchNow()
    #expect(host.calls.isEmpty && model.fetchProblem == nil)
    #expect(model.worktreeRequest == WorktreeRequest(from: "feat/x", name: model.worktreeName))
    // ↻ makes another one here, with no folder to ask the host about
    await model.rollName()
    #expect(model.worktreeName.split(separator: "-").count == 3 && host.calls.isEmpty)
    // a typed name is the host's to check when it makes the worktree
    model.worktreeName = "my-fix"
    #expect(model.worktreeRequest == WorktreeRequest(from: "feat/x", name: "my-fix"))
}

@MainActor @Test func sendingARepositoryPlanCarriesTheRepoTheBranchAndAWorktreeWithItsGeneratedName() async {
    let host = FakeChat()
    host.branchesOf["AshuLab/carrier"] = RepoBranches(defaultBranch: "main", branches: ["main", "feat/x"])
    let model = await chosenDraft(host)
    await model.choose(repo: "AshuLab/carrier")
    model.choose(startBranch: "feat/x")
    model.text = "hello"
    #expect(await model.send() == opened)
    #expect(host.plans == [SessionPlan(agent: "claude", workspace: .repo("AshuLab/carrier"), branch: "feat/x", text: "hello")])
    #expect(model.repo == nil && model.folder == nil)
    await model.choose(repo: "AshuLab/carrier")
    await model.useWorktree(true)
    model.choose(startBranch: "feat/x")
    model.text = "again"
    let name = model.worktreeName
    _ = await model.send()
    #expect(host.plans.last == SessionPlan(agent: "claude", workspace: .repo("AshuLab/carrier"), worktree: WorktreeRequest(from: "feat/x", name: name), text: "again"))
    #expect(host.plans.last?.wire.contains("\"name\":\"\(name)\"") == true && host.plans.last?.wire.contains("\"kind\":\"repo\",\"repo\":\"AshuLab\\/carrier\"") == true)
}

@MainActor @Test func aRepositoryAlreadyInTheProjectsFolderIsReadLocallyAndFetchedWhenTheMessageIsSent() async throws {
    let root = try projectsRoot(["AshuLab/carrier"])
    defer { try? FileManager.default.removeItem(atPath: root) }
    let host = FakeChat()
    host.workspaces[root + "/AshuLab/carrier"] = WorkspaceInfo(folder: root + "/AshuLab/carrier", branch: "main", defaultBranch: "main", dirty: 3, branches: [.init(name: "main", remote: false), .init(name: "origin/feat", remote: true)])
    let model = await chosenDraft(host, projects: root)
    await model.choose(repo: "AshuLab/carrier")
    #expect(host.branchCalls.isEmpty && model.toClone == false && model.repo == "AshuLab/carrier")
    #expect(model.folder == root + "/AshuLab/carrier" && model.workspace?.dirty == 3 && model.warning != nil)
    #expect(model.sendSteps.map(\.parts) == [[.text("Updates "), .code("AshuLab/carrier"), .text(" from GitHub first")]])
    model.text = "hello"
    _ = await model.send()
    #expect(host.plans.count == 1 && host.plans[0].folder == nil)
}

@MainActor @Test func aRepositoryThatGitHubWillNotListStillWorksOnItsDefaultBranchAndSaysWhy() async {
    let host = FakeChat()
    host.refuse["repoBranches"] = ControlError.remote(.words("GitHub could not be reached; check the network connection"))
    let model = await chosenDraft(host)
    await model.choose(repo: "AshuLab/carrier")
    #expect(model.workspaceProblem == "GitHub could not be reached; check the network connection" && model.workspace == nil && model.offersWorktree == false)
    model.text = "hello"
    #expect(model.canSend && model.loadingBranches == false)
    // a name that is not a repository is not taken
    await model.choose(repo: "../x")
    #expect(model.repo == "AshuLab/carrier")
}

@MainActor @Test func theBranchesAreAPartialListWhenGitHubSaysThereAreMoreAndTheDefaultIsAlwaysThere() async {
    let host = FakeChat()
    host.branchesOf["AshuLab/api"] = RepoBranches(defaultBranch: "trunk", branches: ["a", "b"], hasMore: true)
    let model = await chosenDraft(host)
    await model.choose(repo: "AshuLab/api")
    #expect(model.branchesPartial && model.workspace?.branches.map(\.name) == ["trunk", "a", "b"])
    await model.choose(folder: "/w/api")
    #expect(model.branchesPartial == false && model.repo == nil && model.toClone == false)
}

@MainActor @Test func aCancelledRepositoryPlanComesBackInTheDraftWithItsBranchAndWorktree() async {
    let host = FakeChat()
    host.branchesOf["AshuLab/carrier"] = RepoBranches(defaultBranch: "main", branches: ["main", "feat/x"])
    let model = await chosenDraft(host)
    model.restore(SessionPlan(agent: "claude", workspace: .repo("AshuLab/carrier"), worktree: WorktreeRequest(from: "feat/x"), text: "again"))
    await model.load()
    #expect(model.repo == "AshuLab/carrier" && model.toClone && model.worktree && model.startBranch == "feat/x" && model.text == "again" && model.worktreeName.isEmpty == false)
}

@MainActor @Test func choosingAProjectOnlyFillsThePlanAndOffersNoWorktreeNorBranch() async {
    let host = FakeChat()
    let model = await chosenDraft(host)
    model.choose(newProject: "my-idea")
    #expect(host.calls.isEmpty)
    #expect(model.newProject == "my-idea" && model.folder == "/nowhere/local/my-idea")
    #expect(model.projectNote == "/nowhere/local/my-idea will be created, with git ready, when the message is sent.")
    #expect(model.sentence == "Work in my-idea in the folder (new project, no commits yet: no worktree)")
    #expect(model.offersWorktree == false && model.warning == nil && branchStep(model) == nil && model.picked == nil)
    await model.useWorktree(true)
    #expect(model.worktree == false && model.workspaceProblem == nil)
    #expect(model.watchNotes.isEmpty)
    model.clearWorkspace()
    #expect(model.newProject == nil && model.folder == nil && model.projectNote == nil)
}

@MainActor @Test func sendingAProjectPlanAsksTheHostForTheProjectStepAndNothingElse() async {
    let host = FakeChat()
    let model = await chosenDraft(host)
    model.choose(newProject: "my-idea")
    model.text = "build it"
    #expect(await model.send() == opened)
    #expect(host.plans == [SessionPlan(agent: "claude", workspace: .newProject("my-idea"), text: "build it")])
    #expect(model.newProject == nil && model.folder == nil)
}

@MainActor @Test func aCancelledProjectPlanComesBackInTheDraft() async {
    let model = await chosenDraft(FakeChat())
    model.restore(SessionPlan(agent: "claude", workspace: .newProject("my-idea"), text: "again"))
    await model.load()
    #expect(model.newProject == "my-idea" && model.folder == "/nowhere/local/my-idea" && model.text == "again")
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
    func open(plan: SessionPlan) async throws -> String { opened }
    func workspace(_ folder: String) async throws -> WorkspaceInfo { cleanRepo(folder) }
    func fetch(_ folder: String, ifStale: Bool) async throws -> WorkspaceInfo { cleanRepo(folder) }
    func suggestName(_ folder: String) async throws -> String { "x" }
    func checkName(_ folder: String, _ name: String) async throws -> NameCheck { NameCheck(valid: true, free: true) }
    func send(_ id: String, _ text: String) async throws {}
    func events(_ id: String, after: Int, limit: Int) async throws -> ChatEvents { ChatEvents(events: [], cursor: after) }
    func resume(_ id: String) async throws {}
    func interrupt(_ id: String) async throws {}
    func answer(_ id: String, approval: String, choice: String, answers: [String: String]?) async throws {}
    func setOption(_ id: String, option: String, value: String) async throws {}
    func archive(_ id: String, _ archived: Bool) async throws {}
    func delete(_ id: String) async throws {}
    func capabilities() async throws -> Set<ControlClient.Capability> { [.plan] }
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
    let model = await chosenDraft(FakeChat())
    model.openPicker()
    #expect(model.watch && model.watchProblem(for: "AshuLab/carrier") == nil)
    #expect(model.watchProblem(for: "acme/web") == "acme/web is already watched")
    #expect(model.watchProblem(for: "other/web")?.contains("same folder name as acme/web") == true)
    // `watching` is what it comes to for the repository chosen: nothing chosen, nothing watched
    #expect(model.watching == false)
    await model.choose(repo: "other/web")
    #expect(model.watching == false)
    await model.choose(repo: "AshuLab/carrier")
    #expect(model.watching)
}

/// A session of the host's list in the given stage of its preparation: still preparing, failed at a step, or answered (no preparation left).
private func listed(_ id: String, _ stage: String) -> ChatSession {
    let (state, preparation) = switch stage {
    case "running": ("preparing", ",\"preparation\":\"running\"")
    case "failed": ("idle", ",\"preparation\":\"failed\"")
    default: ("working", "")
    }
    let json = """
    {"id":"\(id)","agent":"claude","harness":"claude","folder":"/projects/AshuLab/carrier","state":"\(state)","createdAt":0,"lastActiveAt":0,"archived":false,"live":true\(preparation)}
    """
    return try! JSONDecoder().decode(ChatSession.self, from: Data(json.utf8))
}

/// A draft that chose `repo`, wrote its first message and sent it: the session `opened` exists and the repository waits for its `message` step.
@MainActor private func sentForRepo(_ host: FakeChat, config: FakeConfig, repo: String = "AshuLab/carrier") async -> NewSessionModel {
    host.branchesOf[repo] = RepoBranches(defaultBranch: "main", branches: ["main"])
    host.active = [listed(opened, "running")]
    let model = await chosenDraft(host, config: config)
    await model.choose(repo: repo)
    model.text = "hello"
    #expect(await model.send() == opened)
    return model
}

@MainActor @Test func theRepositoryIsAddedToTheConfigOnlyOnceTheMessageStepIsDoneKeepingEverythingElseAndSaysCarrierAppliesItToTheNextEpic() async throws {
    let config = FakeConfig("""
    {"note": "kept", "limits": {"maxReviews": 7}, "repos": [{"name": "acme/web", "agents": {"author": {"profile": "p"}}}]}
    """)
    let host = FakeChat()
    let model = await sentForRepo(host, config: config)
    // preparing, then failed at a step: nothing is written
    #expect(config.writes == 0)
    await model.settleWatches()
    host.active = [listed(opened, "failed")]
    await model.settleWatches()
    #expect(config.writes == 0 && model.watchNotes[opened] == nil)
    // the agent answered: the message step is done
    host.active = [listed(opened, "answered")]
    await settle { config.writes == 1 }
    let saved = try #require(config.json)
    let file = try #require(try JSONSerialization.jsonObject(with: saved) as? [String: Any])
    let repos = try #require(file["repos"] as? [[String: Any]])
    #expect(repos.map { $0["name"] as? String } == ["acme/web", "AshuLab/carrier"] && repos[0]["agents"] != nil && repos[1].keys.sorted() == ["name"])
    #expect(file["note"] as? String == "kept" && (file["limits"] as? [String: Any])?["maxReviews"] as? Int == 7)
    await settle { model.watchNotes[opened] != nil }
    #expect(model.watchNotes[opened] == WatchNote(text: "Carrier applies AshuLab/carrier to the next epic", failed: false))
    // once: looking again changes nothing
    await model.settleWatches()
    try await Task.sleep(for: .milliseconds(30))
    #expect(config.writes == 1)
}

@MainActor @Test func aListReadBeforeTheSessionWasOpenedOrOneThatFailedDoesNotDropTheWatchAndTheNextRealOneSettlesIt() async throws {
    let config = FakeConfig()
    let host = FakeChat()
    let (stream, updates) = AsyncStream.makeStream(of: SessionsUpdate.self)
    host.given = stream
    let model = await sentForRepo(host, config: config)
    let preparing = [listed(opened, "running")], answered = [listed(opened, "answered")]
    // the one in flight when the session was opened, which does not list it; the last good one given at once; a miss
    updates.yield(SessionsUpdate(active: [], archived: [], readAt: .distantPast))
    updates.yield(SessionsUpdate(active: [], archived: [], replayed: true, readAt: .distantPast))
    updates.yield(SessionsUpdate(active: answered, archived: [], stale: true))
    try await Task.sleep(for: .milliseconds(50))
    #expect(config.writes == 0)
    // a read that began after the session was opened settles it
    updates.yield(SessionsUpdate(active: preparing, archived: []))
    updates.yield(SessionsUpdate(active: answered, archived: []))
    await settle { config.writes == 1 }
    #expect(config.writes == 1)
    updates.finish()
    _ = model
}

@MainActor @Test func theEngineIsAskedForTheListOnceTheRepositoryIsAddedAndNeverWhenItWasNot() async throws {
    let config = FakeConfig()
    let host = FakeChat()
    let model = await sentForRepo(host, config: config)
    host.active = [listed(opened, "failed")]
    await model.settleWatches()
    #expect(config.sent.isEmpty)
    host.active = [listed(opened, "answered")]
    await settle { config.sent.count == 1 }
    #expect(config.sent == [.watchedRepos(["acme/web", "AshuLab/carrier"])])
    // a config the engine refuses to change: nothing was sent through, and the note says so
    let stuck = FakeConfig()
    stuck.unwritable = true
    let other = FakeChat()
    let blocked = await sentForRepo(other, config: stuck)
    other.active = [listed(opened, "answered")]
    await settle { blocked.watchNotes[opened] != nil }
    #expect(blocked.watchNotes[opened]?.failed == true && stuck.sent.isEmpty)
}

@MainActor @Test func aRepositoryTheEngineRefusedToApplyIsInTheListAndTheNoteSaysWhatTheEngineAnswered() async {
    let config = FakeConfig()
    config.reply = EngineConfigReply(engine: .refused, reason: .init(code: "config.invalid", params: [:], error: "repos.1.name: bad"))
    let host = FakeChat()
    let model = await sentForRepo(host, config: config)
    host.active = [listed(opened, "answered")]
    await settle { model.watchNotes[opened] != nil }
    #expect(configRepoNames(json: config.json ?? Data()) == ["acme/web", "AshuLab/carrier"])
    #expect(model.watchNotes[opened] == WatchNote(text: "AshuLab/carrier was added to Carrier's list, but Carrier kept its settings: repos.1.name: bad", failed: true))
}

@MainActor @Test func withNoEngineToAskTheNoteSaysItIsReadAtStartAndWithOneThatDidNotAnswerItSaysSo() async {
    for (reply, note) in [
        (EngineConfigReply(engine: .notRunning), WatchNote(text: "Carrier reads AshuLab/carrier when it starts", failed: false)),
        (EngineConfigReply(engine: .applied), WatchNote(text: "Carrier applies AshuLab/carrier to the next epic", failed: false)),
    ] {
        let config = FakeConfig()
        config.reply = reply
        let host = FakeChat()
        let model = await sentForRepo(host, config: config)
        host.active = [listed(opened, "answered")]
        await settle { model.watchNotes[opened] != nil }
        #expect(configRepoNames(json: config.json ?? Data()) == ["acme/web", "AshuLab/carrier"] && model.watchNotes[opened] == note)
    }
    // the request could not be made at all: the list is not changed, and the note says it could not be saved
    let config = FakeConfig()
    config.failure = ControlError.timeout
    let host = FakeChat()
    let model = await sentForRepo(host, config: config)
    host.active = [listed(opened, "answered")]
    await settle { model.watchNotes[opened] != nil }
    #expect(model.watchNotes[opened] == WatchNote(text: "AshuLab/carrier could not be added to Carrier's list: the config file could not be saved.", failed: true))
}

@MainActor @Test func aPreparationThatFailedAndThenWorksAfterTryAgainAddsTheRepositoryThen() async {
    let config = FakeConfig()
    let host = FakeChat()
    let model = await sentForRepo(host, config: config)
    host.active = [listed(opened, "failed")]
    await model.settleWatches()
    try? await Task.sleep(for: .milliseconds(30))
    #expect(config.writes == 0)
    host.active = [listed(opened, "running")]
    await model.settleWatches()
    #expect(config.writes == 0)
    host.active = [listed(opened, "answered")]
    await settle { config.writes == 1 }
    #expect(configRepoNames(json: config.json ?? Data()) == ["acme/web", "AshuLab/carrier"])
}

@MainActor @Test func aCancelledOrDeletedSessionNeverAddsItsRepository() async throws {
    let config = FakeConfig()
    let host = FakeChat()
    let model = await sentForRepo(host, config: config)
    host.active = []  // cancelled: the host deleted the session
    await model.settleWatches()
    host.active = [listed(opened, "answered")]  // and nothing of the same id comes back to be counted
    await model.settleWatches()
    try await Task.sleep(for: .milliseconds(30))
    #expect(config.writes == 0 && model.watchNotes.isEmpty)
}

@MainActor @Test func theConfigIsReadAgainJustBeforeTheWrite() async throws {
    let config = FakeConfig()
    let host = FakeChat()
    let model = await sentForRepo(host, config: config)
    // another tab saves while the session is prepared
    config.json = Data(#"{"repos": [{"name": "acme/web"}, {"name": "vemec/encaja"}], "pollIntervalMinutes": 3}"#.utf8)
    host.active = [listed(opened, "answered")]
    await settle { config.writes == 1 }
    let saved = try #require(config.json)
    #expect(configRepoNames(json: saved) == ["acme/web", "vemec/encaja", "AshuLab/carrier"])
    #expect(String(decoding: saved, as: UTF8.self).contains("pollIntervalMinutes"))
    withExtendedLifetime(model) {}  // the model is what watches the host and writes the config: it must outlive the wait
}

@MainActor @Test func withTheBoxOffOrNotAllowedTheSessionIsPreparedAndTheConfigIsNotTouched() async throws {
    let config = FakeConfig()
    let host = FakeChat()
    host.active = [listed(opened, "answered")]
    for (name, watch) in [("AshuLab/carrier", false), ("acme/web", true), ("other/web", true)] {
        host.branchesOf[name] = RepoBranches(defaultBranch: "main", branches: ["main"])
        let model = await chosenDraft(host, config: config)
        model.watch = watch
        await model.choose(repo: name)
        model.text = "hello"
        #expect(await model.send() == opened)
        await model.settleWatches()
        #expect(host.plans.last?.workspace == .repo(name))
    }
    try await Task.sleep(for: .milliseconds(30))
    #expect(config.writes == 0)
}

@MainActor @Test func aConfigThatCannotBeWrittenIsSaidInTheSessionsNoteAndTheSessionGoesOn() async {
    for config in [FakeConfig("[1]"), FakeConfig(nil), { let c = FakeConfig(); c.unwritable = true; return c }()] {
        let host = FakeChat()
        let model = await sentForRepo(host, config: config)
        host.active = [listed(opened, "answered")]
        await settle { model.watchNotes[opened] != nil }
        #expect(model.watchNotes[opened]?.failed == true)
        #expect(model.watchNotes[opened]?.text.hasPrefix("AshuLab/carrier could not be added to Carrier's list: ") == true)
        #expect(config.writes == 0)
    }
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
    #expect(host.plans.map(\.options) == [["model": "haiku"]])
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

@MainActor @Test func aDraftShowsWhatWasKeptForAnAgentAndKeepsItWhenTheHostFailsToAnswerAgain() async {
    let host = FakeChat()
    host.offered["claude"] = claudeOptions
    let offers = AgentOfferStore()
    let first = await draft(host, offers: offers)
    await first.loadOptions()
    #expect(host.optionAsks == ["claude"])
    // the next draft has the list before the host answers, and a host that then fails leaves it
    host.offered = [:]
    var logged: [String] = []
    let second = await draft(host, offers: offers, log: { logged.append($0) })
    await second.loadOptions()
    #expect(host.optionAsks == ["claude", "claude"] && second.loadingOptions == false)
    #expect(optionsPill(second.shownOptions) == "Default · high" && logged.count == 1)
    // and what the host lists now replaces it
    host.offered["claude"] = [ChatOption(id: "model", label: "Model", values: [.init(id: "new", label: "New")], current: "new")]
    let third = await draft(host, offers: offers)
    await third.loadOptions()
    #expect(optionsPill(third.shownOptions) == "New")
}

@MainActor @Test func aFirstMessageThatNamesACommandTravelsInThePlanAsTyped() async {
    let host = FakeChat()
    host.offered["claude"] = claudeOptions
    host.commandsOffered["claude"] = [ChatCommand(id: "review", name: "review", description: "Review a change", argumentHint: "<pr>")]
    let model = await draft(host)
    await model.choose(folder: "/w/api")
    await model.loadOptions()
    #expect(model.agentCommands.map(\.name) == ["review"])
    model.text = "/review 42"
    _ = await model.send()
    #expect(host.plans.map(\.text) == ["/review 42"] && host.calls == ["open claude /w/api"])
}


// The health: what `agentChoices` and the draft's provider make of it, and the store that asks the host.

private func agentHealth(_ states: [String: ToolState]) -> HostHealth {
    HostHealth(git: .ready, gh: .ready, agents: states.sorted { $0.key < $1.key }.map { .init(name: $0.key, harness: $0.key, state: $0.value) })
}

@Test func aBlockedProviderGhAndGitOfferTheirFixFromTheList() {
    let agents = [ChatAgent(name: "work", harness: "claude", found: true), ChatAgent(name: "codex", harness: "codex", found: true), ChatAgent(name: "x'; id", harness: "agy", found: true)]
    let choices = agentChoices(agents, health: agentHealth(["work": .signedOut, "codex": .missing, "x'; id": .signedOut]))
    // the harness picks the fix, never the name the person gave the agent
    #expect(choices.map(\.fix) == [.command(["claude", "auth", "login"]), healthFix(.agent(harness: "codex"), .missing), nil])
    #expect(agentChoices(agents, health: agentHealth(["work": .ready, "codex": .unknown])).prefix(2).map(\.fix) == [nil, nil])
}

@MainActor @Test func theModelSaysWhatGhIs() async {
    let host = FakeChat()
    host.healthReply = HostHealth(git: .ready, gh: .signedOut, agents: [])
    host.capabilities.insert(.health)
    let store = HealthStore(host: host)
    let model = NewSessionModel(host: host, health: store, log: { _ in }, sleep: { _ in })
    #expect(model.ghState == nil)
    await store.check(.open)
    #expect(model.ghState == .signedOut)
}

@Test func aProviderThatIsMissingOrSignedOutIsListedDisabledWithWhyAndReadyOrUnknownCanBeChosen() {
    let agents = [ChatAgent(name: "a", harness: "claude", found: true), ChatAgent(name: "b", harness: "codex", found: true), ChatAgent(name: "c", harness: "codex", found: true), ChatAgent(name: "d", harness: "codex", found: true)]
    let choices = agentChoices(agents, health: agentHealth(["a": .ready, "b": .signedOut, "c": .missing, "d": .unknown]))
    #expect(choices.map(\.available) == [true, false, false, true])
    #expect(choices.map(\.note) == [nil, "signed out", "not installed", nil])
}

@Test func withoutAHealthAnAgentIsReadyWhenItsBinaryWasFoundAndMissingWhenItWasNot() {
    let agents = [ChatAgent(name: "claude", harness: "claude", found: true), ChatAgent(name: "codex", harness: "codex", found: false)]
    #expect(agentChoices(agents).map(\.state) == [.ready, .missing])
    // an agent the health does not list is read the same way
    #expect(agentChoices(agents, health: agentHealth(["claude": .signedOut])).map(\.state) == [.signedOut, .missing])
}

@MainActor @Test func theDraftTakesTheFirstProviderThatIsAvailableAndNeverASignedOutOne() async {
    let host = FakeChat()
    host.agents = [ChatAgent(name: "claude", harness: "claude", found: true), ChatAgent(name: "codex", harness: "codex", found: true)]
    host.healthReply = agentHealth(["claude": .signedOut, "codex": .ready])
    let store = HealthStore(host: host)
    host.capabilities.insert(.health)
    await store.check(.open)
    let model = NewSessionModel(host: host, health: store, log: { _ in }, sleep: { _ in })
    await model.load()
    #expect(model.agents.map(\.note) == ["signed out", nil])
    #expect(model.agent == "codex")
    #expect(model.noAgentReason == nil)
}

@MainActor @Test func aProviderThatLosesItsLoginAfterTheDraftOpenedIsLeftForAnAvailableOne() async {
    let host = FakeChat()
    host.agents = [ChatAgent(name: "claude", harness: "claude", found: true), ChatAgent(name: "codex", harness: "codex", found: true)]
    host.capabilities.insert(.health)
    let store = HealthStore(host: host)
    let model = NewSessionModel(host: host, health: store, log: { _ in }, sleep: { _ in })
    await model.load()
    await model.choose(folder: "/w/api")
    model.text = "hello"
    #expect(model.agent == "claude" && model.canSend)
    host.healthReply = agentHealth(["claude": .signedOut, "codex": .unknown])
    await store.check(.active)
    #expect(model.canSend == false)
    model.pickAvailableAgent()
    #expect(model.agent == "codex" && model.canSend)
}

@MainActor @Test func withNoProviderAvailableTheBoxSaysWhyAndSendIsOff() async {
    let host = FakeChat()
    host.agents = [ChatAgent(name: "claude", harness: "claude", found: true), ChatAgent(name: "codex", harness: "codex", found: false)]
    host.healthReply = agentHealth(["claude": .signedOut, "codex": .missing])
    host.capabilities.insert(.health)
    let store = HealthStore(host: host)
    await store.check(.open)
    let model = NewSessionModel(host: host, health: store, log: { _ in }, sleep: { _ in })
    await model.load()
    await model.choose(folder: "/w/api")
    model.text = "hello"
    #expect(model.agent == nil && model.canSend == false)
    #expect(model.noAgentReason == "No provider can start a session: claude is signed out, codex is not installed.")
    #expect(await model.send() == nil && host.calls.isEmpty)
}

@MainActor @Test func aHostWithoutTheHealthCapabilityIsNeverAskedAndTheDraftBehavesAsBefore() async {
    let host = FakeChat()
    host.healthReply = agentHealth(["claude": .signedOut])
    let store = HealthStore(host: host)
    for moment in HealthMoment.allCases { await store.check(moment) }
    #expect(host.healthAsks.isEmpty && store.latest == nil)
    let model = NewSessionModel(host: host, health: store, log: { _ in }, sleep: { _ in })
    await model.load()
    #expect(model.agents == [AgentChoice(name: "codex", harness: "codex", state: .missing), AgentChoice(name: "claude", harness: "claude", state: .ready)] && model.agent == "claude")
}

@MainActor @Test func theStoreAsksAfreshWhenTheAppBecomesActiveOrIsAskedToCheckAgainButNotAtOpen() async {
    let host = FakeChat()
    host.capabilities.insert(.health)
    let store = HealthStore(host: host)
    await store.check(.open)
    await store.check(.active)
    await store.check(.refresh)
    #expect(host.healthAsks == [false, true, true])
    #expect(store.latest == host.healthReply)
}

@MainActor @Test func aHostThatRefusesTheHealthIsLoggedAndTheLastAnswerStands() async {
    let host = FakeChat()
    host.capabilities.insert(.health)
    var lines: [String] = []
    let store = HealthStore(host: host, log: { lines.append($0) })
    await store.check(.open)
    let answered = store.latest
    host.refuse["health"] = ControlError.remote(.words("boom"))
    await store.check(.refresh)
    #expect(lines == ["health: boom"] && store.latest == answered && answered != nil)
}

@MainActor @Test func theStoreForgetsItsAnswerWhenTheHostNoLongerListsHealth() async {
    let host = FakeChat()
    host.capabilities.insert(.health)
    let store = HealthStore(host: host)
    await store.check(.open)
    #expect(store.latest != nil)
    host.capabilities.remove(.health)
    await store.check(.active)
    #expect(store.latest == nil)
}

// Without git: the draft turns off New worktree and says why where the branch would be.

private func gitHealth(_ git: ToolState) -> HostHealth { HostHealth(git: git, gh: .ready, agents: []) }

@MainActor private func draftWithGit(_ git: ToolState?, folder: String) async -> NewSessionModel {
    let host = FakeChat()
    host.workspaces[folder] = WorkspaceInfo(folder: folder, branch: "main", defaultBranch: "main", dirty: 2, branches: [.init(name: "main", remote: false)])
    var store: HealthStore?
    if let git {
        host.healthReply = gitHealth(git)
        host.capabilities.insert(.health)
        store = HealthStore(host: host)
        await store?.check(.open)
    }
    let model = NewSessionModel(host: host, health: store, log: { _ in }, sleep: { _ in })
    await model.load()
    await model.choose(folder: folder)
    return model
}

@MainActor @Test func withGitMissingTheDraftOffersNoWorktreeAndSaysWhyInsteadOfTheBranch() async {
    let model = await draftWithGit(.missing, folder: "/w/api")
    #expect(model.gitMissing && model.offersWorktree == false && model.warning == nil)
    #expect(model.sentence == "Work in api in the folder (git is missing: no worktree, no branch. See Health in Settings)")
    await model.useWorktree(true)
    #expect(model.worktree == false)
}

@MainActor @Test func withGitReadyOrUnknownOrNoHealthTheDraftIsAsBefore() async {
    for git in [ToolState.ready, .unknown, nil] {
        let model = await draftWithGit(git, folder: "/w/api")
        #expect(model.gitMissing == false && model.offersWorktree)
        #expect(model.sentence == "Work in api on the base folder (main)" && model.warning != nil)
        await model.useWorktree(true)
        #expect(model.worktree)
    }
}

@MainActor @Test func withGhSignedOutTheSheetKeepsTheFolderAndTheNewProjectOpen() async {
    let host = FakeChat()
    host.healthReply = HostHealth(git: .ready, gh: .signedOut, agents: [])
    host.capabilities.insert(.health)
    let store = HealthStore(host: host)
    await store.check(.open)
    let model = NewSessionModel(host: host, health: store, log: { _ in }, sleep: { _ in }, projectsFolder: { "/nowhere" })
    await model.load()
    #expect(model.ghState == .signedOut && model.hostCreates)
    // a folder and a new project never depend on gh
    await model.choose(folder: "/w/api")
    #expect(model.folder == "/w/api" && model.workspaceProblem == nil)
    model.choose(newProject: "my-idea")
    #expect(model.newProject == "my-idea")
    host.healthReply = HostHealth(git: .ready, gh: .unknown, agents: [])
    await store.check(.refresh)
    #expect(model.ghState == .unknown)
}

// MARK: the plan of a cancelled preparation comes back

@MainActor @Test func aRestoredPlanBringsBackTheFolderTheBranchTheAgentTheOptionsAndTheText() async {
    let host = FakeChat()
    host.offered["claude"] = claudeOptions
    host.workspaces["/w/api"] = WorkspaceInfo(folder: "/w/api", branch: "main", dirty: 0, branches: [.init(name: "main", remote: false), .init(name: "feat/x", remote: false)])
    let model = await draft(host)
    model.restore(SessionPlan(agent: "claude", folder: "/w/api", branch: "feat/x", options: ["model": "haiku"], text: "build the thing\nthen test it"))
    // the draft that opens next is the one that takes it: opening starts blank and then puts the plan back
    await model.load()
    await model.loadOptions()
    #expect(model.folder == "/w/api" && model.text == "build the thing\nthen test it" && model.agent == "claude")
    #expect(model.branchChange?.to == "feat/x" && model.worktree == false)
    #expect(model.chosenOptions == ["model": "haiku"])
    // nothing was made on the machine
    #expect(host.calls.filter { $0.hasPrefix("open") }.isEmpty)
    // and it is given back once: the next opening is blank
    await model.load()
    #expect(model.folder == nil && model.text.isEmpty)
}

@MainActor @Test func aRestoredWorktreePlanBringsBackTheBranchItStartsFromAndItsName() async {
    let host = FakeChat()
    let model = await draft(host)
    model.restore(SessionPlan(agent: "claude", folder: "/w/api", worktree: WorktreeRequest(from: "origin/main", name: "my-fix"), text: "again"))
    await model.load()
    #expect(model.worktree && model.worktreeName == "my-fix" && model.startBranch == "origin/main" && model.text == "again")
    // a worktree the host was to name keeps the name the draft suggested
    model.restore(SessionPlan(agent: "claude", folder: "/w/api", worktree: WorktreeRequest(from: "main", name: ""), text: "once more"))
    await model.load()
    #expect(model.worktree && model.worktreeName == "keen-ghost-char" && model.startBranch == "main")
}

@MainActor @Test func aRestoredPlanWhoseAgentCannotBeChosenAnyMoreKeepsTheFolderAndTheTextAndTakesAnAvailableAgent() async {
    let host = FakeChat()
    let model = await draft(host)
    model.restore(SessionPlan(agent: "codex", folder: "/w/api", text: "hello"))
    await model.load()
    #expect(model.folder == "/w/api" && model.text == "hello" && model.agent == "claude")
}

// MARK: what each agent offers, kept

private func offer(_ model: String) -> AgentOffer {
    AgentOffer(options: [ChatOption(id: "model", label: "Model", values: [.init(id: model, label: model)], current: model)], commands: [])
}

private func tempFile() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("offers-\(UUID().uuidString)/agent-offers.json") }

@MainActor @Test func anAnswerIsKeptOnDiskAndTheNextLaunchHasItBeforeAskingAnyone() async throws {
    let file = tempFile()
    let host = FakeChat()
    host.offered["claude"] = offer("sonnet").options
    let first = AgentOfferStore(file: file, fingerprint: { "a" })
    #expect(first.offer("claude") == nil)
    try await first.refresh("claude", host: host)
    // a new store, as after a launch: no request was made and the file has it
    let second = AgentOfferStore(file: file, fingerprint: { "a" })
    #expect(second.offer("claude") == offer("sonnet") && host.optionAsks == ["claude"])
}

@MainActor @Test func whatWasKeptIsDroppedWhenTheAccountsChange() async throws {
    let file = tempFile()
    let host = FakeChat()
    host.offered["claude"] = offer("sonnet").options
    var fingerprint = "a"
    let store = AgentOfferStore(file: file, fingerprint: { fingerprint })
    try await store.refresh("claude", host: host)
    #expect(store.offer("claude") != nil)
    fingerprint = "b"
    #expect(store.offer("claude") == nil)
    // and so does a store opened after the change
    #expect(AgentOfferStore(file: file, fingerprint: { "b" }).offer("claude") == nil)
}

@MainActor @Test func aFailedAskLeavesWhatWasKept() async throws {
    let host = FakeChat()
    host.offered["claude"] = offer("sonnet").options
    let store = AgentOfferStore()
    try await store.refresh("claude", host: host)
    host.offered = [:]
    await #expect(throws: (any Error).self) { try await store.refresh("claude", host: host) }
    #expect(store.offer("claude") == offer("sonnet"))
}

@MainActor @Test func warmingAsksEveryAgentWithABinaryAndSkipsTheOthers() async {
    let host = FakeChat()
    host.offered = ["claude": offer("sonnet").options, "codex": offer("gpt").options]
    host.agents = [ChatAgent(name: "claude", harness: "claude", found: true), ChatAgent(name: "codex", harness: "codex", found: true), ChatAgent(name: "gone", harness: "x", found: false)]
    let store = AgentOfferStore()
    await store.warm(host: host)
    // one at a time, in the host's order: a draft's three agents are not three launches at once
    #expect(host.optionAsks == ["claude", "codex"] && host.mostAsksOpen == 1 && store.offer("codex") == offer("gpt") && store.offer("gone") == nil)
}

@MainActor @Test func warmingSkipsAnAgentWhoseOfferWasKept() async throws {
    let host = FakeChat()
    host.offered = ["claude": offer("sonnet").options, "codex": offer("gpt").options]
    host.agents = [ChatAgent(name: "claude", harness: "claude", found: true), ChatAgent(name: "codex", harness: "codex", found: true)]
    let store = AgentOfferStore()
    try await store.refresh("claude", host: host)
    host.optionAsks = []
    await store.warm(host: host)
    #expect(host.optionAsks == ["codex"] && store.offer("claude") == offer("sonnet"))
    // everything kept: nothing is launched when the app opens
    host.optionAsks = []
    await store.warm(host: host)
    #expect(host.optionAsks.isEmpty)
}


// MARK: what Settings > Sessions says a new session opens with

@MainActor private func draft(_ host: FakeChat, starting start: NewSessionStart) async -> NewSessionModel {
    let model = NewSessionModel(host: host, ensureHost: { true }, log: { _ in }, sleep: { _ in }, start: { start })
    await model.load()
    return model
}

@MainActor @Test func aNewDraftOpensOnTheProviderSettingsNamesWhenItCanWorkElseOnTheFirstThatCan() async {
    let host = FakeChat()
    host.agents = [ChatAgent(name: "codex", harness: "codex", found: true), ChatAgent(name: "claude", harness: "claude", found: true)]
    #expect(await draft(host).agent == "codex")
    #expect(await draft(host, starting: NewSessionStart(agent: "claude")).agent == "claude")
    // one that is gone or cannot work is not taken
    #expect(await draft(host, starting: NewSessionStart(agent: "gone")).agent == "codex")
    host.agents = [ChatAgent(name: "codex", harness: "codex", found: false), ChatAgent(name: "claude", harness: "claude", found: true)]
    #expect(await draft(host, starting: NewSessionStart(agent: "codex")).agent == "claude")
}

@MainActor @Test func theModelAndReasoningSettingsNamesGoToItsProviderAsFarAsItListsThem() async {
    let host = FakeChat()
    host.offered["claude"] = claudeOptions
    let model = await draft(host, starting: NewSessionStart(agent: "claude", model: "haiku", effort: "max"))
    await model.loadOptions()
    // the model is listed and taken; "max" is not listed and is left out
    #expect(model.chosenOptions == ["model": "haiku"])
    // a provider that is not the named one starts from its own values
    let other = await draft(host, starting: NewSessionStart(agent: "codex", model: "haiku", effort: "low"))
    await other.loadOptions()
    #expect(other.agent == "claude" && other.chosenOptions.isEmpty)
}

private let accessOptions = claudeOptions + [
    ChatOption(id: "permissionMode", label: "Permission mode", values: [.init(id: "default", label: "Ask"), .init(id: "acceptEdits", label: "Accept edits")], current: "default"),
]

@MainActor @Test func theAccessSettingsNamesGoToAnyProviderThatListsItAndNothingElse() async {
    let host = FakeChat()
    host.offered["claude"] = accessOptions
    let model = await draft(host, starting: NewSessionStart(access: ["permissionMode": "acceptEdits", "sandbox": "read-only"]))
    await model.loadOptions()
    #expect(model.agent == "claude" && model.chosenOptions == ["permissionMode": "acceptEdits"])
    // the model of the named provider and the access come together
    let both = await draft(host, starting: NewSessionStart(agent: "claude", model: "haiku", access: ["permissionMode": "acceptEdits"]))
    await both.loadOptions()
    #expect(both.chosenOptions == ["model": "haiku", "permissionMode": "acceptEdits"])
}

@Test func theAccessIsKeptAsJSONAndABadOneReadsAsNone() {
    let access = ["permissionMode": "acceptEdits", "sandbox": "read-only"]
    #expect(NewSessionStart.access(fromJSON: NewSessionStart.json(fromAccess: access)) == access)
    #expect(NewSessionStart.access(fromJSON: "").isEmpty && NewSessionStart.access(fromJSON: "[1]").isEmpty)
}

// MARK: what Settings > Sessions says a new session opens in

@MainActor private func draft(_ host: FakeChat, workIn: WorkIn) async -> NewSessionModel {
    let model = NewSessionModel(host: host, ensureHost: { true }, log: { _ in }, sleep: { _ in }, projectsFolder: { "/nowhere" }, workIn: { workIn })
    await model.load()
    return model
}

@MainActor @Test func aGitFolderOpensInANewWorktreeWhenWorkInSaysSoAndOnTheBaseFolderOtherwise() async {
    let host = FakeChat()
    host.workspaces["/w/api"] = WorkspaceInfo(folder: "/w/api", branch: "main", defaultBranch: "main", branches: [.init(name: "main", remote: false)])
    let base = await draft(host, workIn: .baseFolder)
    await base.choose(folder: "/w/api")
    #expect(base.worktree == false)
    let model = await draft(host, workIn: .newWorktree)
    await model.choose(folder: "/w/api")
    #expect(model.worktree && model.worktreeName == "brave-marine-aiur" && model.nameState == .free && model.startBranch == "main")
}

@MainActor @Test func aFolderThatOffersNoWorktreeOpensOnTheBaseFolderWhateverWorkInSays() async {
    let host = FakeChat()
    host.workspaces["/w/plain"] = WorkspaceInfo(folder: "/w/plain", git: false)
    host.workspaces["/w/bare"] = WorkspaceInfo(folder: "/w/bare", bare: true, branches: [.init(name: "main", remote: false)])
    host.workspaces["/w/empty"] = WorkspaceInfo(folder: "/w/empty")
    let model = await draft(host, workIn: .newWorktree)
    for folder in ["/w/plain", "/w/bare", "/w/empty"] {
        await model.choose(folder: folder)
        #expect(model.offersWorktree == false && model.worktree == false, "\(folder)")
    }
}

@MainActor @Test func whatThePersonChoosesInTheDraftWinsOverWorkIn() async {
    let host = FakeChat()
    host.workspaces["/w/api"] = WorkspaceInfo(folder: "/w/api", branch: "main", defaultBranch: "main", branches: [.init(name: "main", remote: false)])
    let model = await draft(host, workIn: .newWorktree)
    await model.choose(folder: "/w/api")
    await model.useWorktree(false)
    await model.fetchNow()
    #expect(model.worktree == false)
    // a plan sent for the base folder comes back on it
    model.restore(SessionPlan(agent: "claude", folder: "/w/api", text: "hi"))
    await model.load()
    #expect(model.folder == "/w/api" && model.worktree == false && model.text == "hi")
}

@MainActor @Test func aRepositoryToCloneOpensInANewWorktreeWhenWorkInSaysSo() async {
    let host = FakeChat()
    host.branchesOf["AshuLab/carrier"] = RepoBranches(defaultBranch: "main", branches: ["main", "feat/x"])
    let base = await draft(host, workIn: .baseFolder)
    await base.choose(repo: "AshuLab/carrier")
    #expect(base.toClone && base.worktree == false)
    let model = await draft(host, workIn: .newWorktree)
    await model.choose(repo: "AshuLab/carrier")
    #expect(model.toClone && model.worktree && model.worktreeName.isEmpty == false && model.startBranch == "main")
}

// MARK: the reasoning levels follow the model chosen in the draft

/// What a host lists when it opened its probe session with `best-model`: the effort is that model's, the models say their own levels.
private let codexLevels = [
    ChatOption(id: "model", label: "Model", values: [
        .init(id: "best-model", label: "Best model", efforts: ["low"], defaultEffort: "low"),
        .init(id: "gpt-6.1-terra", label: "GPT-6.1 Terra", efforts: ["low", "medium", "high"], defaultEffort: "low"),
        .init(id: "gpt-6.1-sol", label: "GPT-6.1 Sol", efforts: ["low", "medium", "high"], defaultEffort: "medium"),
    ], current: "best-model"),
    ChatOption(id: "effort", label: "Reasoning effort", values: [.init(id: "low", label: "low")], current: "low"),
]

@MainActor private func effortOf(_ model: NewSessionModel) -> ChatOption? { model.shownOptions.first { $0.id == "effort" } }

@MainActor @Test func theSettingsReasoningIsKeptWhenTheModelItNamesTakesIt() async {
    let host = FakeChat()
    host.agents = [ChatAgent(name: "codex", harness: "codex", found: true)]
    host.offered["codex"] = codexLevels
    let model = await draft(host, starting: NewSessionStart(agent: "codex", model: "gpt-6.1-terra", effort: "high"))
    await model.loadOptions()
    #expect(model.chosenOptions == ["model": "gpt-6.1-terra", "effort": "high"])
    #expect(effortOf(model)?.values.map(\.id) == ["low", "medium", "high"] && optionsPill(model.shownOptions) == "GPT-6.1 Terra · high")
}

@MainActor @Test func choosingAModelInTheDraftBringsItsLevelsAndItsDefault() async {
    let host = FakeChat()
    host.agents = [ChatAgent(name: "codex", harness: "codex", found: true)]
    host.offered["codex"] = codexLevels
    let model = await draft(host)
    await model.loadOptions()
    #expect(effortOf(model)?.values.map(\.id) == ["low"])
    model.choose(option: "model", value: "gpt-6.1-sol")
    #expect(effortOf(model)?.values.map(\.id) == ["low", "medium", "high"] && effortOf(model)?.current == "medium")
    model.choose(option: "effort", value: "high")
    #expect(model.chosenOptions == ["model": "gpt-6.1-sol", "effort": "high"])
    // a level the next model does not take is let go, and that model's default shows
    model.choose(option: "model", value: "best-model")
    #expect(model.chosenOptions == ["model": "best-model"] && effortOf(model)?.values.map(\.id) == ["low"] && effortOf(model)?.current == "low")
}

@MainActor @Test func aHostThatSendsNoLevelsLeavesTheReasoningAsItListsIt() async {
    let host = FakeChat()
    host.offered["claude"] = claudeOptions
    let model = await draft(host)
    await model.loadOptions()
    model.choose(option: "model", value: "haiku")
    #expect(effortOf(model)?.values.map(\.id) == ["low", "high"] && effortOf(model)?.current == "high")
    model.choose(option: "effort", value: "low")
    #expect(model.chosenOptions == ["model": "haiku", "effort": "low"])
}

@MainActor @Test func theProbeModelKeepsTheEffortTheHostReportsAndAModelWithNoDefaultNamesNone() async {
    let host = FakeChat()
    host.offered["codex"] = [
        ChatOption(id: "model", label: "Model", values: [
            .init(id: "probe", label: "Probe", efforts: ["low", "high"], defaultEffort: "low"),
            .init(id: "other", label: "Other", efforts: ["low", "high"]),
        ], current: "probe"),
        ChatOption(id: "effort", label: "Reasoning effort", values: [.init(id: "low", label: "low"), .init(id: "high", label: "high")], current: "high"),
    ]
    host.agents = [ChatAgent(name: "codex", harness: "codex", found: true)]
    let model = await draft(host)
    await model.loadOptions()
    // the probe's own model: the effort the host reports (it may come from the person's own config), not the model's default
    model.choose(option: "model", value: "probe")
    #expect(effortOf(model)?.current == "high")
    // a model that names no default: the host's current stays and no level is made up
    model.choose(option: "model", value: "other")
    #expect(effortOf(model)?.current == "high")
}

@MainActor @Test func aModelThatListsNoLevelsHasNoReasoningOption() async {
    let host = FakeChat()
    host.offered["codex"] = [
        ChatOption(id: "model", label: "Model", values: [
            .init(id: "plain", label: "Plain", efforts: []),
            .init(id: "deep", label: "Deep", efforts: ["low", "high"], defaultEffort: "low"),
        ], current: "deep"),
        ChatOption(id: "effort", label: "Reasoning effort", values: [.init(id: "low", label: "low"), .init(id: "high", label: "high")], current: "low"),
    ]
    host.agents = [ChatAgent(name: "codex", harness: "codex", found: true)]
    let model = await draft(host)
    await model.loadOptions()
    model.choose(option: "model", value: "plain")
    #expect(effortOf(model) == nil)
    model.choose(option: "effort", value: "high")
    #expect(model.chosenOptions == ["model": "plain"])
    model.choose(option: "model", value: "deep")
    #expect(effortOf(model)?.values.map(\.id) == ["low", "high"])
}

// Where a new worktree starts: the picker's Remote and Local tabs, the setting that opens one, and what is sent.

private let startSides = WorkspaceInfo(
    folder: "/w/api", branch: "main", defaultBranch: "main",
    branches: [
        .init(name: "main", remote: false), .init(name: "local-only", remote: false),
        .init(name: "origin/main", remote: true), .init(name: "origin/remote-only", remote: true),
    ]
)

/// A draft on `/w/api` (main on both sides, `local-only` never pushed) whose `chat.json` says `setting`, in a new worktree.
@MainActor private func startDraft(_ host: FakeChat, setting: String? = nil, listing: Bool = true) async -> NewSessionModel {
    host.workspaces["/w/api"] = startSides
    if listing { host.capabilities.insert(.worktreeStart) }
    let file = setting.map { Data("{\"worktreeStart\":\"\($0)\"}".utf8) }
    let model = NewSessionModel(host: host, ensureHost: { true }, log: { _ in }, sleep: { _ in }, readChatConfig: { file })
    await model.load()
    await model.choose(folder: "/w/api")
    await model.useWorktree(true)
    model.text = "hi"
    return model
}

@MainActor @Test func thePickerOpensOnTheTabTheSettingSaysAndRemoteWhenTheFileSaysNothing() async {
    #expect(await startDraft(FakeChat()).startTab == .remote)
    #expect(await startDraft(FakeChat(), setting: "remote").startTab == .remote)
    #expect(await startDraft(FakeChat(), setting: "local").startTab == .local)
    #expect(await startDraft(FakeChat(), setting: "elsewhere").startTab == .remote)
}

@MainActor @Test func theSettingDecidesTheStartOfTheBranchTheFolderIsOn() async {
    let remote = await startDraft(FakeChat())
    #expect(remote.startPoint == StartPoint(branch: "main", side: .remote) && remote.sentence.hasSuffix("from origin/main"))
    let local = await startDraft(FakeChat(), setting: "local")
    #expect(local.startPoint == StartPoint(branch: "main", side: .local) && local.sentence.hasSuffix("from main"))
}

@MainActor @Test func theTabLeftOnIsTheSessionsChoiceAndIsSentAsStartFromWithTheBareName() async {
    let host = FakeChat()
    host.workspaces["/w/api"] = startSides
    host.capabilities.insert(.worktreeStart)
    let model = NewSessionModel(host: host, ensureHost: { true }, log: { _ in }, sleep: { _ in }, readChatConfig: { nil })
    await model.load()
    await model.choose(folder: "/w/api")
    await model.useWorktree(true)
    model.text = "hi"
    model.choose(startTab: .local)
    #expect(model.startTab == .local && model.worktreeRequest == WorktreeRequest(from: "main", name: model.worktreeName, startFrom: .local))
    model.choose(startBranch: "origin/main", on: .remote)
    #expect(model.startTab == .remote && model.startBranch == "main" && model.worktreeRequest == WorktreeRequest(from: "main", name: model.worktreeName, startFrom: .remote))
    let name = model.worktreeName
    _ = await model.send()
    #expect(host.plans.last?.wire.contains("\"worktree\":{\"name\":\"\(name)\",\"startFrom\":\"remote\"}") == true)
}

@MainActor @Test func theTabLeftOnIsForgottenWhenAnotherWorkspaceIsChosen() async {
    let model = await startDraft(FakeChat(), setting: "local")
    model.choose(startTab: .remote)
    await model.choose(folder: "/w/api")
    #expect(model.startTab == .local)
}

@MainActor @Test func aLocalBranchWithNoCounterpartOnOriginStartsFromLocalAndSaysSo() async {
    let model = await startDraft(FakeChat())
    model.choose(startBranch: "local-only", on: .local)
    #expect(model.startPoint == StartPoint(branch: "local-only", side: .local))
    #expect(model.picker(query: "")?.rows(.local).first { $0.name == "local-only" }?.localOnly == true)
    #expect(model.worktreeRequest == WorktreeRequest(from: "local-only", name: model.worktreeName, startFrom: .local))
    #expect(model.sentence.hasSuffix("from local-only"))
}

@MainActor @Test func theSendStepsBringTheLatestRemoteBranchBeforeCreatingTheBranchOnlyForARemoteStart() async {
    let model = await startDraft(FakeChat())
    #expect(model.sendSteps.map(\.title) == ["Bring the latest origin/main", "Create a branch of its own"])
    #expect(model.sendSteps.last?.parts.contains(.code("origin/main")) == true)
    model.choose(startTab: .local)
    #expect(model.sendSteps.map(\.title) == ["Create a branch of its own"] && model.sendSteps.first?.parts.contains(.code("main")) == true)
}

@MainActor @Test func aHostThatDoesNotListWorktreeStartIsToldTheRemoteRefAndNoStartFrom() async {
    let host = FakeChat()
    let model = await startDraft(host, listing: false)
    // the setting is Remote: the app's old way of saying so is the ref itself
    #expect(model.worktreeRequest == WorktreeRequest(from: "origin/main", name: model.worktreeName))
    #expect(model.sendSteps.map(\.title) == ["Create a branch of its own"], "an older host does not fetch the folder")
    model.choose(startTab: .local)
    #expect(model.worktreeRequest == WorktreeRequest(from: "main", name: model.worktreeName))
    model.choose(startBranch: "origin/remote-only", on: .remote)
    #expect(model.worktreeRequest == WorktreeRequest(from: "origin/remote-only", name: model.worktreeName))
    _ = await model.send()
    #expect(host.plans.last?.wire.contains("\"branch\":\"origin\\/remote-only\"") == true && host.plans.last?.wire.contains("startFrom") == false)
}

@MainActor @Test func aRepositoryToCloneHasNoTabsAndNoStartFrom() async {
    let host = FakeChat()
    host.capabilities.insert(.worktreeStart)
    host.branchesOf["AshuLab/carrier"] = RepoBranches(defaultBranch: "main", branches: ["main", "feat/x"])
    let model = await chosenDraft(host)
    await model.choose(repo: "AshuLab/carrier")
    await model.useWorktree(true)
    model.choose(startBranch: "feat/x")
    #expect(model.hasStartTabs == false && model.startPoint == StartPoint(branch: "feat/x", side: nil))
    #expect(model.worktreeRequest == WorktreeRequest(from: "feat/x", name: model.worktreeName))
    #expect(model.sendSteps.map(\.title) == ["Download the repository", "Create a branch of its own"])
    let folder = await startDraft(FakeChat())
    #expect(folder.hasStartTabs)
}

@MainActor @Test func aCancelledWorktreeComesBackWithItsSide() async {
    let model = await startDraft(FakeChat(), setting: "local")
    model.choose(startBranch: "origin/main", on: .remote)
    #expect(model.startPoint?.side == .remote)
    let wanted = SessionPlan(agent: "claude", folder: "/w/api", worktree: WorktreeRequest(from: "main", name: "my-fix", startFrom: .remote), text: "hi")
    let back = await startDraft(FakeChat(), setting: "local")
    back.restore(wanted)
    await back.load()
    #expect(back.startPoint == StartPoint(branch: "main", side: .remote))
}

// Choosing a project brings its branches up to date: the fetch behind the branches, what it shows and when it says nothing.

private let behindInfo = WorkspaceInfo(
    folder: "/w/api", branch: "main", defaultBranch: "main",
    branches: [.init(name: "main", remote: false, ahead: 0, behind: 2), .init(name: "origin/main", remote: true)], fetchedAt: 1_000, repo: .init(owner: "a", name: "api")
)
private let freshInfo = WorkspaceInfo(
    folder: "/w/api", branch: "main", defaultBranch: "main",
    branches: [.init(name: "main", remote: false, ahead: 0, behind: 14), .init(name: "origin/main", remote: true)], fetchedAt: 2_000, repo: .init(owner: "a", name: "api")
)

/// A host that lists `fetchIfStale`, with `/w/api` as it is on disk (`behindInfo`) and as a fetch would leave it (`freshInfo`).
@MainActor private func fetchingHost(listing: Bool = true) -> FakeChat {
    let host = FakeChat()
    host.workspaces["/w/api"] = behindInfo
    host.fetched = freshInfo
    if listing { host.capabilities.insert(.fetchIfStale) }
    return host
}

@MainActor @Test func choosingAProjectShowsTheBranchesAtOnceAndFetchesBehindThemAskingForTheFreshnessWindow() async {
    let host = fetchingHost()
    var release: CheckedContinuation<Void, Never>?
    host.fetchGate = { await withCheckedContinuation { release = $0 } }
    let model = await draft(host)
    await model.choose(folder: "/w/api")
    await settle { release != nil }
    // what is on disk is shown and the spinner runs while the fetch is out
    #expect(model.workspace == behindInfo && model.fetching && model.unreachable == false)
    #expect(host.fetches.map(\.folder) == ["/w/api"] && host.fetches.map(\.ifStale) == [true])
    release?.resume()
    await model.refreshed()
    #expect(model.workspace == freshInfo && model.fetching == false && model.unreachable == false && model.fetchProblem == nil)
    #expect(model.picker(query: "")?.local.first?.behindText == "14 behind origin")
}

@MainActor @Test func aFetchInsideTheFreshnessWindowChangesNothingButTheSpinnerEndingAtOnce() async {
    let host = fetchingHost()
    host.fetched = behindInfo  // the host skipped the git call and answered what the folder is
    let model = await draft(host)
    await model.choose(folder: "/w/api")
    await model.refreshed()
    #expect(model.workspace == behindInfo && model.fetching == false && model.unreachable == false && model.fetchProblem == nil)
    #expect(model.picker(query: "")?.unreachable == nil)
}

@MainActor @Test func aFetchThatCannotReachTheRemoteShowsNoErrorAndTheFooterSaysSoWithWhenItWasLastFetched() async {
    let host = fetchingHost()
    host.refuse["fetch"] = ControlError.remote(.words("The fetch of origin failed"))
    let model = await draft(host)
    await model.choose(folder: "/w/api")
    await model.refreshed()
    #expect(model.workspace == behindInfo && model.fetching == false && model.fetchProblem == nil && model.refusal == nil && model.workspaceProblem == nil)
    let picker = model.picker(query: "", now: Date(timeIntervalSince1970: 1.5))
    #expect(picker?.unreachable == "Could not reach origin" && picker?.fetched == "Fetched just now")
    // Fetch now asks for no window, shows its own error, and a later one that works clears the footer's note
    await model.fetchNow()
    #expect(host.fetches.map(\.ifStale) == [true, false] && model.fetchProblem == "The fetch of origin failed" && model.unreachable)
    host.refuse["fetch"] = nil
    await model.fetchNow()
    #expect(model.workspace == freshInfo && model.unreachable == false && model.fetchProblem == nil)
}

@MainActor @Test func aHostWithoutFetchIfStaleIsNotFetchedOnChoosingAndFetchNowWorksAsItDid() async {
    let host = fetchingHost(listing: false)
    let model = await draft(host)
    await model.choose(folder: "/w/api")
    await model.refreshed()
    #expect(host.fetches.isEmpty && model.workspace == behindInfo && model.fetching == false)
    await model.fetchNow()
    #expect(host.fetches.map(\.ifStale) == [false] && model.workspace == freshInfo)
}

@MainActor @Test func onlyAGitRepositoryWithAnOriginIsFetchedOnChoosing() async {
    let host = fetchingHost()
    host.workspaces["/w/notes"] = WorkspaceInfo(folder: "/w/notes", git: false)
    host.workspaces["/w/bare"] = WorkspaceInfo(folder: "/w/bare", bare: true, defaultBranch: "main", branches: [.init(name: "main", remote: false)])
    host.workspaces["/w/local"] = WorkspaceInfo(folder: "/w/local", branch: "main", branches: [.init(name: "main", remote: false)])
    let model = await draft(host)
    for folder in ["/w/notes", "/w/bare", "/w/local"] {
        await model.choose(folder: folder)
        await model.refreshed()
    }
    #expect(host.fetches.isEmpty && model.unreachable == false)
    // a repository the person has in the projects folder is a folder, and is fetched; one still to clone is read from GitHub and is not
    host.branchesOf["a/new"] = RepoBranches(defaultBranch: "main", branches: ["main"])
    await model.choose(repo: "a/new")
    await model.refreshed()
    #expect(host.fetches.isEmpty && model.fetching == false)
}

@MainActor @Test func theFetchOfAFolderLeftBehindDoesNotAnswerTheOneChosenAfterIt() async {
    let host = fetchingHost()
    host.workspaces["/w/notes"] = WorkspaceInfo(folder: "/w/notes", git: false)
    var release: CheckedContinuation<Void, Never>?
    host.fetchGate = { await withCheckedContinuation { release = $0 } }
    let model = await draft(host)
    await model.choose(folder: "/w/api")
    await settle { release != nil }
    await model.choose(folder: "/w/notes")  // nothing to fetch: the first fetch is left behind
    #expect(model.fetching == false)
    release?.resume()
    await model.refreshed()
    #expect(model.folder == "/w/notes" && model.workspace?.folder == "/w/notes" && model.unreachable == false)
}

@MainActor @Test func aFolderChosenWhileTheNameIsBeingSuggestedIsNotFetchedForTheOneLeftBehind() async {
    let host = fetchingHost()
    host.workspaces["/w/notes"] = WorkspaceInfo(folder: "/w/notes", git: false)
    var release: CheckedContinuation<Void, Never>?
    host.suggestGate = { await withCheckedContinuation { release = $0 } }
    let model = await draft(host, workIn: .newWorktree)
    let first = Task { await model.choose(folder: "/w/api") }
    await settle { release != nil }
    await model.choose(folder: "/w/notes")  // the first read is still waiting for its name
    release?.resume()
    await first.value
    await model.refreshed()
    #expect(host.fetches.isEmpty && model.folder == "/w/notes" && model.fetching == false)
}

@Test func theWireOfFetchCarriesIfStaleOnlyToAHostThatListsIt() async throws {
    var lines: [String] = []
    for listed in [true, false] {
        let server = TestServer { connection in
            connection.send(listed ? "{\"event\":\"hello\",\"protocol\":1,\"capabilities\":[\"fetch\",\"fetchIfStale\"]}\n" : "{\"event\":\"hello\",\"protocol\":1,\"capabilities\":[\"fetch\"]}\n")
            guard let line = connection.readLine(), let id = (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])?["id"] as? Int else { return }
            lines.append(line)
            connection.send("{\"id\":\(id),\"ok\":true,\"data\":{\"folder\":\"/w\",\"git\":false,\"bare\":false,\"linkedWorktree\":false,\"repo\":null,\"branch\":null,\"defaultBranch\":null,\"dirty\":0,\"branches\":[],\"fetchedAt\":null}}\n")
        }
        defer { server.stop() }
        let host = SocketChatHost(socketPath: { server.path })
        _ = try await host.fetch("/w", ifStale: true)
    }
    #expect(lines.count == 2 && lines[0].contains("\"ifStale\":true") && lines[1].contains("ifStale") == false)
}

// A project's defaults for a new session (docs/specs/projects.md, Scope 11): they fill the draft when the project is chosen and win over Settings > Sessions.

/// A draft whose projects file holds `defaults` for `/work/web`; Settings > Sessions says `settings`.
@MainActor private func draft(defaults: String?, settings: WorkIn = .baseFolder, host: FakeChat = FakeChat()) async throws -> NewSessionModel {
    let carrier = NSTemporaryDirectory() + "carrier-" + UUID().uuidString
    try FileManager.default.createDirectory(atPath: carrier, withIntermediateDirectories: true)
    let extra = defaults.map { #","defaults":\#($0)"# } ?? ""
    try Data(#"{"projects":[{"path":"/work/web","origin":"added"\#(extra)}]}"#.utf8).write(to: URL(fileURLWithPath: carrier + "/projects.json"))
    host.agents = [ChatAgent(name: "codex", harness: "codex", found: true), ChatAgent(name: "claude", harness: "claude", found: true)]
    host.workspaces["/work/web"] = WorkspaceInfo(
        folder: "/work/web", branch: "main", defaultBranch: "main",
        branches: [.init(name: "main", remote: false), .init(name: "develop", remote: false), .init(name: "origin/release", remote: true)]
    )
    let projects = ProjectsModel(host: host, file: ProjectsFile(folder: carrier)) { _ in nil }
    projects.reload()
    let model = NewSessionModel(host: host, ensureHost: { true }, log: { _ in }, sleep: { _ in }, projectsFolder: { "/nowhere" }, workIn: { settings }, projects: projects)
    await model.load()
    return model
}

@MainActor @Test func choosingAProjectFillsTheDraftWithItsAgentWorkInAndBaseBranchAndThePersonCanChangeThem() async throws {
    let model = try await draft(defaults: #"{"agent":"claude","workIn":"worktree","baseBranch":"develop"}"#)
    #expect(model.agent == "codex") // Settings > Sessions names none: the first provider that can work
    await model.choose(folder: "/work/web")
    #expect(model.agent == "claude" && model.worktree && model.startBranch == "develop")
    // the draft shows them as its own choices, which the person changes there
    model.agent = "codex"
    await model.useWorktree(false)
    model.choose(startBranch: "main")
    #expect(model.agent == "codex" && model.worktree == false && model.startBranch == "main")
}

@MainActor @Test func aProjectsValueWinsOverSettingsSessionsAndAnUnsetOneFallsBackToIt() async throws {
    // Settings says a new worktree: the project's base folder wins, and with no value the setting stands
    let wins = try await draft(defaults: #"{"workIn":"baseFolder"}"#, settings: .newWorktree)
    await wins.choose(folder: "/work/web")
    #expect(wins.worktree == false)
    let falls = try await draft(defaults: #"{"baseBranch":"develop"}"#, settings: .newWorktree)
    await falls.choose(folder: "/work/web")
    #expect(falls.worktree && falls.projectDefaults.workIn == nil)
    // the same for the agent: the project's wins, an unset one keeps the one Settings > Sessions gave
    let agent = try await draft(defaults: #"{"agent":"claude"}"#)
    await agent.choose(folder: "/work/web")
    #expect(agent.agent == "claude")
    let unset = try await draft(defaults: nil)
    await unset.choose(folder: "/work/web")
    #expect(unset.agent == "codex" && unset.worktree == false && unset.startBranch == "main")
}

// A project that is not a git repository: a session started in it works in its folder, whatever Settings > Sessions or the project's defaults say.
@MainActor @Test func aSessionInAProjectThatIsNotAGitRepositoryWorksInItsFolder() async throws {
    let host = FakeChat()
    let model = try await draft(defaults: #"{"workIn":"worktree"}"#, settings: .newWorktree, host: host)
    host.workspaces["/work/web"] = WorkspaceInfo(folder: "/work/web", git: false)
    await model.choose(folder: "/work/web")
    #expect(model.offersWorktree == false && model.worktree == false)
    #expect(model.sentence == "Work in web in the folder (not a git repository: no worktree)")
}

@MainActor @Test func aProjectsAgentThatCannotWorkAndABranchTheFolderLacksAreLeftOutOfTheDraft() async throws {
    let host = FakeChat()
    let model = try await draft(defaults: #"{"agent":"gone","baseBranch":"deleted"}"#, host: host)
    await model.choose(folder: "/work/web")
    #expect(model.agent == "codex" && model.startBranch == "main")
}

@MainActor @Test func aProjectsModelReasoningAndAccessGoWithItsAgentOverWhatSettingsSessionsSays() async throws {
    let host = FakeChat()
    host.offered["claude"] = accessOptions
    let model = try await draft(defaults: #"{"agent":"claude","model":"haiku","access":{"permissionMode":"acceptEdits"}}"#, host: host)
    await model.choose(folder: "/work/web")
    #expect(model.agent == "claude" && model.chosenOptions == ["model": "haiku", "permissionMode": "acceptEdits"])
    // a project that names no agent leaves the options to Settings > Sessions
    let plain = try await draft(defaults: #"{"model":"haiku"}"#, host: host)
    await plain.choose(folder: "/work/web")
    #expect(plain.chosenOptions.isEmpty)
}
