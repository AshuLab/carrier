import Foundation
@testable import CarrierCore

/// A fake Carrier that answers the four requests with the engine's golden replies and keeps every request line it got.
final class FixtureEngine {
    let server: TestServer

    /// `fail` names the commands answered with an error reply; `garbage` the ones answered with `data` that is not a reply, `replies` the data to send instead of the golden one.
    init(capabilities: [String], fail: Set<String> = [], garbage: Set<String> = [], replies: [String: String] = [:]) {
        let hello = "{\"event\":\"hello\",\"protocol\":1,\"pid\":42,\"startedAt\":1000,\"version\":\"0.2.0\",\"capabilities\":[\(capabilities.map { "\"\($0)\"" }.joined(separator: ","))]}\n"
        let box = Box()
        server = TestServer { connection in
            connection.send(hello)
            while let line = connection.readLine() {
                guard let request = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let id = request["id"] as? Int, let cmd = request["cmd"] as? String else { continue }
                box.append(line)
                if fail.contains(cmd) {
                    connection.send("{\"id\":\(id),\"ok\":false,\"error\":\"internal error\"}\n")
                } else if garbage.contains(cmd) {
                    connection.send("{\"id\":\(id),\"ok\":true,\"data\":{\"unexpected\":true}}\n")
                } else {
                    connection.send("{\"id\":\(id),\"ok\":true,\"data\":\(replies[cmd] ?? FixtureEngine.golden(cmd))}\n")
                }
            }
        }
        self.box = box
    }

    private let box: Box

    var path: String { server.path }
    func stop() { server.stop() }

    /// The request lines received so far, as objects.
    var requests: [[String: Any]] { box.all.compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] } }
    var commands: [String] { requests.compactMap { $0["cmd"] as? String } }

    static func golden(_ cmd: String) -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/reply-\(cmd).json")
        let json = try! JSONSerialization.jsonObject(with: Data(contentsOf: url))
        return String(decoding: try! JSONSerialization.data(withJSONObject: json), as: UTF8.self)
    }

    private final class Box {
        private let lock = NSLock()
        private var lines: [String] = []
        func append(_ line: String) { lock.lock(); lines.append(line); lock.unlock() }
        var all: [String] { lock.lock(); defer { lock.unlock() }; return lines }
    }
}
