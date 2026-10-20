import Foundation
import Testing
@testable import CarrierCore

private let fixtureURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/snapshot.json")

/// The fixture (two running epics, one needing a person, two queued) with `change` applied.
private func snapshot(_ change: (inout PanelSnapshot) -> Void = { _ in }) throws -> PanelSnapshot {
    var snapshot = try decodeSnapshot(Data(contentsOf: fixtureURL))
    change(&snapshot)
    return snapshot
}

@Test func stoppingAsksWhenEpicsAreRunningAndCountsThem() throws {
    let s = try snapshot()
    #expect(s.stopNeedsConfirmation)
    #expect(s.runningEpics == 2)
}

@Test func stoppingDoesNotAskWhenEpicsOnlyNeedAPerson() throws {
    let s = try snapshot { $0.epics = $0.epics.filter { $0.status == .needsHuman } }
    #expect(s.epics.count == 1)
    #expect(s.stopNeedsConfirmation == false)
}

@Test func stoppingDoesNotAskWithOnlyAQueue() throws {
    let s = try snapshot { $0.epics = [] }
    #expect(s.queue.isEmpty == false)
    #expect(s.stopNeedsConfirmation == false)
}

@Test func stoppingDoesNotAskWithAnEmptySnapshot() throws {
    let s = try snapshot { $0.epics = []; $0.queue = [] }
    #expect(s.stopNeedsConfirmation == false)
}

private let hello = "{\"event\":\"hello\",\"protocol\":1,\"pid\":42,\"startedAt\":1000}\n"

@Test func sendsEachCommandByNameAndWaitsForItsReply() throws {
    var received: [String] = []
    let server = TestServer { connection in
        connection.send(hello)
        while let line = connection.readLine() {
            let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            received.append(json?["cmd"] as? String ?? "?")
            connection.send("{\"id\":1,\"ok\":true}\n")
        }
    }
    defer { server.stop() }
    for command in [Command.pause, .resume, .checkNow, .stop] { try send(command, socketPath: server.path) }
    #expect(received == ["pause", "resume", "checkNow", "stop"])
}

@Test func stopIsOkWhenTheConnectionClosesRightAfterTheReply() throws {
    let server = TestServer { connection in
        connection.send(hello)
        _ = connection.readRequestId()
        connection.send("{\"id\":1,\"ok\":true}\n")
    }
    defer { server.stop() }
    try send(.stop, socketPath: server.path)
}

@Test func aRefusedCommandThrowsTheRemoteError() {
    let server = TestServer { connection in
        connection.send(hello)
        _ = connection.readRequestId()
        connection.send("{\"id\":1,\"ok\":false,\"error\":\"internal error\"}\n")
    }
    defer { server.stop() }
    #expect(throws: ControlError.remote("internal error")) { try send(.pause, socketPath: server.path) }
}

@Test func noCarrierIsAClosedConnectionNotACrash() {
    #expect(throws: ControlError.closed) { try send(.pause, socketPath: "/tmp/cc-missing-\(UUID().uuidString.prefix(8)).sock") }
}
