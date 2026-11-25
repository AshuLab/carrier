import Foundation
import Testing
@testable import CarrierCore

private let fixtures = testPaths().fixtures.path

private func hello(_ capabilities: String = "\"agents\",\"list\"", protocol version: Int = 1) -> String {
    "{\"event\":\"hello\",\"protocol\":\(version),\"pid\":42,\"startedAt\":1000,\"version\":\"x\",\"capabilities\":[\(capabilities)]}\n"
}

@Test func theChatSocketIsUnderTheCarrierFolderAndNeverReadsTheConfig() {
    #expect(chatSocketPath(environment: [:], home: "/Users/x") == "/Users/x/.carrier/chat/state/chat.sock")
    #expect(chatSocketPath(environment: ["CARRIER_HOME": ""], home: "/Users/x") == "/Users/x/.carrier/chat/state/chat.sock")
    #expect(chatSocketPath(environment: ["CARRIER_HOME": "/tmp/scratch"], home: "/Users/x") == "/tmp/scratch/chat/state/chat.sock")
}

@Test func theClientReadsAgentsAndListFromTheFixtureHost() async throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.chatSocketPath })

    let agents = try await host.agents()
    #expect(agents.map(\.name) == ["claude", "codex", "claude-beta"])
    #expect(agents.map(\.found) == [true, true, false])
    #expect(agents.first?.model == "claude-sonnet-5-5")
    // an agent named by the person still has its tool's mark: the harness is what it is looked up by, and an agent not known is its own name
    #expect(AgentAccounts.harness(of: "claude-beta") == "claude" && AgentAccounts.harness(of: "codex") == "codex")
    #expect(AgentAccounts.harness(of: "nobody") == "nobody")

    let active = try await host.list(archived: false)
    // the fifth is a session whose turn ended while a build runs; the twelve after it fill the sidebar's other states (unread, a single task, plain, pinned, a worktree preparing, a long title, every component of a conversation, every tool...), and the last is the one with three subagents
    #expect(active.map(\.state) == [.working, .waitingApproval, .idle, .idle, .idle, .idle, .idle, .working, .idle, .working, .idle, .preparing, .idle, .waitingApproval, .working, .idle, .idle, .idle])
    #expect(active.map(\.live) == [true, true, false, false, true, true, true, true, true, true, true, true, false, true, true, true, true, false])
    let worktree = "/Users/dev/work/web"
    #expect(active.map { $0.workspace?.base } == [nil, nil, nil, worktree, nil, nil, nil, nil, nil, worktree, worktree, worktree, nil, nil, nil, nil, nil, nil])
    #expect(active.map(\.background.count) == [0, 0, 0, 0, 3, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
    #expect(active.compactMap(\.pullRequest).map(\.number) == [983, 979, 412, 88, 1051, 1060, 431, 398, 77] && active.compactMap(\.diff).count == 10)
    #expect(try await host.list(archived: true).map(\.archived) == [true, true])
    // the parent carries its children and none of the other sessions has a parent or children
    #expect(active.first?.children == [
        ChatSession.Child(id: "0d1e2f3a-9b8c-4d54-8a7b-8b9c0d1e2f0b", agent: "codex", harness: "codex", state: .working, level: 1, needsPerson: false),
        ChatSession.Child(id: "1e2f3a4b-0c9d-4e65-9b8c-9c0d1e2f3a0c", agent: "claude", harness: "claude", state: .waitingApproval, level: 0, needsPerson: true),
    ])
    #expect(active.compactMap(\.parentSessionId).isEmpty && active.dropFirst().allSatisfy { $0.children.isEmpty })
}

@Test func aSessionCarriesItsParentAndItsChildrenOrNone() throws {
    func decode(_ extra: String) throws -> ChatSession {
        let json = #"{"id":"a","agent":"claude","harness":"claude","folder":"/w","title":"t","state":"idle","createdAt":1,"lastActiveAt":2,"archived":false,"live":false\#(extra)}"#
        return try JSONDecoder().decode(ChatSession.self, from: Data(json.utf8))
    }
    let child = try decode(#","parentSessionId":"p1","children":[]"#)
    #expect(child.parentSessionId == "p1" && child.children.isEmpty)
    let parent = try decode(#","parentSessionId":null,"children":[{"id":"c1","agent":"codex","harness":"codex","state":"idle","level":2,"needsPerson":false}]"#)
    #expect(parent.parentSessionId == nil && parent.children.map(\.id) == ["c1"] && parent.children.first?.level == 2)
    // a host that says nothing of either
    let older = try decode("")
    #expect(older.parentSessionId == nil && older.children.isEmpty)
    // a child whose level the host does not say
    #expect(try decode(#","children":[{"id":"c1","agent":"a","harness":"claude","state":"working","needsPerson":false}]"#).children.first?.level == nil)
}

@Test func theFixtureListIsRelativeToTheLaunchAndMarksWhatTheAppSeedsAsUnreadAndPinned() async throws {
    let beforeMs = Int(Date().timeIntervalSince1970 * 1000)
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.chatSocketPath })
    let active = try await host.list(archived: false)
    let afterMs = Int(Date().timeIntervalSince1970 * 1000)
    // "5 seconds ago" in the golden list is made when the server starts, so it lies between the two readings whatever the load of the run,
    // and the three tasks of the build session started minutes before
    #expect(active[0].lastActiveAt + 5_000 >= beforeMs && active[0].lastActiveAt + 5_000 <= afterMs)
    #expect(active[4].background.allSatisfy { ($0.startedAt.map { Date().timeIntervalSince($0) } ?? 0) > 90 })
    #expect(server.unreadSessionIds == ["a1000000-0000-4000-8000-000000000001"] && server.pinnedSessionIds == ["a1000000-0000-4000-8000-000000000004"])
}

@Test func theFixtureHostCutsAPlansWorktreeFromTheRemoteBranchWhenTheStartIsRemote() async throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.chatSocketPath })
    func plan(_ branch: String, _ startFrom: WorktreeStart?) -> SessionPlan {
        SessionPlan(agent: "claude", folder: "/Users/dev/web", worktree: WorktreeRequest(from: branch, name: "x-\(branch.count)", startFrom: startFrom), options: [:], text: "hi")
    }
    // `release/2` is listed only as `origin/release/2`: a remote start finds it, a local one is refused as the host refuses it
    _ = try await host.open(plan: plan("release/2", .remote))
    await #expect(throws: ControlError.remote(Refusal(code: "worktree.startNotListed", text: "The branch to start from is not one this repository lists"))) { _ = try await host.open(plan: plan("release/2", .local)) }
    _ = try await host.open(plan: plan("main", .remote))
    _ = try await host.open(plan: plan("main", .local))
    let opened = try await host.list(archived: false).filter { $0.workspace?.base == "/Users/dev/web" }
    #expect(opened.count >= 3)
}

