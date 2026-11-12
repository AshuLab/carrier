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
    var created: [String] = []
    /// What `cloneRepo` was asked for: the draft never asks.
    var clones: [String] = []
    /// What `repoBranches` answers by repository (one not listed is refused as for a repository the login cannot see) and what it was asked for.
    var branchesOf: [String: RepoBranches] = [:]
    var branchCalls: [String] = []
    /// Where the host puts what it clones and makes; a test points it at the config's projects folder, which the real host reads at each request.
    var projects: () -> String = { "/projects" }

    func agents() async throws -> [ChatAgent] { agents }
    func list(archived wanted: Bool) async throws -> [ChatSession] { wanted ? archived : active }
    /// `AgentOfferStore.warm` asks every agent at once, so the asks are recorded under a lock.
    private let asksLock = NSLock()
    func agentOptions(_ agent: String) async throws -> AgentOffer {
        asksLock.withLock { optionAsks.append(agent) }
        guard let listed = offered[agent] else { throw ControlError.remote("the chat host does not support agentOptions") }
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
    func answer(_ id: String, approval: String, choice: String, answers: [String: String]?) async throws {}
    func setOption(_ id: String, option: String, value: String) async throws {}
    func archive(_ id: String, _ archived: Bool) async throws {}
    func delete(_ id: String) async throws {}
    func capabilities() async throws -> Set<ControlClient.Capability> { capabilities }
    func cloneRepo(_ repo: String) async throws -> ClonedRepo {
        clones.append(repo)
        return ClonedRepo(folder: "\(projects())/\(repo)", repo: repo, fetched: false)
    }
    func repoBranches(_ repo: String) async throws -> RepoBranches {
        branchCalls.append(repo)
        if let error = refuse["repoBranches"] { throw error }
        guard let listed = branchesOf[repo] else { throw ControlError.remote("\(repo) was not found, or your GitHub login cannot see it") }
        return listed
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
    _ host: FakeChat, hostStarts: Bool = true, offers: AgentOfferStore = AgentOfferStore(), log: @escaping (String) -> Void = { _ in }
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
    host.refuse["open"] = ControlError.remote("claude is not logged in; run claude once to log in")
    let model = await draft(host)
    await model.choose(folder: "/w/api")
    model.text = "hello"
    #expect(await model.send() == nil)
    #expect(model.refusal == "claude is not logged in; run claude once to log in" && model.text == "hello")
    #expect(host.calls == ["open claude /w/api"])
    #expect(signInLine(refusal: model.refusal ?? "") != nil)
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
    _ = try await SocketChatHost(socketPath: { server.path }).open(plan: SessionPlan(agent: "claude", workspace: .project("my-app"), text: "hi"))
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
    #expect(model.branchNote == nil && model.branchChange == nil)
    model.choose(startBranch: "main")
    #expect(model.branchNote == nil)
    model.choose(startBranch: "feat/x")
    #expect(model.branchNote == "The branch of the folder will change from main to feat/x when the message is sent.")
    #expect(model.warning == nil)
    model.text = "go"
    #expect(await model.send() == opened)
    #expect(host.plans.map(\.branch) == ["feat/x"] && host.plans.map(\.worktree) == [nil])
}

@MainActor @Test func aFolderWithUncommittedChangesWarnsThatTheBranchChangeWillFailAndSendingIsStillAllowed() async {
    let host = FakeChat()
    host.workspaces["/w/dirty"] = WorkspaceInfo(folder: "/w/dirty", branch: "main", dirty: 2, branches: [.init(name: "main", remote: false), .init(name: "feat/x", remote: false)])
    let model = await draft(host)
    await model.choose(folder: "/w/dirty")
    // no change picked: the worktree way out is offered
    #expect(model.warning == "2 uncommitted files in the folder. A worktree keeps them out of the agent's way.")
    model.choose(startBranch: "feat/x")
    #expect(model.branchNote == "The branch of the folder will change from main to feat/x when the message is sent.")
    #expect(model.warning == "2 uncommitted files in the folder, so changing its branch will fail and it keeps the branch it is on. Save the work first, or use a worktree.")
    model.text = "go"
    #expect(model.canSend)
    // a worktree is cut from the pick and changes no folder: no branch change, and the pick is the worktree's start
    await model.useWorktree(true)
    #expect(model.branchNote == nil && model.warning == nil)
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

@MainActor @Test func aBlankDraftHasNoTypedRepositoryNorProjectNameAndShowsTheMenu() async {
    let host = FakeChat()
    let model = await draft(host)
    model.urlText = "AshuLab/web"
    model.projectName = "scratch"
    model.blank()
    #expect(model.urlText.isEmpty && model.projectName.isEmpty && model.step == .menu)
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
    func plan(_ folder: String, _ worktree: WorktreeRequest?) -> SessionPlan { SessionPlan(agent: "claude", folder: folder, worktree: worktree, text: "hello") }
    let id = try await host.open(plan: plan("/Users/dev/carrier", WorktreeRequest(from: "origin/main", name: "my-fix")))
    let made = try #require(try await host.list(archived: false).first { $0.id == id })
    #expect(made.workspace == ChatSession.Workspace(base: "/Users/dev/carrier", branch: "carrier/my-fix") && made.folder.hasSuffix("/my-fix"))
    #expect(try await host.events(id, after: 0, limit: 10).events.map(\.kind) == ["step", "step", "user"])
    // refused as the host does
    await #expect(throws: ControlError.remote("The branch to start from is not one this repository lists")) {
        try await host.open(plan: plan("/Users/dev/carrier", WorktreeRequest(from: "nope", name: "x")))
    }
    await #expect(throws: ControlError.remote("A branch called carrier/fix-login already exists")) {
        try await host.open(plan: plan("/Users/dev/carrier", WorktreeRequest(from: "main", name: "fix-login")))
    }
    await #expect(throws: ControlError.remote("Worktrees need a git repository")) {
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
        host: host, ensureHost: { true }, log: { _ in }, sleep: { _ in }, watchEvery: .milliseconds(5), projectsFolder: { projects },
        readConfig: { config.json }, writeConfig: { try config.write($0) }
    )
    await model.load()
    return model
}

