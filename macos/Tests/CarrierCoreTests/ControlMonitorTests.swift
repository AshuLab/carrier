import Foundation
import Testing
@testable import CarrierCore

private let fixtureURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/snapshot.json")

private func fixture() throws -> Data {
    let json = try JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL))
    return try JSONSerialization.data(withJSONObject: json)
}

private func hello(protocol version: Int = 1) -> String { "{\"event\":\"hello\",\"protocol\":\(version),\"pid\":42,\"startedAt\":1000}\n" }

/// Runs a monitor to its end and returns what it reported and the intervals it waited. `wait` never sleeps: it records
/// the interval and says stop once `waits` of them have gone by.
private func observe(path: String, waits: Int) -> (states: [ConnectionState], intervals: [TimeInterval]) {
    var states: [ConnectionState] = []
    var intervals: [TimeInterval] = []
    ControlMonitor(
        socketPath: path, pollInterval: 1, retryInterval: 3,
        wait: { intervals.append($0); return intervals.count < waits },
        log: { _ in },
        onChange: { states.append($0) }
    ).run()
    return (states, intervals)
}

@Test func aMissingSocketIsStoppedAndRetriedEveryThreeSeconds() {
    let seen = observe(path: "/tmp/cc-missing-\(UUID().uuidString.prefix(8)).sock", waits: 3)
    #expect(seen.states == [.stopped, .stopped, .stopped])
    #expect(seen.intervals == [3, 3, 3])
}

@Test func aPathThatDoesNotFitIsStoppedNotACrash() {
    let seen = observe(path: "/tmp/" + String(repeating: "a", count: 200), waits: 1)
    #expect(seen.states == [.stopped])
}

@Test func aProtocolOtherThanOneIsIncompatible() {
    let server = TestServer { $0.send(hello(protocol: 2)) }
    defer { server.stop() }
    let seen = observe(path: server.path, waits: 1)
    #expect(seen.states == [.incompatible])
    #expect(seen.intervals == [3])
}

@Test func aSnapshotThatDoesNotDecodeIsIncompatible() {
    let server = TestServer { connection in
        connection.send(hello())
        guard let id = connection.readRequestId() else { return }
        connection.send("{\"id\":\(id),\"ok\":true,\"data\":{\"now\":1}}\n")
    }
    defer { server.stop() }
    #expect(observe(path: server.path, waits: 1).states == [.incompatible])
}

@Test func connectedItAsksEverySecondAndWhenTheConnectionClosesItIsStoppedAndRetriesEveryThree() throws {
    let snapshot = String(decoding: try fixture(), as: UTF8.self)
    let server = TestServer { connection in
        connection.send(hello())
        for _ in 1...2 {
            guard let id = connection.readRequestId() else { return }
            connection.send("{\"id\":\(id),\"ok\":true,\"data\":\(snapshot)}\n")
        }
        // the third request finds the connection closed
    }
    defer { server.stop() }

    // waits: 1 after the first snapshot, 1 after the second, then the closed connection: 3
    let seen = observe(path: server.path, waits: 3)
    let expected = try decodeSnapshot(fixture())
    #expect(seen.states == [.running(expected), .running(expected), .stopped])
    #expect(seen.intervals == [1, 1, 3])
}

@Test func theMenuLineSaysWhatCarrierIsDoing() throws {
    let snapshot = try decodeSnapshot(fixture())
    #expect(ConnectionState.stopped.menuLine == "Carrier is stopped")
    #expect(ConnectionState.incompatible.menuLine == "Carrier is an incompatible version")
    #expect(ConnectionState.running(snapshot).menuLine == "Carrier running · \(snapshot.epics.count) epics · 2/3 slots")
}

@Test func theTickRunsAfterEachSnapshotOnTheSameConnection() throws {
    let snapshot = String(decoding: try fixture(), as: UTF8.self)
    let server = TestServer { connection in
        connection.send(hello())
        for _ in 1...2 {
            guard let id = connection.readRequestId() else { return }
            connection.send("{\"id\":\(id),\"ok\":true,\"data\":\(snapshot)}\n")
        }
    }
    defer { server.stop() }
    var log: [String] = []
    var waits = 0
    ControlMonitor(
        socketPath: server.path, wait: { _ in waits += 1; return waits < 2 }, log: { _ in },
        tick: { _ in log.append("tick") }, onChange: { _ in log.append("snapshot") }
    ).run()
    #expect(log == ["snapshot", "tick", "snapshot", "tick"])
}
