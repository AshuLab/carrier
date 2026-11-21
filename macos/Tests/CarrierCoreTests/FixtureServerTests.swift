import Foundation
import Testing
@testable import CarrierCore

private let fixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures").path

private func golden(_ name: String) throws -> Data {
    try Data(contentsOf: URL(fileURLWithPath: fixtures + "/" + name))
}

/// Same JSON value, whatever the key order or spacing.
private func sameJSON(_ a: Data, _ b: Data) throws -> Bool {
    let (x, y) = (try JSONSerialization.jsonObject(with: a), try JSONSerialization.jsonObject(with: b))
    return (x as AnyObject).isEqual(y)
}

@Test func answersEachRequestFromItsGoldenFileOverARealSocket() throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let client = try #require(ControlClient.connect(path: server.socketPath))
    let hello = try client.hello()
    #expect(hello.capabilities == [.sessions, .events, .epic, .files, .fileDiff, .availableRepos, .availableReposPaged, .resumeEpic, .reload])
    let repo = ",\"repo\":\"AshuLab/web\",\"issue\":5"
    let id = ",\"executionId\":\"3f2b8c1e-5a4d-4e8b-9c1a-0d2e4f6a8b1c\""
    #expect(try sameJSON(client.request("snapshot"), golden("snapshot.json")))
    #expect(try sameJSON(client.request("sessions", fields: repo), golden("reply-sessions.json")))
    let sessions = try JSONDecoder().decode(SessionsReply.self, from: client.request("sessions", fields: repo))
    #expect(sessions.sessions.compactMap(\.failure?.kind) == ["usage_limit", "killed"])
    #expect(try sameJSON(client.request("events", fields: id + ",\"limit\":50"), golden("reply-events.json")))
    #expect(try sameJSON(client.request("epic", fields: repo), golden("reply-epic.json")))
    #expect(try sameJSON(client.request("files", fields: repo), golden("reply-files.json")))
    let diff = try JSONSerialization.jsonObject(with: golden("reply-filediff.json")) as? [Any]
    let first = try JSONSerialization.data(withJSONObject: try #require(diff?.first))
    #expect(try sameJSON(client.request("fileDiff", fields: repo + ",\"section\":\"slice-121\",\"path\":\"src/a.ts\""), first))
}

@Test func theFixtureChatHostAnswersProvidersFromItsGoldenFile() throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let client = try #require(ControlClient.connect(path: server.chatSocketPath))
    #expect(try client.hello().capabilities.contains(.providers))
    #expect(try sameJSON(client.request("providers"), golden("chat-providers.json")))
}

@Test func anAddInTheFixtureHomeTakesTheFoundNotAddedRowAway() throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let client = try #require(ControlClient.connect(path: server.chatSocketPath))
    _ = try client.hello()
    let file = ProvidersFile(folder: server.home)
    try file.write(applyingAccounts([(name: "agy", harness: "agy")], to: try file.read()))
    let reply = try JSONDecoder().decode(HostProviders.self, from: client.request("providers"))
    #expect(reply.unadded.isEmpty && reply.accounts.map(\.name) == ["claude", "claude-work", "codex", "agy"])
    #expect(reply.accounts.last?.harness == "agy" && reply.accounts.last?.found == true)
}

@Test func theFixtureChatHostAnswersUsageFromItsGoldenFile() throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let client = try #require(ControlClient.connect(path: server.chatSocketPath))
    let capabilities = try client.hello().capabilities
    #expect(capabilities.contains(.usage) && capabilities.contains(.usageOverride))
    #expect(try sameJSON(client.request("usage"), golden("chat-usage.json")))
    _ = try client.request("usageOverride", fields: ",\"model\":\"m\",\"action\":\"clear\"")
}

@Test func answersAnUnknownRequestWithAnError() throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let client = try #require(ControlClient.connect(path: server.socketPath))
    _ = try client.hello()
    #expect(throws: ControlError.remote("unknown request")) { try client.request("selfDestruct") }
    // the connection is still good afterwards
    #expect(try client.request("pause") == Data("null".utf8))
}

@Test func theMonitorShowsTheFixtureAsRunning() throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    var states: [ConnectionState] = []
    ControlMonitor(socketPath: { server.socketPath }, wait: { _ in false }, log: { _ in }, onChange: { states.append($0) }).run()
    let snapshot = try decodeSnapshot(golden("snapshot.json"))
    #expect(states == [.running(snapshot)])
    #expect(states[0].menuLine == "Carrier running · \(snapshot.epics.count) \(snapshot.epics.count == 1 ? "epic" : "epics") · \(snapshot.slots.busy)/\(snapshot.slots.total) slots")
}

@Test func pointingCarrierHomeAtTheFixtureFindsItsSocket() throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    #expect(controlSocketPath(environment: ["CARRIER_HOME": server.home], home: "/nonexistent") == server.socketPath)
}

@Test func stopRemovesTheSocketAndTheTemporaryHome() throws {
    let server = try FixtureServer(fixtures: fixtures)
    #expect(FileManager.default.fileExists(atPath: server.socketPath))
    server.stop()
    #expect(FileManager.default.fileExists(atPath: server.home) == false)
}

@Test func missingFixturesAreAnErrorAndLeaveNothingBehind() {
    #expect(throws: FixtureError.self) { try FixtureServer(fixtures: "/nonexistent") }
}

@Test func theFixtureChatHostSwitchesAnIdleSessionAndRefusesTheRestInWords() async throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.chatSocketPath })
    let sessions = try await host.list(archived: false)
    let idle = try #require(sessions.first { $0.state == .idle && $0.agent == "claude" })
    let working = try #require(sessions.first { $0.state == .working })

    let switched = try await host.switchAgent(idle.id, to: "codex")
    #expect(switched.session == AgentSwitch.Session(id: idle.id, agent: "codex", harness: "codex", state: .idle))
    #expect(try await host.list(archived: false).first { $0.id == idle.id }?.agent == "codex")
    let notice = try #require(try await host.events(idle.id, after: 0, limit: 200).events.last)
    #expect(notice.kind == "notice" && notice.switched == ChatEvent.Switched(from: "claude", to: "codex"))

    await #expect(throws: ControlError.remote("This session already has the agent \"codex\"")) { try await host.switchAgent(idle.id, to: "codex") }
    await #expect(throws: ControlError.remote("There is no chat agent named \"ghost\"")) { try await host.switchAgent(idle.id, to: "ghost") }
    await #expect(throws: ControlError.remote("The agent \"claude-beta\" is not found on this machine")) { try await host.switchAgent(idle.id, to: "claude-beta") }
    await #expect(throws: ControlError.remote("This session is working; interrupt it or wait, then switch its agent")) { try await host.switchAgent(working.id, to: "codex") }
}

@Test func theFixtureHomeCarriesProjectsThatTheListShowsWithTheirRemotes() throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let rows = projectRows(try ProjectsFile(folder: server.home).read())
    #expect(rows.count == 4)
    #expect(rows.first?.line == "AshuLab/carrier")
    #expect(rows[1].name.count > 60 && rows[1].repo?.hasSuffix("/" + rows[1].path.split(separator: "/").last!) == true)
    // a folder that is not a repository shows its path, and so does one that is not there
    #expect(rows[2].line == rows[2].path && rows[3].line == "/Users/demo/gone")
}
