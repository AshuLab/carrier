import Foundation
import Testing
@testable import CarrierCore

private let hello = "{\"event\":\"hello\",\"protocol\":1,\"pid\":42,\"startedAt\":1000}\n"

private func reply(_ id: Int, data: String = "{\"n\":\(7)}") -> String { "{\"id\":\(id),\"ok\":true,\"data\":\(data)}\n" }

private func object(_ data: Data) -> [String: Any]? { try? JSONSerialization.jsonObject(with: data) as? [String: Any] }

@Test func readsTheHelloAndMatchesEachReplyToItsRequestWithIncreasingIds() throws {
    var ids: [Int] = []
    let server = TestServer { connection in
        connection.send(hello)
        while let id = connection.readRequestId() {
            ids.append(id)
            connection.send(reply(id, data: "{\"n\":\(id)}"))
        }
    }
    defer { server.stop() }

    let client = try #require(ControlClient.connect(path: server.path))
    #expect(try client.hello().protocolVersion == 1)
    #expect(object(try client.request("snapshot"))?["n"] as? Int == 1)
    #expect(object(try client.request("snapshot"))?["n"] as? Int == 2)
    client.close()
}

@Test func aReplySplitAcrossChunksIsOneReply() throws {
    let server = TestServer { connection in
        connection.send(hello)
        guard let id = connection.readRequestId() else { return }
        let text = reply(id)
        let middle = text.index(text.startIndex, offsetBy: text.count / 2)
        connection.send(String(text[..<middle]))
        usleep(50_000)
        connection.send(String(text[middle...]))
    }
    defer { server.stop() }

    let client = try #require(ControlClient.connect(path: server.path))
    _ = try client.hello()
    #expect(object(try client.request("snapshot"))?["n"] as? Int == 7)
}

@Test func severalLinesInOneChunkAreReadInOrderAndAStaleReplyIsSkipped() throws {
    let server = TestServer { connection in
        connection.send(hello + reply(1, data: "{\"n\":1}"))
        _ = connection.readRequestId()
        _ = connection.readRequestId()
        connection.send(reply(1, data: "{\"n\":99}") + reply(2, data: "{\"n\":2}"))
    }
    defer { server.stop() }

    let client = try #require(ControlClient.connect(path: server.path))
    #expect(try client.hello().protocolVersion == 1)
    #expect(object(try client.request("snapshot"))?["n"] as? Int == 1)
    #expect(object(try client.request("snapshot"))?["n"] as? Int == 2)
}

@Test func anErrorReplyThrowsItsMessage() throws {
    let server = TestServer { connection in
        connection.send(hello)
        guard let id = connection.readRequestId() else { return }
        connection.send("{\"id\":\(id),\"ok\":false,\"error\":\"internal error\"}\n")
        _ = connection.readRequestId()
        connection.send("{\"id\":null,\"ok\":false,\"error\":\"invalid request\"}\n")
    }
    defer { server.stop() }

    let client = try #require(ControlClient.connect(path: server.path))
    _ = try client.hello()
    #expect(throws: ControlError.remote("internal error")) { try client.request("snapshot") }
    #expect(throws: ControlError.remote("invalid request")) { try client.request("snapshot") }
}

@Test func aConnectionThatClosesMidRequestThrowsClosed() throws {
    let server = TestServer { connection in
        connection.send(hello)
        _ = connection.readRequestId()
        connection.send("{\"id\":1,\"ok\":tr") // half a reply, then gone
    }
    defer { server.stop() }

    let client = try #require(ControlClient.connect(path: server.path))
    _ = try client.hello()
    #expect(throws: ControlError.closed) { try client.request("snapshot") }
}

@Test func aServerThatStopsAnsweringTimesOut() throws {
    let server = TestServer { connection in
        connection.send(hello)
        _ = connection.readRequestId()
        sleep(1)
    }
    defer { server.stop() }

    let client = try #require(ControlClient.connect(path: server.path, timeout: 0.2))
    _ = try client.hello()
    #expect(throws: ControlError.timeout) { try client.request("snapshot") }
}

@Test func noSocketMeansNoClient() throws {
    #expect(ControlClient.connect(path: "/tmp/cc-missing-\(UUID().uuidString.prefix(8)).sock") == nil)
}