@Test func theHelloCarriesTheChatCapabilities() throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let client = try #require(ControlClient.connect(path: server.chatSocketPath))
    #expect(try client.hello().capabilities == [.agents, .list, .open, .resume, .send, .events, .answer, .setOption, .archive, .delete, .deletePreview, .workspace, .fetch, .suggestName, .checkName, .cloneRepo, .createProject, .githubRepos, .repoBranches, .providers, .plan, .usage, .usageOverride, .accountIdentity, .accountPalette, .switchAgent, .interrupt, .stopTask, .worktreeStart, .fetchIfStale, .projects, .textGenerators, .regenerateTitle, .regenerateTitles, .config])
}

@Test func theFixtureHostAnswersAnythingElseWithAnError() throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let client = try #require(ControlClient.connect(path: server.chatSocketPath))
    _ = try client.hello()
    #expect(throws: ControlError.remote(.words("unknown request"))) { try client.request("resume") }
    // the connection is still good afterwards
    #expect(try client.request("list").isEmpty == false)
}

@Test func anErrorReplyIsARemoteError() async {
    let server = TestServer { connection in
        connection.send(hello())
        guard let id = connection.readRequestId() else { return }
        connection.send("{\"id\":\(id),\"ok\":false,\"error\":\"internal error\"}\n")
    }
    defer { server.stop() }
    await #expect(throws: ControlError.remote(.words("internal error"))) { try await SocketChatHost(socketPath: { server.path }).agents() }
}

@Test func aHostThatGoesAwayOrIsNotThereIsClosed() async {
    let server = TestServer { connection in
        connection.send(hello())
        _ = connection.readRequestId()
        // closes without answering
    }
    defer { server.stop() }
    await #expect(throws: ControlError.closed) { try await SocketChatHost(socketPath: { server.path }).agents() }
    await #expect(throws: ControlError.closed) { try await SocketChatHost(socketPath: { "/tmp/cc-missing-\(UUID().uuidString.prefix(8)).sock" }).list(archived: false) }
}

@Test func aRequestTheHelloDoesNotListIsNotSent() async {
    var asked = false
    let server = TestServer { connection in
        connection.send(hello("\"agents\""))
        asked = connection.readRequestId() != nil
    }
    defer { server.stop() }
    await #expect(throws: ControlError.remote(.hostLacks("list"))) { try await SocketChatHost(socketPath: { server.path }).list(archived: false) }
    #expect(asked == false)
}

@Test func aHostOfAnotherProtocolIsNotAskedAndSaysWhichSideToUpdate() async {
    let cases = [
        (0, "carrier is older than this app. Run brew upgrade carrier in Terminal, then restart Carrier."),
        (2, "This app is older than carrier. It updates itself; if it has not, run brew upgrade --cask carrier in Terminal, then open the app again."),
    ]
    for (version, sentence) in cases {
        var asked = false
        let server = TestServer { connection in
            connection.send(hello(protocol: version))
            asked = connection.readRequestId() != nil
        }
        defer { server.stop() }
        let host = SocketChatHost(socketPath: { server.path })
        let refusal = Refusal(code: version == 0 ? "app.protocol.carrierOlder" : "app.protocol.appOlder", text: sentence)
        await #expect(throws: ControlError.remote(refusal)) { try await host.list(archived: false) }
        await #expect(throws: ControlError.remote(refusal)) { try await host.capabilities() }
        #expect(asked == false)
    }
}

@Test func aHelloWithNoIntegerProtocolIsABadLine() async {
    let server = TestServer { $0.send("{\"event\":\"hello\",\"protocol\":\"1\",\"pid\":42,\"startedAt\":1000}\n") }
    defer { server.stop() }
    await #expect(throws: ControlError.badLine) { try await SocketChatHost(socketPath: { server.path }).list(archived: false) }
}

@Test func aReplyThatDoesNotDecodeIsABadLine() async {
    let server = TestServer { connection in
        connection.send(hello())
        guard let id = connection.readRequestId() else { return }
        connection.send("{\"id\":\(id),\"ok\":true,\"data\":{\"agents\":1}}\n")
    }
    defer { server.stop() }
    await #expect(throws: ControlError.badLine) { try await SocketChatHost(socketPath: { server.path }).agents() }
}

@Test func theAppSendsNoCloneRepoOrCreateProjectRequest() throws {
    // a plan replaced both (#668); a host keeps them only for apps older than this one
    let sources = testPaths().sources
    let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
    var scanned = 0
    for case let file as URL in files where file.pathExtension == "swift" {
        scanned += 1
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("\"cloneRepo\"") == false && text.contains("\"createProject\"") == false, "\(file.lastPathComponent) sends a request the plan replaced")
    }
    // a wrong path would scan nothing and pass
    #expect(scanned > 50)
}

@Test func theFixtureHostAnswersGithubReposByPageFromTheGoldenFileWithTheLoginOnPageOneOnly() async throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.chatSocketPath })
    #expect(try await host.capabilities().contains(.githubRepos))
    let first = try await host.githubRepos(page: 1)
    #expect(first.login == "vemec" && first.hasMore && first.repos.count == 6)
    #expect(first.repos[0] == AvailableRepo(name: "AshuLab/carrier", isPrivate: true, pushedAt: "2026-10-28T15:40:00Z"))
    // the host's listing carries the description, which the sheet shows; a repository with none has nil
    #expect(first.repos[1].about == "The marketing site and the docs" && first.repos[3].about == nil)
    #expect(first.repos[5] == AvailableRepo(name: "vemec/dotfiles", isPrivate: false, pushedAt: nil))
    let second = try await host.githubRepos(page: 2)
    #expect(second.login == nil && second.hasMore == false && second.repos.map(\.name) == ["optyra/docs", "vemec/old-experiments"])
    await #expect(throws: ControlError.remote(Refusal(code: "github.noAnswer", text: "GitHub did not answer; check \"gh auth status\""))) { try await host.githubRepos(page: 3) }
}

@Test func aHostWithoutTheGithubReposCapabilityIsNotAskedToList() async {
    var asked = false
    let server = TestServer { connection in
        connection.send(hello("\"agents\""))
        asked = connection.readRequestId() != nil
    }
    defer { server.stop() }
    await #expect(throws: ControlError.remote(.hostLacks("githubRepos"))) { try await SocketChatHost(socketPath: { server.path }).githubRepos(page: 1) }
    #expect(asked == false)
}

