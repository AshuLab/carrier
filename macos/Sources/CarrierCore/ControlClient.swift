import Foundation

public enum ControlError: Error, Equatable {
    case closed
    case timeout
    case badLine
    case remote(String)
}

/// The one protocol number this app speaks; a hello's is compared with it only through `protocolMatch`.
public let supportedProtocol = 1

public enum ProtocolMatch: Equatable {
    case match, carrierOlder, appOlder

    /// What to tell the person when the protocols differ: which side to update and with which command; nil when they match.
    public var update: String? {
        switch self {
        case .match: nil
        case .carrierOlder: "carrier is older than this app. Run brew upgrade carrier in Terminal, then restart Carrier."
        case .appOlder: "This app is older than carrier. It updates itself; if it has not, run brew upgrade --cask carrier in Terminal, then open the app again."
        }
    }
}

public func protocolMatch(_ host: Int) -> ProtocolMatch {
    host == supportedProtocol ? .match : host < supportedProtocol ? .carrierOlder : .appOlder
}

/// One connection to Carrier's control socket: newline-delimited JSON, blocking, so it belongs on its own thread.
/// A POSIX socket rather than Network.framework: a missing or stale socket fails at once instead of waiting and retrying,
/// and a path that does not fit is refused here instead of crashing the process.
public final class ControlClient {
    private let fd: Int32
    private var buffer: [UInt8] = []
    /// How much of `buffer` has been searched for the end of a line, so a long reply read in several pieces is searched once.
    private var scanned = 0
    /// What the searches for the end of a line have looked at in all, and how many replies took one parse: the tests tell a search that
    /// goes over the buffer again at each read, or a reply parsed twice, from these.
    private(set) var bytesScanned = 0
    private(set) var repliesParsedOnce = 0
    private var lastId = 0
    private var isOpen = true
    private let maxLineBytes = 8 * 1024 * 1024

    private init(fd: Int32) { self.fd = fd }

    deinit { close() }

