import Foundation

public enum FixtureError: Error, Equatable {
    case unreadable(String)
    case socket(String)
}

/// A fake Carrier for the app's `--fixture` mode: a control server on a temporary socket that answers the snapshot and the
/// requests from the golden files (macos/Tests/Fixtures), and `availableRepos` with a made-up list, so the app is exercised through its real client path with no engine.
/// It owns a temporary home (`home`) holding a `config.json` whose `root` is the home itself, so pointing `CARRIER_HOME` at it
/// makes `controlSocketPath()` find the socket. `stop()` removes the home and everything in it.
public final class FixtureServer {
    public let home: String
    public var socketPath: String { home + "/orchestrator/control.sock" }

    private let listener: Int32
    private let data: [String: Data]
    private let hello: Data
    private var stopped = false
    private let lock = NSLock()

    /// request name -> golden file
    private static let files = [
        "snapshot": "snapshot.json", "sessions": "reply-sessions.json", "events": "reply-events.json",
        "epic": "reply-epic.json", "files": "reply-files.json",
    ]
    /// What `availableRepos` answers: a few owners, some private, one already in the golden snapshot's repos.
    static let availableRepos = """
    {"repos":[{"name":"AshuLab/web","private":true,"pushedAt":"2026-10-22T10:00:00Z"},\
    {"name":"AshuLab/agent-forge","private":false,"pushedAt":"2026-10-20T08:30:00Z"},\
    {"name":"AshuLab/docs","private":false,"pushedAt":"2026-09-02T12:00:00Z"},\
    {"name":"vemec/encaja","private":true,"pushedAt":"2026-10-22T06:00:00Z"},\
    {"name":"vemec/dotfiles","private":false,"pushedAt":null},\
    {"name":"acme/web","private":true,"pushedAt":"2026-08-01T09:00:00Z"},\
    {"name":"acme/api","private":true,"pushedAt":"2026-10-15T09:00:00Z"}],"hasMore":false}
    """

    /// Accepted and answered with nothing, as the real engine would; the fixture has no one to pause or stop.
    private static let controls: Set<String> = ["pause", "resume", "checkNow", "stop", "resumeEpic"]

    /// `longTranscript`: `events` answers with a made-up transcript of thousands of events instead of the golden file.
    public init(fixtures: String, longTranscript: Bool = false) throws {
        var data: [String: Data] = [:]
        for (name, file) in Self.files {
            do {
                // compact: a reply is one line
                let json = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: fixtures + "/" + file)))
                data[name] = try JSONSerialization.data(withJSONObject: json, options: .sortedKeys)
            } catch { throw FixtureError.unreadable("\(fixtures)/\(file)") }
        }
        // the golden file holds several replies: every file of `reply-files.json` opens to the first
        do {
            let replies = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: fixtures + "/reply-filediff.json"))) as? [Any]
            guard let first = replies?.first else { throw FixtureError.unreadable("\(fixtures)/reply-filediff.json") }
            data["fileDiff"] = try JSONSerialization.data(withJSONObject: first, options: .sortedKeys)
        } catch { throw FixtureError.unreadable("\(fixtures)/reply-filediff.json") }
        if longTranscript {
            let reply = EventsReply(events: longTranscriptEvents(rounds: 400), next: 3600, running: true, structured: true)
            data["events"] = try JSONEncoder().encode(reply)
        }
        data["availableRepos"] = Data(Self.availableRepos.utf8)
        self.data = data
        let names = ["sessions", "events", "epic", "files", "fileDiff", "availableRepos", "availableReposPaged", "resumeEpic"].map { "\"\($0)\"" }.joined(separator: ",")
        hello = Data("{\"event\":\"hello\",\"protocol\":1,\"pid\":\(getpid()),\"startedAt\":0,\"version\":\"fixture\",\"capabilities\":[\(names)]}\n".utf8)

        // /tmp, not the default temp folder: a socket path holds 103 bytes and that folder takes about 70
        var template = Array("/tmp/carrier-fixture-XXXXXX".utf8CString)
        guard mkdtemp(&template) != nil else { throw FixtureError.socket("cannot create a temporary folder") }
        let home = String(cString: template)
        self.home = home
        do {
            let orchestrator = home + "/orchestrator"
            try FileManager.default.createDirectory(atPath: orchestrator, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: ["root": home]).write(to: URL(fileURLWithPath: home + "/config.json"))
            listener = try Self.listen(path: orchestrator + "/control.sock")
        } catch {
            try? FileManager.default.removeItem(atPath: home)
            throw error
        }
        Thread.detachNewThread { [self] in accept() }
    }

    public func stop() {
        lock.lock(); stopped = true; lock.unlock()
        try? FileManager.default.removeItem(atPath: home)
    }

    private var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }

    private static func listen(path: String) throws -> Int32 {
        var address = sockaddr_un()
        guard path.utf8.count < MemoryLayout.size(ofValue: address.sun_path) else { throw FixtureError.socket("path too long: \(path)") }
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path.utf8) }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw FixtureError.socket("socket() failed") }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, Darwin.listen(fd, 4) == 0 else {
            Darwin.close(fd)
            throw FixtureError.socket("cannot listen on \(path)")
        }
        return fd
    }

    private func accept() {
        while isStopped == false {
            var ready = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
            guard poll(&ready, 1, 50) > 0 else { continue }
            let fd = Darwin.accept(listener, nil, nil)
            guard fd >= 0 else { continue }
            Thread.detachNewThread { [self] in
                var on: Int32 = 1
                setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
                serve(fd)
                Darwin.close(fd)
            }
        }
        Darwin.close(listener)
    }

    /// The hello, then one reply per line until the client leaves or the server stops.
    private func serve(_ fd: Int32) {
        guard send(hello, to: fd) else { return }
        var pending = Data()
        while isStopped == false {
            var ready = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&ready, 1, 50) >= 0 else { return }
            guard ready.revents != 0 else { continue }
            var chunk = [UInt8](repeating: 0, count: 4096)
            let n = read(fd, &chunk, chunk.count)
            guard n > 0 else { return }
            pending.append(contentsOf: chunk[..<n])
            while let end = pending.firstIndex(of: 0x0A) {
                let line = pending[pending.startIndex..<end]
                pending.removeSubrange(pending.startIndex...end)
                guard send(reply(to: Data(line)), to: fd) else { return }
            }
        }
    }

    private func reply(to line: Data) -> Data {
        let request = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
        guard let id = request?["id"] as? Int else { return Self.line("{\"id\":null,\"ok\":false,\"error\":\"invalid request\"}") }
        guard let cmd = request?["cmd"] as? String else { return Self.line("{\"id\":\(id),\"ok\":false,\"error\":\"invalid request\"}") }
        if let body = data[cmd] { return Self.line("{\"id\":\(id),\"ok\":true,\"data\":" + String(decoding: body, as: UTF8.self) + "}") }
        if Self.controls.contains(cmd) { return Self.line("{\"id\":\(id),\"ok\":true}") }
        return Self.line("{\"id\":\(id),\"ok\":false,\"error\":\"unknown request\"}")
    }

    private static func line(_ text: String) -> Data { Data((text + "\n").utf8) }

    private func send(_ data: Data, to fd: Int32) -> Bool {
        var sent = 0
        while sent < data.count {
            let n = data.withUnsafeBytes { write(fd, $0.baseAddress! + sent, data.count - sent) }
            if n > 0 { sent += n } else if n < 0 && errno == EINTR { continue } else { return false }
        }
        return true
    }
}