@Test func theHealthReplyIsDecodedAndAStateItDoesNotKnowReadsAsUnknown() async throws {
    let server = TestServer { connection in
        connection.send(hello("\"health\""))
        guard let id = connection.readRequestId() else { return }
        connection.send("{\"id\":\(id),\"ok\":true,\"data\":{\"git\":\"ready\",\"gh\":\"signedOut\",\"agents\":[{\"name\":\"claude\",\"harness\":\"claude\",\"state\":\"missing\"},{\"name\":\"codex\",\"harness\":\"codex\",\"state\":\"asleep\"}]}}\n")
    }
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.path })
    #expect(try await host.health(refresh: true) == HostHealth(git: .ready, gh: .signedOut, agents: [.init(name: "claude", harness: "claude", state: .missing), .init(name: "codex", harness: "codex", state: .unknown)]))
}

@Test func aHostWithoutTheHealthCapabilityIsNotAskedForIt() async {
    var asked = false
    let server = TestServer { connection in
        connection.send(hello("\"agents\""))
        asked = connection.readRequestId() != nil
    }
    defer { server.stop() }
    await #expect(throws: ControlError.remote(.hostLacks("health"))) { try await SocketChatHost(socketPath: { server.path }).health(refresh: false) }
    #expect(asked == false)
}

@Test @MainActor func theProvidersStoreHoldsTheReplyOfAHostThatListsProvidersAndSaysWhyOtherwise() async throws {
    let fixtures = testPaths().fixtures.path
    let fixture = try FixtureServer(fixtures: fixtures)
    defer { fixture.stop() }
    let store = ProvidersStore(host: SocketChatHost(socketPath: { fixture.chatSocketPath }), log: { _ in }, bundle: english.bundle, locale: english.locale)
    #expect(store.outcome == .unasked)
    await store.load()
    guard case .reply(let reply) = store.outcome else { throw ControlError.closed }
    #expect(reply.accounts.map(\.name) == ["claude", "claude-work", "codex"] && reply.problem == nil)

    let old = TestServer { connection in connection.send(hello("\"agents\"")) }
    defer { old.stop() }
    let tooOld = ProvidersStore(host: SocketChatHost(socketPath: { old.path }), log: { _ in }, bundle: english.bundle, locale: english.locale)
    await tooOld.load()
    #expect(tooOld.outcome == .tooOld)

    let absent = ProvidersStore(host: SocketChatHost(socketPath: { "/tmp/carrier-no-such-host.sock" }), log: { _ in }, bundle: english.bundle, locale: english.locale)
    await absent.load()
    #expect(absent.outcome == .noHost)

    let failing = TestServer { connection in
        connection.send(hello("\"providers\""))
        guard let id = connection.readRequestId() else { return }
        connection.send("{\"id\":\(id),\"ok\":false,\"error\":\"internal error\"}\n")
    }
    defer { failing.stop() }
    let failed = ProvidersStore(host: SocketChatHost(socketPath: { failing.path }), log: { _ in }, bundle: english.bundle, locale: english.locale)
    await failed.load()
    #expect(failed.outcome == .failed("internal error"))
}

// MARK: the preparation of a session

@Test func theEventsReplyCarriesStepEventsThePreparationAndTheProgress() throws {
    let json = """
    {"events":[{"id":1,"at":5,"kind":"step","step":"clone","status":"failed","detail":"Could not reach github.com"}],"cursor":1,"streaming":"",
     "session":{"state":"preparing","preparation":"running"},"approvals":[],"options":[],"commands":[],"progress":"Receiving objects: 45%"}
    """
    let reply = try JSONDecoder().decode(ChatEvents.self, from: Data(json.utf8))
    #expect(reply.events.first?.step == "clone" && reply.events.first?.status == "failed" && reply.events.first?.detail == "Could not reach github.com")
    #expect(reply.state == .preparing && reply.preparation == .running && reply.progress == "Receiving objects: 45%")
}