    /// nil when there is no one to talk to: no socket file, nobody listening on it, or a path longer than `sun_path` holds.
    public static func connect(path: String, timeout: TimeInterval = 5) -> ControlClient? {
        var address = sockaddr_un()
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else { return nil }
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path.utf8) }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        // a write to a Carrier that just quit must fail, not raise SIGPIPE; a Carrier that stops answering must not block the read for good
        var on: Int32 = 1
        var limit = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - timeout.rounded(.down)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else {
            Darwin.close(fd)
            return nil
        }
        return ControlClient(fd: fd)
    }

    /// Whether the other end has gone (it closed its socket, or the process died), seen without waiting: a connection kept between requests asks
    /// this before it is used again, so a Carrier that was replaced is reconnected to at once and not found out by a failed request.
    public var peerClosed: Bool {
        guard isOpen else { return true }
        var byte: UInt8 = 0
        let n = recv(fd, &byte, 1, MSG_PEEK | MSG_DONTWAIT)
        if n == 0 { return true }
        return n < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR
    }

    /// Safe to call twice (and again by `deinit`): closing an fd a second time could close one another thread has since been given.
    public func close() {
        guard isOpen else { return }
        isOpen = false
        Darwin.close(fd)
    }

    /// What Carrier says about itself on connect. An engine older than the version and capabilities has neither: `version` is nil and `capabilities` empty.
    public struct Hello: Equatable {
        public let protocolVersion: Int
        public let version: String?
        public let capabilities: Set<Capability>
    }

    /// The optional requests an engine can answer, and the chat host's own (`agents` onwards). A name this app does not know is dropped, so a newer engine never breaks an older app.
    public enum Capability: String, CaseIterable {
        case sessions, events, epic, files, fileDiff, availableRepos, availableReposPaged, resumeEpic, resumeFromStage, resumeReviewerOptions, recoverEpic, reload
        case agents, list, open, resume, send, answer, interrupt, setOption, agentOptions, close, archive, delete, deletePreview, stop
        case workspace, fetch, suggestName, checkName, cloneRepo, createProject, githubRepos, repoBranches, health, providers, plan, reasoning, rename, regenerateTitle, regenerateTitles, usage, usageOverride, accountIdentity, accountPalette, switchAgent, stopTask, worktreeStart, fetchIfStale, listsRev, projects, textGenerators
    }

    /// What the last `hello()` said Carrier can do; empty until then.
    public internal(set) var capabilities: Set<Capability> = []

    /// Reads the hello Carrier sends on connect.
    public func hello() throws -> Hello {
        let hello = try json(readLine())
        guard hello["event"] as? String == "hello", let protocolVersion = hello["protocol"] as? Int else { throw ControlError.badLine }
        let names = hello["capabilities"] as? [String] ?? []
        capabilities = Set(names.compactMap(Capability.init(rawValue:)))
        return Hello(protocolVersion: protocolVersion, version: hello["version"] as? String, capabilities: capabilities)
    }

    /// `hello`, but throws the sentence that says which side to update when the protocols differ, so nothing is sent after it.
    public func supportedHello() throws -> Hello {
        let hello = try hello()
        if let update = protocolMatch(hello.protocolVersion).update { throw ControlError.remote(update) }
        return hello
    }

    /// `request`, but only when the engine said it can answer it: nil, with nothing sent, when it did not.
    public func request(_ command: String, requires capability: Capability, fields: String = "") throws -> Data? {
        guard capabilities.contains(capability) else { return nil }
        return try request(command, fields: fields)
    }

    /// Sends the command with the next id and waits for its reply; returns the reply's `data`, as JSON bytes, `null` when it has none.
    /// `fields` is more of the request object, already JSON (`,"lines":60`); only this file's callers build it, from checked values.
    public func request(_ command: String, fields: String = "") throws -> Data {
        try exchange(command, fields) { try answer($0) }
    }

    /// `request`, but only when the engine said it can answer it, and the reply is decoded into `Reply` (see `request(_:fields:as:decoding:)`):
    /// nil, with nothing sent, when it did not. A reply that does not decode is a bad line.
    public func request<Reply: Decodable>(_ command: String, requires capability: Capability, fields: String = "", as type: Reply.Type) throws -> Reply? {
        guard capabilities.contains(capability) else { return nil }
        return try request(command, fields: fields, as: type) { data in
            do { return try JSONDecoder().decode(Reply.self, from: data) } catch { throw ControlError.badLine }
        }
    }

    /// `request`, but the reply's `data` is decoded into `Reply`: the whole line is parsed once, where handing the bytes of `data` back
    /// takes it apart and puts it together again first. A reply that is not the one waited for, an error or an empty `data` goes the
    /// long way, as `request` does, and `decoding` then reads the bytes of `data`, so it can say what is wrong with them.
    public func request<Reply: Decodable>(
        _ command: String, fields: String = "", as type: Reply.Type, decoding: (Data) throws -> Reply = { try JSONDecoder().decode(Reply.self, from: $0) }
    ) throws -> Reply {
        try exchange(command, fields) { line in
            if let whole = try? JSONDecoder().decode(Answer<Reply>.self, from: line), whole.id == lastId, whole.ok == true, let data = whole.data {
                repliesParsedOnce += 1
                return data
            }
            guard let data = try answer(line) else { return nil }
            return try decoding(data)
        }
    }

    private struct Answer<Payload: Decodable>: Decodable {
        let id: Int?
        let ok: Bool?
        let data: Payload?
    }

    /// Sends the request and reads lines until `take` says one is the answer.
    private func exchange<Result>(_ command: String, _ fields: String, take: (Data) throws -> Result?) throws -> Result {
        // requests come from several threads at once, so each interval has its own id
        let signpost = Signposts.poll.beginInterval("request", id: Signposts.poll.makeSignpostID(), "\(command, privacy: .public)")
        var bytes = 0
        defer { Signposts.poll.endInterval("request", signpost, "\(bytes) bytes") }
        lastId += 1
        try write(Data("{\"id\":\(lastId),\"cmd\":\"\(command)\"\(fields)}\n".utf8))
        while true {
            let line = try readLine()
            bytes += line.count
            if let result = try take(line) { return result }
        }
    }

    /// The `data` of the reply to the last request, `null` when it has none; nil for a line that is not that reply (a reply to an earlier
    /// request that gave up is skipped); an error reply throws.
    private func answer(_ line: Data) throws -> Data? {
        let reply = try json(line)
        let id = reply["id"] as? Int
        // an error with no id can only be about this one
        guard id == lastId || (id == nil && reply["ok"] as? Bool == false) else { return nil }
        guard reply["ok"] as? Bool == true else { throw ControlError.remote(reply["error"] as? String ?? "unknown error") }
        guard let data = reply["data"] else { return Data("null".utf8) }
        return try JSONSerialization.data(withJSONObject: data, options: .fragmentsAllowed)
    }

    /// The last `lines` meaningful lines of an execution's output. Only a UUID goes on the wire, as Carrier accepts nothing else.
    public func tail(executionId: String, lines: Int) throws -> [String] {
        guard let id = UUID(uuidString: executionId)?.uuidString.lowercased() else { throw ControlError.remote("not a valid execution id") }
        let data = try request("tail", fields: ",\"executionId\":\"\(id)\",\"lines\":\(lines)")
        guard let output = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? [String] else { throw ControlError.badLine }
        return output
    }

    private func json(_ line: Data) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { throw ControlError.badLine }
        return object
    }

    private func write(_ data: Data) throws {
        var sent = 0
        while sent < data.count {
            let n = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress! + sent, data.count - sent) }
            if n > 0 { sent += n } else if n < 0 && errno == EINTR { continue } else { throw ControlError.closed }
        }
    }

    private func readLine() throws -> Data {
        while true {
            if let end = endOfLine() {
                let line = Data(buffer[..<end])
                buffer.removeSubrange(...end)
                return line
            }
            guard buffer.count <= maxLineBytes else { throw ControlError.badLine }
            var failure: Int32 = 0
            let n = withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 32 * 1024) { space -> Int in
                let n = read(fd, space.baseAddress, space.count)
                if n > 0 { buffer.append(contentsOf: space[..<n]) } else if n < 0 { failure = errno }
                return n
            }
            if n > 0 {
                continue
            } else if n < 0 && failure == EINTR {
                continue
            } else if n < 0 && (failure == EAGAIN || failure == EWOULDBLOCK) {
                throw ControlError.timeout
            } else {
                throw ControlError.closed
            }
        }
    }

    /// Where the first line in `buffer` ends, looking only at what no earlier search has seen.
    private func endOfLine() -> Int? {
        let fresh = buffer.count - scanned
        guard fresh > 0 else { return nil }
        bytesScanned += fresh
        let found = buffer.withUnsafeBufferPointer { bytes in
            memchr(bytes.baseAddress! + scanned, 0x0A, fresh).map { bytes.baseAddress!.distance(to: $0.assumingMemoryBound(to: UInt8.self)) }
        }
        scanned = found == nil ? buffer.count : 0
        return found
    }
}
