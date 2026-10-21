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