@Test func aStepAndACloneDecodeTheirCodeAndParamsAndOnesWithoutStillDecode() throws {
    let step = #"{"events":[{"id":1,"at":5,"kind":"step","step":"clone","status":"failed","detail":"d","code":"session.prepare.cloneFailed","params":{"repo":"a/b"}}],"cursor":1,"streaming":"","session":{"state":"idle"}}"#
    let event = try JSONDecoder().decode(ChatEvents.self, from: Data(step.utf8)).events[0]
    #expect(event.code == "session.prepare.cloneFailed" && event.params == ["repo": "a/b"])
    let old = #"{"events":[{"id":1,"at":5,"kind":"step","step":"clone","status":"failed","detail":"d"}],"cursor":1,"streaming":"","session":{"state":"idle"}}"#
    let oldEvent = try JSONDecoder().decode(ChatEvents.self, from: Data(old.utf8)).events[0]
    #expect(oldEvent.code == nil && oldEvent.params == nil && oldEvent.detail == "d")

    let clone = try JSONDecoder().decode(ProjectClone.self, from: Data(#"{"repo":"a/b","folder":"/f","state":"failed","error":"e","code":"folder.cloneFailed","params":{"n":1}}"#.utf8))
    #expect(clone.code == "folder.cloneFailed" && clone.params == ["n": 1])
    let oldClone = try JSONDecoder().decode(ProjectClone.self, from: Data(#"{"repo":"a/b","folder":"/f","state":"failed","error":"e"}"#.utf8))
    #expect(oldClone.code == nil && oldClone.params == nil && oldClone.error == "e")
}

@Test func aHostThatLeavesTheNewFieldsOutOrSaysNullStillDecodes() throws {
    let bare = #"{"events":[],"cursor":0,"streaming":"","session":{"state":"idle"}}"#
    let reply = try JSONDecoder().decode(ChatEvents.self, from: Data(bare.utf8))
    #expect(reply.preparation == nil && reply.progress == nil)
    let nulls = #"{"events":[],"cursor":0,"streaming":"","session":{"state":"idle","preparation":null},"progress":null}"#
    let withNulls = try JSONDecoder().decode(ChatEvents.self, from: Data(nulls.utf8))
    #expect(withNulls.preparation == nil && withNulls.progress == nil)
    // a preparation this app does not know is none, not a failure to read the reply
    let newer = #"{"events":[],"cursor":0,"streaming":"","session":{"state":"idle","preparation":"queued"}}"#
    #expect(try JSONDecoder().decode(ChatEvents.self, from: Data(newer.utf8)).preparation == nil)
}

@Test func aSessionInTheListCarriesItsPreparationOrNone() throws {
    func decode(_ extra: String) throws -> ChatSession {
        let json = #"{"id":"a","agent":"claude","harness":"claude","folder":"/w","title":"t","state":"\#(extra)","createdAt":1,"lastActiveAt":2,"archived":false,"live":false}"#
        return try JSONDecoder().decode(ChatSession.self, from: Data(json.utf8))
    }
    let preparing = try decode(#"preparing","preparation":"running"#)
    #expect(preparing.state == .preparing && preparing.preparation == .running)
    #expect(try decode(#"idle","preparation":"failed"#).preparation == .failed)
    #expect(try decode("idle").preparation == nil)
}

@Test func retryAndCancelOfAPreparationGoOnTheWireBehindPlanAndTheCancelReadsThePlanBack() async throws {
    var lines: [String] = []
    let server = TestServer { connection in
        connection.send(hello("\"plan\""))
        guard let line = connection.readLine(), let id = (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])?["id"] as? Int else { return }
        lines.append(line)
        if line.contains("retryPreparation") { return connection.send("{\"id\":\(id),\"ok\":true,\"data\":{\"session\":{\"id\":\"x\"}}}\n") }
        connection.send("{\"id\":\(id),\"ok\":true,\"data\":{\"plan\":{\"workspace\":{\"kind\":\"folder\",\"folder\":\"/w/api\"},\"agent\":\"claude\",\"text\":\"hi\\nthere\",\"options\":{\"model\":\"haiku\"},\"branch\":\"main\",\"worktree\":{\"name\":\"my-fix\",\"startFrom\":\"remote\"}}}}\n")
    }
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.path })
    let sessionId = "5d1f7c3a-0b6e-4a52-9a1d-3c7e8b2f4a01"
    try await host.retryPreparation(sessionId)
    let plan = try await host.cancelPreparation(sessionId)
    #expect(plan == SessionPlan(agent: "claude", folder: "/w/api", worktree: WorktreeRequest(from: "main", name: "my-fix", startFrom: .remote), options: ["model": "haiku"], text: "hi\nthere"))
    let sent = lines.compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
    #expect(sent.map { $0["cmd"] as? String } == ["retryPreparation", "cancelPreparation"] && sent.allSatisfy { $0["sessionId"] as? String == sessionId && $0.keys.sorted() == ["cmd", "id", "sessionId"] })
}

@Test func aPlanForABranchWithNoWorktreeComesBackAsABranchAndAHostWithoutPlanIsNotAsked() async throws {
    let server = TestServer { connection in
        connection.send(hello("\"agents\""))
        guard let line = connection.readLine(), let id = (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])?["id"] as? Int else { return }
        connection.send("{\"id\":\(id),\"ok\":true,\"data\":{\"plan\":{\"workspace\":{\"kind\":\"folder\",\"folder\":\"/w/api\"},\"agent\":\"claude\",\"text\":\"hi\",\"branch\":\"feat/x\"}}}\n")
    }
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.path })
    // a host that does not list `plan` is never sent either request
    await #expect(throws: ControlError.remote(.hostLacks("cancelPreparation"))) { _ = try await host.cancelPreparation("5d1f7c3a-0b6e-4a52-9a1d-3c7e8b2f4a01") }
}

@Test func aCancelledPlanForARepositoryIsReadBackWithItsBranchAndWorktree() async throws {
    let server = TestServer { connection in
        connection.send(hello("\"plan\""))
        guard let line = connection.readLine(), let id = (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])?["id"] as? Int else { return }
        connection.send("{\"id\":\(id),\"ok\":true,\"data\":{\"plan\":{\"workspace\":{\"kind\":\"repo\",\"repo\":\"a/b\"},\"agent\":\"claude\",\"text\":\"hi\",\"branch\":\"feat/x\",\"worktree\":{}}}}\n")
    }
    defer { server.stop() }
    let plan = try await SocketChatHost(socketPath: { server.path }).cancelPreparation("5d1f7c3a-0b6e-4a52-9a1d-3c7e8b2f4a01")
    #expect(plan == SessionPlan(agent: "claude", workspace: .repo("a/b"), worktree: WorktreeRequest(from: "feat/x"), text: "hi"))
}

@Test func aCancelThatAnswersANullPlanIsASessionThatStaysNotAnError() async throws {
    let server = TestServer { connection in
        connection.send(hello("\"plan\""))
        guard let line = connection.readLine(), let id = (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])?["id"] as? Int else { return }
        connection.send("{\"id\":\(id),\"ok\":true,\"data\":{\"plan\":null}}\n")
    }
    defer { server.stop() }
    let plan = try await SocketChatHost(socketPath: { server.path }).cancelPreparation("5d1f7c3a-0b6e-4a52-9a1d-3c7e8b2f4a01")
    #expect(plan == nil)
}

@Test func aCancelledPlanForANewProjectIsReadBackFromTheKindThatStayedProject() async throws {
    let server = TestServer { connection in
        connection.send(hello("\"plan\""))
        guard let line = connection.readLine(), let id = (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])?["id"] as? Int else { return }
        connection.send("{\"id\":\(id),\"ok\":true,\"data\":{\"plan\":{\"workspace\":{\"kind\":\"project\",\"name\":\"my-app\"},\"agent\":\"claude\",\"text\":\"hi\"}}}\n")
    }
    defer { server.stop() }
    let plan = try await SocketChatHost(socketPath: { server.path }).cancelPreparation("5d1f7c3a-0b6e-4a52-9a1d-3c7e8b2f4a01")
    #expect(plan == SessionPlan(agent: "claude", workspace: .newProject("my-app"), text: "hi"))
}

@Test func aCancelledPlanWithAWorkspaceThisAppDoesNotKnowIsNotRead() async throws {
    let server = TestServer { connection in
        connection.send(hello("\"plan\""))
        guard let line = connection.readLine(), let id = (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])?["id"] as? Int else { return }
        connection.send("{\"id\":\(id),\"ok\":true,\"data\":{\"plan\":{\"workspace\":{\"kind\":\"remote\",\"repo\":\"a/b\"},\"agent\":\"claude\",\"text\":\"hi\"}}}\n")
    }
    defer { server.stop() }
    await #expect(throws: ControlError.badLine) { _ = try await SocketChatHost(socketPath: { server.path }).cancelPreparation("5d1f7c3a-0b6e-4a52-9a1d-3c7e8b2f4a01") }
}

@Test func theFixtureHostAnswersRepoBranchesFromTheGoldenFileAndRefusesWhatItDoesNotList() async throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.chatSocketPath })
    #expect(try await host.capabilities().contains(.repoBranches))
    #expect(try await host.repoBranches("AshuLab/web") == RepoBranches(defaultBranch: "main", branches: ["main", "feat/x"], hasMore: false))
    #expect(try await host.repoBranches("AshuLab/api") == RepoBranches(defaultBranch: "trunk", branches: ["trunk"], hasMore: true))
    await #expect(throws: ControlError.remote(Refusal(code: "github.repoNotFound", params: ["repo": "AshuLab/nope"], text: "AshuLab/nope was not found, or your GitHub login cannot see it"))) { try await host.repoBranches("AshuLab/nope") }
}