/// Waits (briefly) for something a task started in the background to happen.
@MainActor private func settle(_ done: () -> Bool) async {
    for _ in 0..<500 where done() == false { try? await Task.sleep(for: .milliseconds(2)) }
}

@MainActor @Test func theMenuListsOpenLocalFolderAndGitHubURLOnlyForAHostThatPreparesARepository() async {
    let host = FakeChat()
    #expect(await popover(host).sources == [.localFolder, .githubURL, .githubRepos, .newProject])
    host.capabilities = [.repoBranches, .createProject]
    #expect(await popover(host).sources == [.localFolder, .githubURL, .newProject])
    host.capabilities = [.repoBranches]
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
    #expect(model.step == .url && model.canUseRepo == false && model.repoButton == "Use (cloned when sent)")
    model.urlText = "AshuLab"
    #expect(model.canUseRepo == false)
    model.urlText = "https://github.com/AshuLab/carrier.git"
    #expect(model.canUseRepo && model.reference == "AshuLab/carrier")
    model.show(.menu)
    #expect(model.step == .menu)
}

@MainActor @Test func choosingARepositoryToCloneOnlyFillsThePlanWithGitHubsBranchesAndTouchesNothing() async {
    let host = FakeChat()
    host.branchesOf["AshuLab/carrier"] = RepoBranches(defaultBranch: "main", branches: ["main", "feat/x"])
    let config = FakeConfig()
    let model = await popover(host, config: config)
    model.show(.url)
    model.urlText = "AshuLab/carrier"
    await model.choose(folder: "/w/api")
    #expect(await model.useRepo())
    // nothing was cloned, nothing was written, and nothing was asked of the folder, which is not there
    #expect(host.clones.isEmpty && config.writes == 0 && host.branchCalls == ["AshuLab/carrier"])
    #expect(model.repo == "AshuLab/carrier" && model.toClone && model.folder == "/nowhere/AshuLab/carrier" && model.urlText.isEmpty)
    #expect(model.workspace?.branches.map(\.name) == ["main", "feat/x"] && model.workspace?.branch == "main" && model.startBranch == "main")
    #expect(model.picker(query: "")?.local.map(\.name) == ["main", "feat/x"])
    #expect(model.sentence == "Work in carrier on the base folder (main)" && model.offersWorktree && model.canSend == false)
    #expect(model.sendSteps == [SendStep(
        icon: "arrow.down.circle", title: "Download the repository", parts: [.text("When you send, Carrier downloads "), .code("AshuLab/carrier"), .text(" from GitHub into "), .code(model.projectsPath), .text(". Only this first time: later sessions reuse that copy.")], help: "/nowhere/AshuLab/carrier")])
    // a fresh clone has no uncommitted changes, and nothing is said of the folder's branch
    #expect(model.warning == nil && model.branchNote == nil)
    model.choose(startBranch: "feat/x")
    #expect(model.branchNote == nil && model.warning == nil)
}