@Test func aSocketFileNobodyListensOnMeansNoClient() throws {
    let path = "/tmp/cc-stale-\(UUID().uuidString.prefix(8)).sock"
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path.utf8) }
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    _ = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    close(fd) // the file stays, nothing listens: what a crashed Carrier leaves behind
    defer { unlink(path) }
    #expect(FileManager.default.fileExists(atPath: path))

    #expect(ControlClient.connect(path: path) == nil)
}

@Test func aPathThatDoesNotFitMeansNoClient() throws {
    let fits = "/tmp/" + String(repeating: "a", count: 103 - 5)
    let tooLong = fits + "a"
    #expect(fits.utf8.count == 103 && tooLong.utf8.count == 104)
    #expect(ControlClient.connect(path: fits) == nil) // fits, there is just nothing there
    #expect(ControlClient.connect(path: tooLong) == nil) // must come back, not crash
    #expect(ControlClient.connect(path: "/tmp/" + String(repeating: "a", count: 5000)) == nil)
}

@Test func aLowerAnEqualAndAHigherProtocolAreToldApart() throws {
    for (version, sentence) in [(0, "carrier is older than this app. Run brew upgrade carrier in Terminal, then restart Carrier."), (1, nil), (2, "This app is older than carrier. It updates itself; if it has not, run brew upgrade --cask carrier in Terminal, then open the app again.")] as [(Int, String?)] {
        var asked = false
        let server = TestServer { connection in
            connection.send("{\"event\":\"hello\",\"protocol\":\(version),\"pid\":42,\"startedAt\":1000}\n")
            asked = connection.readRequestId() != nil
        }
        defer { server.stop() }
        let client = try #require(ControlClient.connect(path: server.path))
        defer { client.close() }
        if let sentence {
            #expect(throws: ControlError.remote(sentence)) { try client.supportedHello() }
        } else {
            #expect(try client.supportedHello().protocolVersion == 1)
            _ = try? client.request("snapshot", fields: "")
        }
        client.close()
        #expect(asked == (sentence == nil))
    }
}

@Test func aHelloWithVersionAndCapabilitiesIsDecodedAndUnknownCapabilitiesAreDropped() throws {
    let newer = "{\"event\":\"hello\",\"protocol\":1,\"pid\":42,\"startedAt\":1000,\"version\":\"0.2.0\",\"capabilities\":[\"events\",\"files\",\"telepathy\"]}\n"
    let server = TestServer { $0.send(newer) }
    defer { server.stop() }

    let client = try #require(ControlClient.connect(path: server.path))
    let decoded = try client.hello()
    #expect(decoded.version == "0.2.0")
    #expect(decoded.capabilities == [.events, .files])
    #expect(client.capabilities == [.events, .files])
}

@Test func aHelloWithoutThemIsAnEngineWithNoCapabilities() throws {
    let server = TestServer { $0.send(hello) }
    defer { server.stop() }

    let client = try #require(ControlClient.connect(path: server.path))
    let decoded = try client.hello()
    #expect(decoded.protocolVersion == 1)
    #expect(decoded.version == nil)
    #expect(decoded.capabilities.isEmpty)
}

@Test func aRequestThatNeedsACapabilityIsNotSentWithoutIt() throws {
    let withEvents = "{\"event\":\"hello\",\"protocol\":1,\"pid\":42,\"startedAt\":1000,\"version\":\"0.2.0\",\"capabilities\":[\"events\"]}\n"
    let server = TestServer { connection in
        connection.send(withEvents)
        // each reply carries how many requests this connection has sent so far
        var seen = 0
        while let id = connection.readRequestId() {
            seen += 1
            connection.send(reply(id, data: "{\"n\":\(seen)}"))
        }
    }
    defer { server.stop() }

    let client = try #require(ControlClient.connect(path: server.path))
    _ = try client.hello()
    #expect(try client.request("sessions", requires: .sessions) == nil)
    #expect(object(try client.request("snapshot"))?["n"] as? Int == 1)
}

@Test func aRequestThatNeedsACapabilityIsSentWithIt() throws {
    let withEvents = "{\"event\":\"hello\",\"protocol\":1,\"pid\":42,\"startedAt\":1000,\"version\":\"0.2.0\",\"capabilities\":[\"events\"]}\n"
    let server = TestServer { connection in
        connection.send(withEvents)
        while let id = connection.readRequestId() { connection.send(reply(id)) }
    }
    defer { server.stop() }

    let client = try #require(ControlClient.connect(path: server.path))
    _ = try client.hello()
    #expect(object(try #require(try client.request("events", requires: .events)))?["n"] as? Int == 7)
}