@Test func repoBranchesGoesOnTheWireWithTheRepoAsAJSONStringAndOnlyForAHostThatListsIt() async throws {
    var wire = ""
    let server = TestServer { connection in
        connection.send(hello("\"repoBranches\""))
        guard let line = connection.readLine(), let id = (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])?["id"] as? Int else { return }
        wire = line
        connection.send("{\"id\":\(id),\"ok\":true,\"data\":{\"default\":\"main\",\"branches\":[\"main\"],\"hasMore\":false}}\n")
    }
    defer { server.stop() }
    _ = try await SocketChatHost(socketPath: { server.path }).repoBranches("AshuLab/carrier")
    let sent = try #require(try JSONSerialization.jsonObject(with: Data(wire.utf8)) as? [String: Any])
    #expect(sent["cmd"] as? String == "repoBranches" && sent["repo"] as? String == "AshuLab/carrier" && sent.keys.sorted() == ["cmd", "id", "repo"])

    var asked = false
    let older = TestServer { connection in
        connection.send(hello("\"plan\""))
        asked = connection.readRequestId() != nil
    }
    defer { older.stop() }
    await #expect(throws: ControlError.remote(.hostLacks("repoBranches"))) { _ = try await SocketChatHost(socketPath: { older.path }).repoBranches("AshuLab/carrier") }
    #expect(asked == false)
}

@Test func switchAgentSendsTheSessionAndTheAgentInsideJSONStringsAndDecodesTheGoldenReply() async throws {
    var line = ""
    let reply = try String(contentsOf: URL(fileURLWithPath: fixtures + "/chat-switch.json"), encoding: .utf8)
        .split(whereSeparator: \.isNewline).joined()
    let server = TestServer { connection in
        connection.send(hello("\"switchAgent\""))
        guard let read = connection.readLine(), let id = (try? JSONSerialization.jsonObject(with: Data(read.utf8)) as? [String: Any])?["id"] as? Int else { return }
        line = read
        connection.send("{\"id\":\(id),\"ok\":true,\"data\":\(reply)}\n")
    }
    defer { server.stop() }
    let session = "c3d4e5f6-2a1b-4c8d-9e0f-1a2b3c4d5e03"
    let switched = try await SocketChatHost(socketPath: { server.path }).switchAgent(session, to: "co\"dex")
    let sent = try #require(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
    #expect(sent["cmd"] as? String == "switchAgent" && sent["sessionId"] as? String == session && sent["agent"] as? String == "co\"dex")
    // the session as the host summarizes it has no `live`, and everything it says beyond what is read is ignored
    #expect(switched.session == AgentSwitch.Session(id: session, agent: "codex", harness: "codex", state: .idle))
    #expect(switched.options.map(\.id) == ["model", "sandbox"] && switched.options.map(\.current) == ["gpt-5", "read-only"])
}

@Test func switchAgentIsNotSentToAHostThatDoesNotListIt() async {
    var asked = false
    let server = TestServer { connection in
        connection.send(hello("\"agents\""))
        asked = connection.readRequestId() != nil
    }
    defer { server.stop() }
    await #expect(throws: ControlError.self) { try await SocketChatHost(socketPath: { server.path }).switchAgent("c3d4e5f6-2a1b-4c8d-9e0f-1a2b3c4d5e03", to: "codex") }
    #expect(asked == false)
}

