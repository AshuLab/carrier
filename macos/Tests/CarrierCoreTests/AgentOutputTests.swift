import Foundation
import Testing
@testable import CarrierCore

private let executionId = "3f2b8c1e-9a4d-4e57-8b1a-0c6d2f7e5a11"

/// Answers each request with the next scripted result and counts them; a closed connection once the script runs out.
private final class FakeClient: TailClient {
    var script: [Result<[String], ControlError>]
    var asked: [(id: String, lines: Int)] = []
    var closed = false

    init(_ script: [Result<[String], ControlError>]) { self.script = script }

    func tail(executionId: String, lines: Int) throws -> [String] {
        asked.append((executionId, lines))
        guard script.isEmpty == false else { throw ControlError.closed }
        return try script.removeFirst().get()
    }

    func close() { closed = true }
}

/// Runs a watcher to its end with a clock that never sleeps: `wait` records the interval and says stop after `waits` of them.
private func watch(_ client: FakeClient?, waits: Int) -> (updates: [OutputUpdate], intervals: [TimeInterval]) {
    var updates: [OutputUpdate] = []
    var intervals: [TimeInterval] = []
    OutputWatcher(
        executionId: executionId,
        connect: { client },
        wait: { intervals.append($0); return intervals.count < waits },
        log: { _ in },
        onUpdate: { updates.append($0) }
    ).run()
    return (updates, intervals)
}

@Test func theFirstRequestIsOnOpenThenOneEveryTwoSecondsForTheLast60Lines() {
    let client = FakeClient([.success(["a"]), .success(["a", "b"]), .success(["a", "b", "c"])])
    let seen = watch(client, waits: 3)
    #expect(seen.updates == [.lines(["a"]), .lines(["a", "b"]), .lines(["a", "b", "c"])])
    #expect(seen.intervals == [2, 2, 2])
    #expect(client.asked.count == 3)
    #expect(client.asked.allSatisfy { $0.id == executionId && $0.lines == 60 })
}

@Test func closingTheViewStopsTheRequests() {
    let client = FakeClient([.success(["a"]), .success(["b"]), .success(["c"])])
    let seen = watch(client, waits: 1)  // the first wait says the view closed
    #expect(client.asked.count == 1)
    #expect(seen.updates == [.lines(["a"])])
    #expect(client.closed)
}

@Test func anExecutionWithNoOutputYetIsEmptyLinesNotAnError() {
    #expect(watch(FakeClient([.success([])]), waits: 1).updates == [.lines([])])
}

@Test func anErrorReplyIsReportedAndTheNextRequestIsStillMade() {
    let client = FakeClient([.failure(.remote("invalid request")), .success(["a"])])
    let seen = watch(client, waits: 2)
    #expect(seen.updates == [.error("invalid request"), .lines(["a"])])
    #expect(client.asked.count == 2)
}

@Test func aTimeoutIsReportedAndAskingContinues() {
    let client = FakeClient([.failure(.timeout), .success(["a"])])
    #expect(watch(client, waits: 2).updates == [.error("Carrier did not answer"), .lines(["a"])])
}

@Test func whenTheConnectionIsLostItSaysSoAndNeverAsksAgain() {
    let client = FakeClient([.success(["a"])])  // the second request finds it closed
    let seen = watch(client, waits: 10)
    #expect(seen.updates == [.lines(["a"]), .carrierStopped])
    #expect(seen.intervals == [2])
    #expect(client.asked.count == 2)
    #expect(client.closed)
}

@Test func noCarrierIsStoppedWithoutAnyRequest() {
    let seen = watch(nil, waits: 10)
    #expect(seen.updates == [.carrierStopped])
    #expect(seen.intervals.isEmpty)
}

// The real client, against a fake Carrier on a real socket.

private let hello = "{\"event\":\"hello\",\"protocol\":1,\"pid\":42,\"startedAt\":1000}\n"

@Test func tailSendsTheExecutionIdAndLinesAndReadsTheArrayOfStrings() throws {
    var request: [String: Any] = [:]
    let server = TestServer { connection in
        connection.send(hello)
        guard let line = connection.readLine() else { return }
        request = (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]) ?? [:]
        connection.send("{\"id\":1,\"ok\":true,\"data\":[\"first\",\"second\"]}\n")
    }
    defer { server.stop() }
    let client = try #require(connectForTail(socketPath: server.path))
    defer { client.close() }
    #expect(try client.tail(executionId: executionId.uppercased(), lines: 60) == ["first", "second"])
    #expect(request["cmd"] as? String == "tail")
    #expect(request["executionId"] as? String == executionId)
    #expect(request["lines"] as? Int == 60)
}

@Test func tailThrowsTheSocketsErrorText() throws {
    let server = TestServer { connection in
        connection.send(hello)
        _ = connection.readRequestId()
        connection.send("{\"id\":1,\"ok\":false,\"error\":\"invalid request\"}\n")
    }
    defer { server.stop() }
    let client = try #require(connectForTail(socketPath: server.path))
    defer { client.close() }
    #expect(throws: ControlError.remote("invalid request")) { try client.tail(executionId: executionId, lines: 60) }
}

@Test func tailRefusesAnIdThatIsNotAUUIDWithoutSendingIt() throws {
    var received = 0
    let server = TestServer { connection in
        connection.send(hello)
        while connection.readLine() != nil { received += 1 }
    }
    defer { server.stop() }
    let client = try #require(connectForTail(socketPath: server.path))
    for bad in ["exec-ship-30", "", "\",\"cmd\":\"stop\",\"x\":\"", "../../etc"] {
        #expect(throws: ControlError.remote("not a valid execution id")) { try client.tail(executionId: bad, lines: 60) }
    }
    client.close()
    #expect(received == 0)
}

@Test func noCarrierMeansNoTailClient() {
    #expect(connectForTail(socketPath: "/tmp/cc-missing-\(UUID().uuidString.prefix(8)).sock") == nil)
}
