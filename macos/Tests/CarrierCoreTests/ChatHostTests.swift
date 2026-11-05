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

    let active = try await host.list(archived: false)
    #expect(active.map(\.state) == [.working, .waitingApproval, .idle, .idle])
    #expect(active.map(\.live) == [true, true, false, false])
    #expect(active.map { $0.workspace?.base } == [nil, nil, nil, "/Users/dev/work/web"])
    #expect(try await host.list(archived: true).map(\.archived) == [true, true])
}

@Test func theHelloCarriesTheChatCapabilities() throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let client = try #require(ControlClient.connect(path: server.chatSocketPath))
    #expect(try client.hello().capabilities == [.agents, .list, .open, .send, .events, .answer, .setOption, .archive, .delete, .deletePreview, .workspace, .fetch, .suggestName, .checkName, .cloneRepo, .createProject, .githubRepos, .repoBranches, .plan])
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
        (0, "carrier is older than this app. Run `brew upgrade carrier`."),
        (2, "This app is older than carrier. Run `brew upgrade --cask carrier`."),
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

@Test func theFixtureHostAnswersCloneRepoFromTheGoldenFileAndRefusesWhatItDoesNotList() async throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.chatSocketPath })
    #expect(try await host.capabilities().contains(.cloneRepo))
    #expect(try await host.cloneRepo("AshuLab/web") == ClonedRepo(folder: "/Users/dev/web", repo: "AshuLab/web", fetched: false))
    #expect(try await host.cloneRepo("AshuLab/carrier") == ClonedRepo(folder: "/Users/dev/carrier", repo: "AshuLab/carrier", fetched: true))
    await #expect(throws: ControlError.remote("AshuLab/nope was not found, or your GitHub login cannot see it")) { try await host.cloneRepo("AshuLab/nope") }
}

@Test func theFixtureHostAnswersCreateProjectFromTheGoldenFileAndRefusesAnotherName() async throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.chatSocketPath })
    #expect(try await host.capabilities().contains(.createProject))
    #expect(try await host.createProject("my-idea") == "/Users/dev/projects/local/my-idea")
    await #expect(throws: ControlError.remote("web is already a project; choose another name")) { try await host.createProject("web") }
}

@Test func aHostWithoutTheCreateProjectCapabilityIsNotAskedToCreate() async {
    var asked = false
    let server = TestServer { connection in
        connection.send(hello("\"agents\""))
        asked = connection.readRequestId() != nil
    }
    defer { server.stop() }
    await #expect(throws: ControlError.remote("the chat host does not support createProject")) { try await SocketChatHost(socketPath: { server.path }).createProject("x") }
    #expect(asked == false)
}

@Test func aHostWithoutTheCloneCapabilityIsNotAskedToClone() async {
    var asked = false
    let server = TestServer { connection in
        connection.send(hello("\"agents\""))
        asked = connection.readRequestId() != nil
    }
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.path })
    await #expect(throws: ControlError.remote("the chat host does not support cloneRepo")) { try await host.cloneRepo("AshuLab/carrier") }
    #expect(asked == false)
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