@MainActor @Test func aWorktreeForARepositoryToCloneGetsAGeneratedNameAtOnceAndTheHostIsNotAskedForOne() async {
    let host = FakeChat()
    host.branchesOf["AshuLab/carrier"] = RepoBranches(defaultBranch: "main", branches: ["main", "feat/x"])
    let model = await popover(host)
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
    let model = await popover(host)
    await model.choose(repo: "AshuLab/carrier")
    model.choose(startBranch: "feat/x")
    model.text = "hello"
    #expect(await model.send() == opened)
    #expect(host.plans == [SessionPlan(agent: "claude", workspace: .repo("AshuLab/carrier"), branch: "feat/x", text: "hello")])
    #expect(host.clones.isEmpty && model.repo == nil && model.folder == nil)
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
    let model = await popover(host, projects: root)
    model.show(.url)
    model.urlText = "github.com/ashulab/Carrier"
    #expect(await model.useRepo())
    #expect(host.branchCalls.isEmpty && host.clones.isEmpty && model.toClone == false && model.repo == "AshuLab/carrier")
    #expect(model.folder == root + "/AshuLab/carrier" && model.workspace?.dirty == 3 && model.warning != nil)
    #expect(model.sendSteps.map(\.parts) == [[.text("Updates "), .code("AshuLab/carrier"), .text(" from GitHub first")]])
    model.text = "hello"
    _ = await model.send()
    #expect(host.plans.count == 1 && host.plans[0].folder == nil)
}

@MainActor @Test func aRepositoryThatGitHubWillNotListStillWorksOnItsDefaultBranchAndSaysWhy() async {
    let host = FakeChat()
    host.refuse["repoBranches"] = ControlError.remote("GitHub could not be reached; check the network connection")
    let model = await popover(host)
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
    let model = await popover(host)
    await model.choose(repo: "AshuLab/api")
    #expect(model.branchesPartial && model.workspace?.branches.map(\.name) == ["trunk", "a", "b"])
    await model.choose(folder: "/w/api")
    #expect(model.branchesPartial == false && model.repo == nil && model.toClone == false)
}

@MainActor @Test func aCancelledRepositoryPlanComesBackInTheDraftWithItsBranchAndWorktree() async {
    let host = FakeChat()
    host.branchesOf["AshuLab/carrier"] = RepoBranches(defaultBranch: "main", branches: ["main", "feat/x"])
    let model = await popover(host)
    model.restore(SessionPlan(agent: "claude", workspace: .repo("AshuLab/carrier"), worktree: WorktreeRequest(from: "feat/x"), text: "again"))
    await model.load()
    #expect(model.repo == "AshuLab/carrier" && model.toClone && model.worktree && model.startBranch == "feat/x" && model.text == "again" && model.worktreeName.isEmpty == false)
    #expect(host.clones.isEmpty)
}

@MainActor @Test func theNewProjectStepShowsThePathAndItsButtonStaysOffForANameTheHostWouldRefuse() async throws {
    let root = try projectsRoot(["local/taken", "AshuLab/carrier"])
    defer { try? FileManager.default.removeItem(atPath: root) }
    let model = await popover(FakeChat(), projects: root)
    model.openPicker()
    model.show(.project)
    #expect(model.step == .project && model.projectPath == root + "/local/<name>" && model.canUseNow == false && model.projectNameWarning == nil)
    for bad in [".", "..", ".hidden", "a/b", "../x", "a b", "-x", String(repeating: "a", count: 101)] {
        model.projectName = bad
        #expect(model.canUseNow == false && model.projectNameWarning != nil, "\(bad)")
    }
    model.projectName = "Taken"
    #expect(model.canUseNow == false && model.projectNameWarning == "Taken is already a project; choose another name")
    model.projectName = "my-idea.2"
    #expect(model.canUseNow && model.projectNameWarning == nil && model.projectPath == root + "/local/my-idea.2")
    model.projectName = String(repeating: "a", count: 100)
    #expect(model.canUseNow)
}

@MainActor @Test func choosingAProjectOnlyFillsThePlanAndOffersNoWorktreeNorBranch() async {
    let host = FakeChat()
    let model = await popover(host)
    model.show(.project)
    model.projectName = "my-idea"
    #expect(model.useProject())
    #expect(host.created.isEmpty && host.calls.isEmpty && model.projectName.isEmpty)
    #expect(model.newProject == "my-idea" && model.folder == "/nowhere/local/my-idea")
    #expect(model.projectNote == "/nowhere/local/my-idea will be created, with git ready, when the message is sent.")
    #expect(model.sentence == "Work in my-idea in the folder (new project, no commits yet: no worktree)")
    #expect(model.offersWorktree == false && model.warning == nil && model.branchNote == nil && model.picked == nil)
    await model.useWorktree(true)
    #expect(model.worktree == false && model.workspaceProblem == nil)
    #expect(model.watchNotes.isEmpty)
    model.clearWorkspace()
    #expect(model.newProject == nil && model.folder == nil && model.projectNote == nil)
}