@Test func anErrorThatIsAUsageLimitCarriesItsReasonAndWhenItResetsAndAnyOtherErrorNone() throws {
    let stamped = try JSONDecoder().decode(ChatEvent.self, from: Data(#"{"id":11,"at":1,"kind":"error","text":"You've hit your usage limit.","reason":"usage_limit","resetsAt":1795216260000}"#.utf8))
    #expect(stamped.reason == "usage_limit" && stamped.resetsAt == 1_795_216_260_000 && stamped.resetText == nil)
    let worded = try JSONDecoder().decode(ChatEvent.self, from: Data(#"{"id":12,"at":2,"kind":"error","text":"You've hit your usage limit.","reason":"usage_limit","resetText":"try again at Nov 20th, 2026 7:11 PM"}"#.utf8))
    #expect(worded.reason == "usage_limit" && worded.resetsAt == nil && worded.resetText == "try again at Nov 20th, 2026 7:11 PM")
    let plain = try JSONDecoder().decode(ChatEvent.self, from: Data(#"{"id":13,"at":3,"kind":"error","text":"The turn failed"}"#.utf8))
    #expect(plain.reason == nil && plain.resetsAt == nil && plain.resetText == nil)
}

@Test func aNoticeThatSaysTheAgentChangedCarriesBothAgentsAndAnyOtherNoticeNone() throws {
    let switched = try JSONDecoder().decode(ChatEvent.self, from: Data(#"{"id":9,"at":1,"kind":"notice","text":"The agent changed from claude to codex.","switched":{"from":"claude","to":"codex"}}"#.utf8))
    #expect(switched.switched == ChatEvent.Switched(from: "claude", to: "codex"))
    let lost = try JSONDecoder().decode(ChatEvent.self, from: Data(#"{"id":10,"at":2,"kind":"notice","text":"new conversation","lostNativeId":"x"}"#.utf8))
    #expect(lost.switched == nil)
    // the feed draws a change of agent as its own divider, and any other notice as the plain line it is
    #expect(chatFeed([switched], bundle: english.bundle, locale: english.locale) == [.switched(id: "e9", .init(from: "claude", to: "codex"))])
    #expect(chatFeed([lost], bundle: english.bundle, locale: english.locale) == [.line(id: "e10", text: "new conversation")])
}

private final class Asked: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func add(_ line: String) { lock.withLock { lines.append(line) } }
    var all: [String] { lock.withLock { lines } }
}

private let someCommands = #"[{"id":"review","name":"review","description":"Review","kind":"skill"}]"#
private let otherCommands = #"[{"id":"review","name":"review","description":"Review","kind":"skill"},{"id":"pdf","name":"pdf","description":"PDFs","kind":"skill"}]"#

private func eventsReply(_ id: Int, rev: String, lists: String) -> String {
    #"{"id":\#(id),"ok":true,"data":{"events":[],"cursor":0,"streaming":"","session":{"state":"idle"},"listsRev":"\#(rev)",\#(lists)}}"# + "\n"
}

@Test func theHostIsToldWhichListsTheClientHasAndALeftOutListIsTheOneKept() async throws {
    let asked = Asked()
    // the answers in the order of the requests: whole, left out, whole with another rev, left out
    let answers = [
        { (id: Int) in eventsReply(id, rev: "ab12", lists: #""options":[],"commands":\#(someCommands)"#) },
        { (id: Int) in eventsReply(id, rev: "ab12", lists: #""listsUnchanged":true"#) },
        { (id: Int) in eventsReply(id, rev: "cd34", lists: #""options":[],"commands":\#(otherCommands)"#) },
        { (id: Int) in eventsReply(id, rev: "cd34", lists: #""listsUnchanged":true"#) },
    ]
    let server = TestServer { connection in
        connection.send(hello(#""events","listsRev""#))
        guard let line = connection.readLine(), let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], let id = json["id"] as? Int else { return }
        asked.add(line)
        connection.send(answers[min(asked.all.count, answers.count) - 1](id))
    }
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.path })

    let first = try await host.events("0509fe2a-2637-4bdd-840c-5727696d6a3e", after: 0, limit: 50)
    #expect(first.commands.map(\.name) == ["review"])
    let second = try await host.events("0509fe2a-2637-4bdd-840c-5727696d6a3e", after: 0, limit: 50)
    #expect(second.commands.map(\.name) == ["review"] && second.listsUnchanged == false)
    let third = try await host.events("0509fe2a-2637-4bdd-840c-5727696d6a3e", after: 0, limit: 50)
    #expect(third.commands.map(\.name) == ["review", "pdf"])
    let fourth = try await host.events("0509fe2a-2637-4bdd-840c-5727696d6a3e", after: 0, limit: 50)
    #expect(fourth.commands.map(\.name) == ["review", "pdf"])

    // the first ask had none to name; each one after it named the rev of the last answer
    #expect(asked.all.map { $0.contains("\"lists\"") } == [false, true, true, true])
    #expect(asked.all[1].contains(#""lists":"ab12""#) && asked.all[2].contains(#""lists":"ab12""#) && asked.all[3].contains(#""lists":"cd34""#))
}

@Test func aHostThatDoesNotListTheRevisionIsNeverSentOneAndKeepsSendingTheListsWhole() async throws {
    let asked = Asked()
    let server = TestServer { connection in
        connection.send(hello(#""events""#))
        guard let line = connection.readLine(), let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], let id = json["id"] as? Int else { return }
        asked.add(line)
        connection.send(#"{"id":\#(id),"ok":true,"data":{"events":[],"cursor":0,"streaming":"","session":{"state":"idle"},"options":[],"commands":\#(someCommands)}}"# + "\n")
    }
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.path })

    for _ in 0..<2 { #expect(try await host.events("0509fe2a-2637-4bdd-840c-5727696d6a3e", after: 0, limit: 50).commands.map(\.name) == ["review"]) }
    #expect(asked.all.count == 2 && asked.all.allSatisfy { $0.contains("\"lists\"") == false })
}

@Test func aRevisionThatIsNotPlainHexIsNotKeptNorSentBack() async throws {
    let asked = Asked()
    let server = TestServer { connection in
        connection.send(hello(#""events","listsRev""#))
        guard let line = connection.readLine(), let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], let id = json["id"] as? Int else { return }
        asked.add(line)
        connection.send(eventsReply(id, rev: #"a\",\"cmd\":\"stop"#, lists: #""options":[],"commands":[]"#))
    }
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.path })

    for _ in 0..<2 { _ = try await host.events("0509fe2a-2637-4bdd-840c-5727696d6a3e", after: 0, limit: 50) }
    #expect(asked.all.allSatisfy { $0.contains("\"lists\"") == false && $0.contains("\"cmd\":\"stop\"") == false })
}

// MARK: the projects capability (docs/specs/projects.md, "What the host answers")

@Test func theFixtureHostListsItsClonesAndStartsSharesAndDismissesThem() async throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.chatSocketPath })
    #expect(try await host.capabilities().contains(.projects))
    // the golden reply: one clone running with git's progress line, one failed with its reason
    let listed = try await host.projectClones()
    #expect(listed == [
        ProjectClone(repo: "acme/docs", folder: "/tmp/carrier-projects/acme/docs", state: .cloning, progress: "Receiving objects: 62%"),
        ProjectClone(repo: "acme/private-tools", folder: "/tmp/carrier-projects/acme/private-tools", state: .failed, error: "acme/private-tools was not found, or your GitHub login cannot see it"),
    ])
    // a repository the person's listing has starts cloning in the projects folder, or in the parent chosen for it
    let started = try await host.cloneProject("vemec/encaja", into: nil)
    #expect(started.state == .cloning && started.folder.hasSuffix("/chat/projects/vemec/encaja"))
    // asking again, even for another folder, is the clone that runs
    #expect(try await host.cloneProject("Vemec/Encaja", into: "/tmp/elsewhere") == started)
    #expect(try await host.projectClones().count == 3)
    await #expect(throws: ControlError.remote(Refusal(code: "github.repoNotFound", params: ["repo": "AshuLab/nope"], text: "AshuLab/nope was not found, or your GitHub login cannot see it"))) { _ = try await host.cloneProject("AshuLab/nope", into: nil) }
    // a failed clone goes when it is dismissed, a running one stays
    #expect(try await host.dismissClone("acme/private-tools").map(\.repo) == ["acme/docs", "vemec/encaja"])
    #expect(try await host.dismissClone("acme/docs").count == 2)
}

@Test func theProjectsRequestsGoOnTheWireWithStringsEscapedAndOnlyForAHostThatListsThem() async throws {
    var wire: [String] = []
    let reply = #"{"repo":"acme/app","folder":"/w/acme/app","state":"cloning"}"#
    let server = TestServer { connection in
        connection.send(hello("\"projects\""))
        for _ in 0..<2 {
            guard let line = connection.readLine(), let id = (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])?["id"] as? Int else { return }
            wire.append(line)
            connection.send("{\"id\":\(id),\"ok\":true,\"data\":\(wire.count == 1 ? reply : #"{"clones":[]}"#)}\n")
        }
    }
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.path })
    _ = try await host.cloneProject("acme/app", into: "/w \"x\"")
    _ = try await host.dismissClone("acme/app")
    let sent = try #require(try JSONSerialization.jsonObject(with: Data(wire[0].utf8)) as? [String: Any])
    #expect(sent["cmd"] as? String == "cloneProject" && sent["repo"] as? String == "acme/app" && sent["parent"] as? String == "/w \"x\"" && sent.keys.sorted() == ["cmd", "id", "parent", "repo"])
    let dismissed = try #require(try JSONSerialization.jsonObject(with: Data(wire[1].utf8)) as? [String: Any])
    #expect(dismissed["cmd"] as? String == "dismissClone" && dismissed.keys.sorted() == ["cmd", "id", "repo"])

    // the host's own limits are checked before anything is sent
    await #expect(throws: ControlError.remote(Refusal(code: "project.repoInvalid", params: ["repo": "../x"], text: "\"../x\" is not a repository; write it as owner/name"))) { _ = try await host.cloneProject("../x", into: nil) }
    await #expect(throws: ControlError.remote(.folderUnusable)) { _ = try await host.cloneProject("acme/app", into: "") }

    // a host without the capability is told it is older, and is sent nothing
    var asked = false
    let older = TestServer { connection in
        connection.send(hello("\"plan\""))
        asked = connection.readRequestId() != nil
    }
    defer { older.stop() }
    let old = SocketChatHost(socketPath: { older.path })
    await #expect(throws: ControlError.remote(.projectsNeedNewerHost)) { _ = try await old.cloneProject("acme/app", into: nil) }
    await #expect(throws: ControlError.remote(.projectsNeedNewerHost)) { _ = try await old.projectClones() }
    #expect(asked == false)
    #expect(projectsNeedNewerHost.contains("older") && projectsNeedNewerHost.contains("Restart"))
}

@Test func theFixtureHostMakesANewProjectRegistersItWithOriginCreatedAndRefusesWhatTheHostRefuses() async throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.chatSocketPath })
    let made = try await host.newProject("my-app", into: nil)
    #expect(made == server.home + "/chat/projects/local/my-app")
    var isFolder: ObjCBool = false
    #expect(FileManager.default.fileExists(atPath: made, isDirectory: &isFolder) && isFolder.boolValue)
    let entry = try ProjectsFile(folder: server.home).read().first { $0.path == made }
    #expect(entry?.origin == "created")
    // a name whose folder is there is refused with the reason and nothing is written
    let before = try ProjectsFile(folder: server.home).read().count
    await #expect(throws: ControlError.remote(Refusal(code: "project.nameTaken", params: ["name": "my-app"], text: "my-app is already a project; choose another name"))) { _ = try await host.newProject("my-app", into: nil) }
    #expect(try ProjectsFile(folder: server.home).read().count == before)
    // the parent chosen for this one project
    let parent = server.home + "/elsewhere"
    #expect(try await host.newProject("other", into: parent) == parent + "/local/other")
    // what the host would refuse never goes out
    await #expect(throws: ControlError.remote(.projectNameBadCharacters)) { _ = try await host.newProject("a b", into: nil) }
    await #expect(throws: ControlError.remote(.folderUnusable)) { _ = try await host.newProject("x", into: "") }
}

@Test func theNewProjectRequestGoesOnTheWireAndTheGoldenReplyDecodes() async throws {
    let wire = Asked()
    let golden = try String(contentsOfFile: fixtures + "/chat-new-project.json", encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    let server = TestServer { connection in
        connection.send(hello("\"projects\""))
        guard let line = connection.readLine(), let id = (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])?["id"] as? Int else { return }
        wire.add(line)
        connection.send("{\"id\":\(id),\"ok\":true,\"data\":\(golden)}\n")
    }
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.path })
    let folder = try await host.newProject("my-app", into: "/w \"x\"")
    #expect(folder == "/Users/dev/.carrier/chat/projects/local/my-app")
    let sent = try #require(try JSONSerialization.jsonObject(with: Data(wire.all[0].utf8)) as? [String: Any])
    #expect(sent["cmd"] as? String == "newProject" && sent["name"] as? String == "my-app" && sent["parent"] as? String == "/w \"x\"" && sent.keys.sorted() == ["cmd", "id", "name", "parent"])

    // a host without the capability is told it is older, and is sent nothing
    var asked = false
    let older = TestServer { connection in
        connection.send(hello("\"plan\""))
        asked = connection.readRequestId() != nil
    }
    defer { older.stop() }
    await #expect(throws: ControlError.remote(.projectsNeedNewerHost)) { _ = try await SocketChatHost(socketPath: { older.path }).newProject("my-app", into: nil) }
    #expect(asked == false)
}

@Test func theProjectDiskRequestGoesOnTheWireWithTheHostsLimitsAndItsReplyDecodes() async throws {
    let wire = Asked()
    let server = TestServer { connection in
        connection.send(hello("\"projects\""))
        while let line = connection.readLine(), let id = (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])?["id"] as? Int {
            wire.add(line)
            connection.send("{\"id\":\(id),\"ok\":true,\"data\":{\"projects\":[{\"folder\":\"/w \\\"x\\\"\",\"bytes\":6420000000,\"measuredAt\":1792000000000,\"parts\":{\"/w \\\"x\\\"\":6420000000}},{\"folder\":\"/new\",\"bytes\":null,\"measuredAt\":null,\"parts\":{}}],\"measuring\":[\"/new\"]}}\n")
        }
    }
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.path })
    let reply = try await host.projectDisk(["/w \"x\"", "/new"], refresh: .stale)
    #expect(reply.projects == [.init(folder: "/w \"x\"", bytes: 6_420_000_000, measuredAt: 1_792_000_000_000, parts: ["/w \"x\"": 6_420_000_000]), .init(folder: "/new", bytes: nil)])
    #expect(reply.measuring == ["/new"])
    // a read sends no refresh; what the host would refuse (an empty folder, one over 4096 characters) never goes out, and with nothing left nothing is asked
    _ = try await host.projectDisk(["/a", "", String(repeating: "a", count: 4097)], refresh: .read)
    let none = try await host.projectDisk(["", String(repeating: "a", count: 4097)], refresh: .now)
    #expect(none == ProjectDiskReply(projects: []))
    let sent = try wire.all.map { try #require(try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]) }
    #expect(sent.count == 2)
    #expect(sent[0]["cmd"] as? String == "projectDisk" && sent[0]["folders"] as? [String] == ["/w \"x\"", "/new"] && sent[0]["refresh"] as? String == "stale" && sent[0].keys.sorted() == ["cmd", "folders", "id", "refresh"])
    #expect(sent[1]["folders"] as? [String] == ["/a"] && sent[1].keys.sorted() == ["cmd", "folders", "id"])

    // a host without the capability is told it is older, and is sent nothing
    var asked = false
    let older = TestServer { connection in
        connection.send(hello("\"plan\""))
        asked = connection.readRequestId() != nil
    }
    defer { older.stop() }
    await #expect(throws: ControlError.remote(.projectsNeedNewerHost)) { _ = try await SocketChatHost(socketPath: { older.path }).projectDisk(["/w"], refresh: .now) }
    #expect(asked == false)
}

@Test func theProjectWorktreesRequestGoesOnTheWireAndTheGoldenReplyDecodes() async throws {
    let wire = Asked()
    let golden = try String(contentsOfFile: fixtures + "/chat-project-worktrees.json", encoding: .utf8)
    let carrier = try #require(try JSONSerialization.jsonObject(with: Data(golden.utf8)) as? [String: Any])["carrier"] as Any
    let reply = String(decoding: try JSONSerialization.data(withJSONObject: carrier), as: UTF8.self)
    let server = TestServer { connection in
        connection.send(hello("\"projects\""))
        guard let line = connection.readLine(), let id = (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])?["id"] as? Int else { return }
        wire.add(line)
        connection.send("{\"id\":\(id),\"ok\":true,\"data\":\(reply)}\n")
    }
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.path })
    let listed = try await host.projectWorktrees("/w \"x\"")
    #expect(listed.main == .init(path: "/Users/dev/projects/carrier", branch: "main", state: .notPushed))
    #expect(listed.worktrees.map(\.state) == [.sessionOpen, .merged, .uncommitted, .notPushed, .clean])
    #expect(listed.worktrees[3].session == .init(id: "s-ahead") && listed.worktrees[4].session == nil)
    let sent = try #require(try JSONSerialization.jsonObject(with: Data(wire.all[0].utf8)) as? [String: Any])
    #expect(sent["cmd"] as? String == "projectWorktrees" && sent["folder"] as? String == "/w \"x\"" && sent.keys.sorted() == ["cmd", "folder", "id"])
    // what the host would refuse never goes out
    await #expect(throws: ControlError.remote(.folderUnusable)) { _ = try await host.projectWorktrees("") }

    // a host without the capability is told it is older, and is sent nothing
    var asked = false
    let older = TestServer { connection in
        connection.send(hello("\"plan\""))
        asked = connection.readRequestId() != nil
    }
    defer { older.stop() }
    await #expect(throws: ControlError.remote(.projectsNeedNewerHost)) { _ = try await SocketChatHost(socketPath: { older.path }).projectWorktrees("/w") }
    #expect(asked == false)
}

