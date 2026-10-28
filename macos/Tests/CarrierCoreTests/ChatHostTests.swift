import Foundation
import Testing
@testable import CarrierCore

private let fixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures").path

private func hello(_ capabilities: String = "\"agents\",\"list\"") -> String {
    "{\"event\":\"hello\",\"protocol\":1,\"pid\":42,\"startedAt\":1000,\"version\":\"x\",\"capabilities\":[\(capabilities)]}\n"
}

@Test func theChatSocketIsUnderTheSharedRoot() {
    let environment = ["CARRIER_HOME": "/tmp/nowhere"]
    #expect(chatSocketPath(saved: nil, environment: environment, home: "/Users/x") == "/Users/x/.solve/chat/chat.sock")
    #expect(controlSocketPath(saved: nil, environment: environment, home: "/Users/x") == "/Users/x/.solve/orchestrator/control.sock")
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
    #expect(try client.hello().capabilities == [.agents, .list, .open, .send, .events, .answer, .setOption, .archive, .delete, .deletePreview, .workspace, .fetch, .suggestName, .checkName, .cloneRepo, .createProject])
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
