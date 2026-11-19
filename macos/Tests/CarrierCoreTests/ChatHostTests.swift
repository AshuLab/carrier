import Foundation
import Testing
@testable import CarrierCore

private let fixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures").path

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
    // the fifth is a session whose turn ended while a build runs; the eleven after it fill the sidebar's other states (unread, a single task, plain, pinned, a worktree preparing, a long title...), and the last is the one with three subagents
    #expect(active.map(\.state) == [.working, .waitingApproval, .idle, .idle, .idle, .idle, .idle, .working, .idle, .working, .idle, .preparing, .idle, .waitingApproval, .working, .idle, .idle])
    #expect(active.map(\.live) == [true, true, false, false, true, true, true, true, true, true, true, true, false, true, true, true, false])
    let worktree = "/Users/dev/work/web"
    #expect(active.map { $0.workspace?.base } == [nil, nil, nil, worktree, nil, nil, nil, nil, nil, worktree, worktree, worktree, nil, nil, nil, nil, nil])
    #expect(active.map(\.background.count) == [0, 0, 0, 0, 3, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
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
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.chatSocketPath })
    let active = try await host.list(archived: false)
    let nowMs = Int(Date().timeIntervalSince1970 * 1000)
    // "5 seconds ago" in the golden list, and the three tasks of the build session, started minutes before
    #expect(abs(nowMs - active[0].lastActiveAt - 5_000) < 10_000)
    #expect(active[4].background.allSatisfy { ($0.startedAt.map { Date().timeIntervalSince($0) } ?? 0) > 90 })
    #expect(server.unreadSessionIds == ["a1000000-0000-4000-8000-000000000001"] && server.pinnedSessionIds == ["a1000000-0000-4000-8000-000000000004"])
}

@Test func theHelloCarriesTheChatCapabilities() throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let client = try #require(ControlClient.connect(path: server.chatSocketPath))
    #expect(try client.hello().capabilities == [.agents, .list, .open, .resume, .send, .events, .answer, .setOption, .archive, .delete, .deletePreview, .workspace, .fetch, .suggestName, .checkName, .cloneRepo, .createProject, .githubRepos, .repoBranches, .providers, .plan, .usage, .usageOverride, .accountIdentity, .accountPalette, .switchAgent, .interrupt, .stopTask])
}

@Test func theFixtureHostAnswersAnythingElseWithAnError() throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let client = try #require(ControlClient.connect(path: server.chatSocketPath))
    _ = try client.hello()
    #expect(throws: ControlError.remote("unknown request")) { try client.request("resume") }
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
    await #expect(throws: ControlError.remote("internal error")) { try await SocketChatHost(socketPath: { server.path }).agents() }
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
    await #expect(throws: ControlError.remote("the chat host does not support list")) { try await SocketChatHost(socketPath: { server.path }).list(archived: false) }
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
        await #expect(throws: ControlError.remote(sentence)) { try await host.list(archived: false) }
        await #expect(throws: ControlError.remote(sentence)) { try await host.capabilities() }
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
    let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources")
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
    #expect(first.repos[5] == AvailableRepo(name: "vemec/dotfiles", isPrivate: false, pushedAt: nil))
    let second = try await host.githubRepos(page: 2)
    #expect(second.login == nil && second.hasMore == false && second.repos.map(\.name) == ["optyra/docs", "vemec/old-experiments"])
    await #expect(throws: ControlError.remote("GitHub did not answer; check \"gh auth status\"")) { try await host.githubRepos(page: 3) }
}

@Test func aHostWithoutTheGithubReposCapabilityIsNotAskedToList() async {
    var asked = false
    let server = TestServer { connection in
        connection.send(hello("\"agents\""))
        asked = connection.readRequestId() != nil
    }
    defer { server.stop() }
    await #expect(throws: ControlError.remote("the chat host does not support githubRepos")) { try await SocketChatHost(socketPath: { server.path }).githubRepos(page: 1) }
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
    await #expect(throws: ControlError.remote("the chat host does not support health")) { try await SocketChatHost(socketPath: { server.path }).health(refresh: false) }
    #expect(asked == false)
}

@Test @MainActor func theProvidersStoreHoldsTheReplyOfAHostThatListsProvidersAndSaysWhyOtherwise() async throws {
    let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures").path
    let fixture = try FixtureServer(fixtures: fixtures)
    defer { fixture.stop() }
    let store = ProvidersStore(host: SocketChatHost(socketPath: { fixture.chatSocketPath }), log: { _ in })
    #expect(store.outcome == .unasked)
    await store.load()
    guard case .reply(let reply) = store.outcome else { throw ControlError.closed }
    #expect(reply.accounts.map(\.name) == ["claude", "claude-work", "codex"] && reply.problem == nil)

    let old = TestServer { connection in connection.send(hello("\"agents\"")) }
    defer { old.stop() }
    let tooOld = ProvidersStore(host: SocketChatHost(socketPath: { old.path }), log: { _ in })
    await tooOld.load()
    #expect(tooOld.outcome == .tooOld)

    let absent = ProvidersStore(host: SocketChatHost(socketPath: { "/tmp/carrier-no-such-host.sock" }), log: { _ in })
    await absent.load()
    #expect(absent.outcome == .noHost)

    let failing = TestServer { connection in
        connection.send(hello("\"providers\""))
        guard let id = connection.readRequestId() else { return }
        connection.send("{\"id\":\(id),\"ok\":false,\"error\":\"internal error\"}\n")
    }
    defer { failing.stop() }
    let failed = ProvidersStore(host: SocketChatHost(socketPath: { failing.path }), log: { _ in })
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
        connection.send("{\"id\":\(id),\"ok\":true,\"data\":{\"plan\":{\"workspace\":{\"kind\":\"folder\",\"folder\":\"/w/api\"},\"agent\":\"claude\",\"text\":\"hi\\nthere\",\"options\":{\"model\":\"haiku\"},\"branch\":\"main\",\"worktree\":{\"name\":\"my-fix\"}}}}\n")
    }
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.path })
    let sessionId = "5d1f7c3a-0b6e-4a52-9a1d-3c7e8b2f4a01"
    try await host.retryPreparation(sessionId)
    let plan = try await host.cancelPreparation(sessionId)
    #expect(plan == SessionPlan(agent: "claude", folder: "/w/api", worktree: WorktreeRequest(from: "main", name: "my-fix"), options: ["model": "haiku"], text: "hi\nthere"))
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
    await #expect(throws: ControlError.remote("the chat host does not support cancelPreparation")) { _ = try await host.cancelPreparation("5d1f7c3a-0b6e-4a52-9a1d-3c7e8b2f4a01") }
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
    await #expect(throws: ControlError.remote("AshuLab/nope was not found, or your GitHub login cannot see it")) { try await host.repoBranches("AshuLab/nope") }
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
    await #expect(throws: ControlError.remote("the chat host does not support repoBranches")) { _ = try await SocketChatHost(socketPath: { older.path }).repoBranches("AshuLab/carrier") }
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
    // the feed shows it as the plain line it is
    #expect(chatFeed([switched]) == [.line(id: "e9", text: "The agent changed from claude to codex.")])
}