@Test func theRemoveAndCleanUpRequestsGoOnTheWireAndTheGoldenReplyDecodes() async throws {
    let wire = Asked()
    let golden = try String(contentsOfFile: fixtures + "/chat-project-cleanup.json", encoding: .utf8)
    let carrier = try #require(try JSONSerialization.jsonObject(with: Data(golden.utf8)) as? [String: Any])["carrier"] as Any
    let reply = String(decoding: try JSONSerialization.data(withJSONObject: carrier), as: UTF8.self)
    let server = TestServer { connection in
        connection.send(hello("\"projects\""))
        guard let line = connection.readLine(), let id = (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])?["id"] as? Int else { return }
        wire.add(line)
        let cmd = (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])?["cmd"] as? String
        connection.send(cmd == "removeProjectWorktree" ? "{\"id\":\(id),\"ok\":false,\"error\":\"It has uncommitted changes\"}\n" : "{\"id\":\(id),\"ok\":true,\"data\":\(reply)}\n")
    }
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.path })
    let preview = try await host.cleanProjectWorktrees("/p/app", run: false)
    #expect(cleanUpWords(preview) == "1 worktree, \(ByteCountFormatter.string(fromByteCount: 1_288_490_189, countStyle: .file))" && preview.skipped.map(\.reason) == ["It has uncommitted changes"])
    _ = try await host.cleanProjectWorktrees("/p/app", run: true)
    await #expect(throws: ControlError.remote(.words("It has uncommitted changes"))) { try await host.removeProjectWorktree("/p/app", path: "/w/a \"x\"") }
    // what the host would refuse never goes out
    await #expect(throws: ControlError.remote(.folderUnusable)) { try await host.removeProjectWorktree("/p/app", path: "") }
    await #expect(throws: ControlError.remote(.folderUnusable)) { _ = try await host.cleanProjectWorktrees("", run: true) }

    let sent = try wire.all.map { try #require(try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]) }
    #expect(sent.count == 3)
    #expect(sent[0].keys.sorted() == ["cmd", "folder", "id"] && sent[0]["cmd"] as? String == "cleanProjectWorktrees")
    #expect(sent[1].keys.sorted() == ["cmd", "folder", "id", "run"] && sent[1]["run"] as? Bool == true)
    #expect(sent[2].keys.sorted() == ["cmd", "folder", "id", "path"] && sent[2]["path"] as? String == "/w/a \"x\"" && sent[2]["cmd"] as? String == "removeProjectWorktree")

    // a host without the capability is told it is older, and is sent nothing
    var asked = false
    let older = TestServer { connection in
        connection.send(hello("\"plan\""))
        asked = connection.readRequestId() != nil
    }
    defer { older.stop() }
    let oldHost = SocketChatHost(socketPath: { older.path })
    await #expect(throws: ControlError.remote(.projectsNeedNewerHost)) { try await oldHost.removeProjectWorktree("/p/app", path: "/w") }
    await #expect(throws: ControlError.remote(.projectsNeedNewerHost)) { _ = try await oldHost.cleanProjectWorktrees("/p/app", run: false) }
    #expect(asked == false)
}

