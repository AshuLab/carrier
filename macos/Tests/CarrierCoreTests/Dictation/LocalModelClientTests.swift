import Foundation
import Testing
@testable import CarrierCore

/// A model server's stub on a real socket: HTTP over the loopback on a port the system picks. `reply` gets the method, the path and the body of each
/// request and answers with a status and a body, or nil to say nothing and keep the connection open.
private final class StubServer: @unchecked Sendable {
    let port: UInt16
    private let listener: Int32
    private let lock = NSLock()
    private var stopped = false
    private var seen: [(method: String, path: String, body: Data)] = []

    var requests: [(method: String, path: String, body: Data)] { lock.lock(); defer { lock.unlock() }; return seen }
    var url: URL { URL(string: "http://127.0.0.1:\(port)")! }

    init(reply: @escaping @Sendable (_ method: String, _ path: String, _ body: Data) -> (status: Int, body: String)?) {
        signal(SIGPIPE, SIG_IGN)
        let listener = socket(AF_INET, SOCK_STREAM, 0)
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        _ = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        listen(listener, 4)
        var bound = sockaddr_in()
        var size = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &bound) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(listener, $0, &size) } }
        self.listener = listener
        port = UInt16(bigEndian: bound.sin_port)
        Thread.detachNewThread { [self] in
            while isStopped == false {
                var ready = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
                guard poll(&ready, 1, 50) > 0 else { continue }
                let fd = accept(listener, nil, nil)
                guard fd >= 0 else { continue }
                Thread.detachNewThread { [self] in
                    var on: Int32 = 1
                    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
                    serve(fd, reply)
                    close(fd)
                }
            }
            close(listener)
        }
    }

    private var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    func stop() { lock.lock(); stopped = true; lock.unlock() }

    private func serve(_ fd: Int32, _ reply: (String, String, Data) -> (status: Int, body: String)?) {
        var head = Data()
        var byte: UInt8 = 0
        while head.suffix(4) != Data("\r\n\r\n".utf8), read(fd, &byte, 1) == 1 { head.append(byte) }
        let lines = String(decoding: head, as: UTF8.self).components(separatedBy: "\r\n")
        let start = lines[0].split(separator: " ").map(String.init)
        guard start.count >= 2 else { return }
        let length = lines.compactMap { $0.lowercased().hasPrefix("content-length:") ? Int($0.dropFirst(15).trimmingCharacters(in: .whitespaces)) : nil }.first ?? 0
        var body = Data()
        while body.count < length, read(fd, &byte, 1) == 1 { body.append(byte) }
        lock.lock(); seen.append((start[0], start[1], body)); lock.unlock()
        guard let answer = reply(start[0], start[1], body) else {
            // no answer: wait until the client gives up
            while isStopped == false, read(fd, &byte, 1) == 1 {}
            return
        }
        let text = "HTTP/1.1 \(answer.status) X\r\nContent-Type: application/json\r\nContent-Length: \(answer.body.utf8.count)\r\nConnection: close\r\n\r\n\(answer.body)"
        _ = Array(text.utf8).withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
    }
}

private func client(_ server: StubServer) -> LocalModelClient { LocalModelClient(baseURL: { _ in server.url }) }

private func complete(_ client: LocalModelClient, timeout: Duration = .seconds(5)) async throws -> String {
    try await client.complete(server: .lmStudio, model: "qwen", system: "Clean it", text: "um hello", timeout: timeout)
}

@Test func theClientListsTheModelsOfTheServer() async throws {
    let server = StubServer { _, _, _ in (200, #"{"object":"list","data":[{"id":"qwen","object":"model"},{"id":"gemma","object":"model"}]}"#) }
    defer { server.stop() }
    #expect(try await client(server).models(of: .lmStudio) == ["qwen", "gemma"])
    #expect(server.requests.map(\.method) == ["GET"] && server.requests.map(\.path) == ["/v1/models"])
}

@Test func aCompletionSendsThePromptAsSystemAndTheTextAsUserWithNoTools() async throws {
    let server = StubServer { _, _, _ in (200, #"{"choices":[{"message":{"role":"assistant","content":"Hello."}}]}"#) }
    defer { server.stop() }
    #expect(try await complete(client(server)) == "Hello.")
    let request = try #require(server.requests.first)
    #expect(request.method == "POST" && request.path == "/v1/chat/completions")
    let json = try #require(try JSONSerialization.jsonObject(with: request.body) as? [String: Any])
    #expect(json["model"] as? String == "qwen" && json["tools"] == nil && json["stream"] as? Bool == false)
    let messages = try #require(json["messages"] as? [[String: String]])
    #expect(messages == [["role": "system", "content": "Clean it"], ["role": "user", "content": "um hello"]])
}

@Test func theServersAreOnTheLoopbackPortsOfThisMac() {
    #expect(CleanupServer.lmStudio.baseURL.absoluteString == "http://127.0.0.1:1234")
    #expect(CleanupServer.ollama.baseURL.absoluteString == "http://127.0.0.1:11434")
}

@Test func aServerThatIsNotListeningIsDown() async throws {
    // a port that was just free: bind, read the port and close
    let gone = StubServer { _, _, _ in nil }
    gone.stop()
    try await Task.sleep(for: .milliseconds(200))
    await #expect(throws: CleanupFailure.serverDown(.lmStudio)) { try await complete(client(gone)) }
    await #expect(throws: CleanupFailure.serverDown(.lmStudio)) { try await client(gone).models(of: .lmStudio) }
}

@Test func aModelTheServerDoesNotHaveIsNotFound() async {
    let server = StubServer { _, _, _ in (404, #"{"error":{"message":"model not found"}}"#) }
    defer { server.stop() }
    await #expect(throws: CleanupFailure.noModel) { try await complete(client(server)) }
}

@Test func aServerThatDoesNotAnswerTimesOut() async {
    let server = StubServer { _, _, _ in nil }
    defer { server.stop() }
    await #expect(throws: CleanupFailure.timeout) { try await complete(client(server), timeout: .milliseconds(300)) }
}

@Test func aReplyThatIsNotACompletionOrAnErrorStatusIsABadReply() async {
    let words = { (failure: CleanupFailure) in failure.message(bundle: english.bundle, locale: english.locale) }
    #expect(words(.notACompletion(.lmStudio)) == "LM Studio answered something that is not a completion")
    #expect(words(.httpStatus(.lmStudio, 500)) == "LM Studio answered HTTP 500")
    #expect(words(.noModelList(.lmStudio)) == "LM Studio has no list of models")
    #expect(words(.notAModelList(.ollama)) == "Ollama answered something that is not a list of models")
    let odd = StubServer { _, _, _ in (200, "<html>hi</html>") }
    defer { odd.stop() }
    await #expect(throws: CleanupFailure.notACompletion(.lmStudio)) { try await complete(client(odd)) }
    let broken = StubServer { _, _, _ in (500, "") }
    defer { broken.stop() }
    await #expect(throws: CleanupFailure.httpStatus(.lmStudio, 500)) { try await complete(client(broken)) }
}
