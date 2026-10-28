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
    #expect(try client.hello().capabilities == [.agents, .list, .events, .setOption])
}

@Test func theFixtureHostAnswersAnythingElseWithAnError() throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let client = try #require(ControlClient.connect(path: server.chatSocketPath))
    _ = try client.hello()
    #expect(throws: ControlError.remote("unknown request")) { try client.request("open") }
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

private func observe(path: String, waits: Int) -> [ChatHostState] {
    var states: [ChatHostState] = []
    var count = 0
    ChatMonitor(socketPath: { path }, wait: { _ in count += 1; return count < waits }, log: { _ in }, onChange: { states.append($0) }).run()
    return states
}

@Test func theMonitorSaysStoppedForAMissingHostAndRunningWithItsAgentsForTheFixture() throws {
    #expect(observe(path: "/tmp/cc-missing-\(UUID().uuidString.prefix(8)).sock", waits: 2) == [.stopped, .stopped])

    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let states = observe(path: server.chatSocketPath, waits: 1)
    guard case .running(let agents)? = states.first else { Issue.record("not running: \(states)"); return }
    #expect(agents.filter(\.found).map(\.name) == ["claude", "codex"])
}

@Test func theStartRuleHasEachOfItsReasons() {
    let found = ChatAgent(name: "claude", harness: "claude", found: true)
    let missing = ChatAgent(name: "codex", harness: "codex", found: false)
    #expect(cannotStartReason(host: .stopped) == "The chat host is not running")
    #expect(cannotStartReason(host: .running(agents: [])) == "No agent found: install claude or codex")
    #expect(cannotStartReason(host: .running(agents: [missing])) == "No agent found: install claude or codex")
    #expect(cannotStartReason(host: .running(agents: [missing, found])) == nil)
    #expect(Sessions(cannotStartReason: nil).canStart)
    #expect(Sessions().canStart == false)
    #expect(Sessions().cannotStartReason == "The chat host is not running")
}