@Test func regenerateTitlesSendsOnlyWhileTheHelloListsItAndDecodesStartedOrRefusal() async throws {
    let asked = Asked()
    let server = TestServer { connection in
        connection.send(hello(#""regenerateTitles""#))
        guard let line = connection.readLine(), let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], let id = json["id"] as? Int else { return }
        asked.add(line)
        if asked.all.count == 1 {
            connection.send("{\"id\":\(id),\"ok\":true,\"data\":{\"started\":4}}\n")
        } else {
            connection.send("{\"id\":\(id),\"ok\":false,\"error\":\"Could not write titles: no text generator is chosen; choose one in Providers\"}\n")
        }
    }
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.path })
    #expect(try await host.regenerateTitles() == 4)
    await #expect(throws: ControlError.remote(.words("Could not write titles: no text generator is chosen; choose one in Providers"))) { _ = try await host.regenerateTitles() }
    let sent = try #require(try JSONSerialization.jsonObject(with: Data(asked.all[0].utf8)) as? [String: Any])
    #expect(sent["cmd"] as? String == "regenerateTitles" && sent.keys.sorted() == ["cmd", "id"])

    var askedOlder = false
    let older = TestServer { connection in
        connection.send(hello(#""textGenerators","regenerateTitle""#))
        askedOlder = connection.readRequestId() != nil
    }
    defer { older.stop() }
    await #expect(throws: ControlError.remote(.hostLacks("regenerateTitles"))) { _ = try await SocketChatHost(socketPath: { older.path }).regenerateTitles() }
    #expect(askedOlder == false)
}
