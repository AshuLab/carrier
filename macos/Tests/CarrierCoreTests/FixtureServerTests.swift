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
    #expect(hello.capabilities == [.sessions, .events, .epic, .files, .fileDiff, .availableRepos, .availableReposPaged, .resumeEpic])
    let repo = ",\"repo\":\"AshuLab/web\",\"issue\":5"
    let id = ",\"executionId\":\"3f2b8c1e-5a4d-4e8b-9c1a-0d2e4f6a8b1c\""
    #expect(try sameJSON(client.request("snapshot"), golden("snapshot.json")))
    #expect(try sameJSON(client.request("sessions", fields: repo), golden("reply-sessions.json")))
    let sessions = try JSONDecoder().decode(SessionsReply.self, from: client.request("sessions", fields: repo))
    #expect(sessions.sessions.compactMap(\.failure?.kind) == ["killed"])
    #expect(try sameJSON(client.request("events", fields: id + ",\"limit\":50"), golden("reply-events.json")))
    #expect(try sameJSON(client.request("epic", fields: repo), golden("reply-epic.json")))
    #expect(try sameJSON(client.request("files", fields: repo), golden("reply-files.json")))
    let diff = try JSONSerialization.jsonObject(with: golden("reply-filediff.json")) as? [Any]
    let first = try JSONSerialization.data(withJSONObject: try #require(diff?.first))
    #expect(try sameJSON(client.request("fileDiff", fields: repo + ",\"section\":\"slice-121\",\"path\":\"src/a.ts\""), first))
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
    #expect(controlSocketPath(saved: nil, environment: ["CARRIER_HOME": server.home], home: "/nonexistent") == server.socketPath)
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