@MainActor @Test func aNameTheHostWouldRefuseIsNotUsed() async throws {
    let root = try projectsRoot(["local/taken"])
    defer { try? FileManager.default.removeItem(atPath: root) }
    let model = await popover(FakeChat(), projects: root)
    model.openPicker()
    model.show(.project)
    model.projectName = "Taken"
    #expect(model.useProject() == false && model.newProject == nil && model.folder == nil && model.step == .project)
}

@MainActor @Test func sendingAProjectPlanAsksTheHostForTheProjectStepAndNothingElse() async {
    let host = FakeChat()
    let model = await popover(host)
    model.show(.project)
    model.projectName = "my-idea"
    _ = model.useProject()
    model.text = "build it"
    #expect(await model.send() == opened)
    #expect(host.plans == [SessionPlan(agent: "claude", workspace: .project("my-idea"), text: "build it")])
    #expect(host.created.isEmpty)
    #expect(model.newProject == nil && model.folder == nil)
}

@MainActor @Test func aCancelledProjectPlanComesBackInTheDraft() async {
    let model = await popover(FakeChat())
    model.restore(SessionPlan(agent: "claude", workspace: .project("my-idea"), text: "again"))
    await model.load()
    #expect(model.newProject == "my-idea" && model.folder == "/nowhere/local/my-idea" && model.text == "again")
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
    func open(plan: SessionPlan) async throws -> String { opened }
    func workspace(_ folder: String) async throws -> WorkspaceInfo { cleanRepo(folder) }
    func fetch(_ folder: String) async throws -> WorkspaceInfo { cleanRepo(folder) }
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
    let model = await popover(host, config: config)
    await model.choose(repo: repo)
    model.text = "hello"
    #expect(await model.send() == opened)
    return model
}

@MainActor @Test func theRepositoryIsAddedToTheConfigOnlyOnceTheMessageStepIsDoneKeepingEverythingElseAndSaysItListensFromTheNextStart() async throws {
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
    #expect(model.watchNotes[opened] == WatchNote(text: "Carrier will listen to AshuLab/carrier from its next start.", failed: false))
    // once: looking again changes nothing
    await model.settleWatches()
    try await Task.sleep(for: .milliseconds(30))
    #expect(config.writes == 1 && host.clones.isEmpty)
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
        let model = await popover(host, config: config)
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
    #expect(await model.useRepo())
    #expect(model.folder == new + "/acme/web" && host.clones.isEmpty)
    model.show(.project)
    model.projectName = "idea"
    #expect(model.useProject())
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

@MainActor @Test func choosingARowFillsThePlanLikeTheUrlStepAndNothingIsClonedOrWritten() async {
    let host = FakeChat()
    host.repoPages = [1: page(["AshuLab/carrier"], more: false, login: "vemec")]
    host.branchesOf["AshuLab/carrier"] = RepoBranches(defaultBranch: "main", branches: ["main"])
    let config = FakeConfig()
    let model = await popover(host, config: config)
    await model.showRepos()
    await model.choose(repo: "AshuLab/carrier")
    #expect(host.clones.isEmpty && config.writes == 0 && model.repo == "AshuLab/carrier" && model.toClone && model.folder == "/nowhere/AshuLab/carrier")
    #expect(model.repoList.repos.count == 1 && model.login == "vemec")
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
    host.refuse["health"] = ControlError.remote("boom")
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

@MainActor @Test func withGhSignedOutTheDraftKeepsTheGitHubStepsClosedAndTheOthersOpen() async {
    let host = FakeChat()
    host.healthReply = HostHealth(git: .ready, gh: .signedOut, agents: [])
    host.capabilities.insert(.health)
    let store = HealthStore(host: host)
    await store.check(.open)
    let model = NewSessionModel(host: host, health: store, log: { _ in }, sleep: { _ in }, projectsFolder: { "/nowhere" })
    await model.load()
    #expect(model.sources == [.localFolder, .githubURL, .githubRepos, .newProject])
    #expect(model.sourceReason(.githubURL) != nil && model.sourceReason(.githubRepos) != nil)
    #expect(model.sourceReason(.localFolder) == nil && model.sourceReason(.newProject) == nil)
    model.show(.url)
    await model.showRepos()
    #expect(model.step == .menu && host.repoCalls.isEmpty)
    model.show(.project)
    #expect(model.step == .project)
    host.healthReply = HostHealth(git: .ready, gh: .unknown, agents: [])
    await store.check(.refresh)
    model.show(.url)
    #expect(model.step == .url)
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
    #expect(host.calls.filter { $0.hasPrefix("open") }.isEmpty && host.created.isEmpty && host.clones.isEmpty)
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
    #expect(Set(host.optionAsks) == ["claude", "codex"] && store.offer("codex") == offer("gpt") && store.offer("gone") == nil)
}