private struct Count: Decodable, Equatable { let n: Int }

@Test func aLongReplyIsSearchedForItsEndOnceNotAtEveryRead() throws {
    // 600 KB: many reads of 32 KB, and a search that starts over at each of them goes over the first bytes again and again
    let filler = String(repeating: "x", count: 600_000)
    let server = TestServer { connection in
        connection.send(hello)
        guard let id = connection.readRequestId() else { return }
        let text = reply(id, data: "{\"n\":5,\"filler\":\"\(filler)\"}")
        var rest = Substring(text)
        while rest.isEmpty == false {
            connection.send(String(rest.prefix(20_000)))
            rest = rest.dropFirst(20_000)
            usleep(1_000)
        }
    }
    defer { server.stop() }

    let client = try #require(ControlClient.connect(path: server.path))
    _ = try client.hello()
    let before = client.bytesScanned
    #expect(try client.request("snapshot").count > 600_000)
    #expect(client.bytesScanned - before <= 600_100)
}

@Test func aReplyDecodedIntoItsTypeIsParsedOnceAndAStaleOrFailedOneTakesTheLongWay() throws {
    let server = TestServer { connection in
        connection.send(hello)
        // the first request is answered whole; the second after a stale reply of another shape; the third with an error
        if let id = connection.readRequestId() { connection.send(reply(id, data: "{\"n\":1}")) }
        if let id = connection.readRequestId() { connection.send(reply(1, data: "[\"late\"]") + reply(id, data: "{\"n\":2}")) }
        if let id = connection.readRequestId() { connection.send("{\"id\":\(id),\"ok\":false,\"error\":\"nope\"}\n") }
    }
    defer { server.stop() }

    let client = try #require(ControlClient.connect(path: server.path))
    _ = try client.supportedHello()
    client.capabilities = [.events]
    #expect(try client.request("events", requires: .events, as: Count.self) == Count(n: 1))
    #expect(client.repliesParsedOnce == 1)
    #expect(try client.request("events", requires: .events, as: Count.self) == Count(n: 2))
    #expect(client.repliesParsedOnce == 2)
    #expect(throws: ControlError.remote("nope")) { try client.request("events", requires: .events, as: Count.self) }
    #expect(client.repliesParsedOnce == 2)
}

@Test func aStaleReplyOfTheSameShapeIsNotTheAnswerToTheCurrentRequest() throws {
    let server = TestServer { connection in
        connection.send(hello)
        guard let id = connection.readRequestId() else { return }
        connection.send(reply(id - 1, data: "{\"n\":99}") + reply(id, data: "{\"n\":1}"))
    }
    defer { server.stop() }

    let client = try #require(ControlClient.connect(path: server.path))
    _ = try client.hello()
    #expect(try client.request("events", as: Count.self) == Count(n: 1))
    #expect(client.repliesParsedOnce == 1)
}

@Test func aReplyOfTheWrongShapeIsABadLineAndAnUnlistedRequestSendsNothing() throws {
    let server = TestServer { connection in
        connection.send(hello)
        guard let id = connection.readRequestId() else { return }
        connection.send(reply(id, data: "[1,2]"))
    }
    defer { server.stop() }

    let client = try #require(ControlClient.connect(path: server.path))
    _ = try client.hello()
    #expect(try client.request("events", requires: .events, as: Count.self) == nil)
    client.capabilities = [.events]
    #expect(throws: ControlError.badLine) { try client.request("events", requires: .events, as: Count.self) }
}

private let snapshotFixture = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/snapshot.json")

@Test func aSnapshotIsParsedOnceAndAWrongOneStillNamesItsField() throws {
    let good = try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: Data(contentsOf: snapshotFixture)))
    var broken = try #require(JSONSerialization.jsonObject(with: good) as? [String: Any])
    broken["slots"] = nil
    let wrong = try JSONSerialization.data(withJSONObject: broken)
    let server = TestServer { connection in
        connection.send(hello)
        for body in [good, wrong] {
            guard let id = connection.readRequestId() else { return }
            connection.send(reply(id, data: String(decoding: body, as: UTF8.self)))
        }
    }
    defer { server.stop() }

    let client = try #require(ControlClient.connect(path: server.path))
    _ = try client.hello()
    #expect(try client.snapshot() == decodeSnapshot(good))
    #expect(client.repliesParsedOnce == 1)
    #expect(throws: SnapshotError.missingField("slots")) { try client.snapshot() }
}
