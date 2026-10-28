import Foundation

public enum ControlError: Error, Equatable {
    case closed
    case timeout
    case badLine
    case remote(String)
}

/// One connection to Carrier's control socket: newline-delimited JSON, blocking, so it belongs on its own thread.
/// A POSIX socket rather than Network.framework: a missing or stale socket fails at once instead of waiting and retrying,
/// and a path that does not fit is refused here instead of crashing the process.
public final class ControlClient {
    private let fd: Int32
    private var buffer = Data()
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

    /// Safe to call twice (and again by `deinit`): closing an fd a second time could close one another thread has since been given.
    public func close() {
        guard isOpen else { return }
        isOpen = false
        Darwin.close(fd)
    }

    /// Ends the conversation from another thread: the read that is waiting in this one gets EOF and throws `closed`. The descriptor
    /// stays this client's until `close()`, which is still the owner's to call.
    public func abort() {
        guard isOpen else { return }
        shutdown(fd, SHUT_RDWR)
    }

    /// What Carrier says about itself on connect. An engine older than the version and capabilities has neither: `version` is nil and `capabilities` empty.
    public struct Hello: Equatable {
        public let protocolVersion: Int
        public let version: String?
        public let capabilities: Set<Capability>
    }

    /// The optional requests an engine can answer, and the chat host's own (`agents` onwards). A name this app does not know is dropped, so a newer engine never breaks an older app.
    public enum Capability: String {
        case sessions, events, epic, files, fileDiff, availableRepos, availableReposPaged, resumeEpic
        case agents, list, open, resume, send, answer, interrupt, setOption, close, archive, delete, deletePreview, stop
        case workspace, fetch, suggestName, checkName, cloneRepo, createProject, githubRepos
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

    /// `request`, but only when the engine said it can answer it: nil, with nothing sent, when it did not.
    public func request(_ command: String, requires capability: Capability, fields: String = "") throws -> Data? {
        guard capabilities.contains(capability) else { return nil }
        return try request(command, fields: fields)
    }

    /// Sends the command with the next id and waits for its reply; returns the reply's `data`, as JSON bytes, `null` when it has none.
    /// `fields` is more of the request object, already JSON (`,"lines":60`); only this file's callers build it, from checked values.
    public func request(_ command: String, fields: String = "") throws -> Data {
        lastId += 1
        try write(Data("{\"id\":\(lastId),\"cmd\":\"\(command)\"\(fields)}\n".utf8))
        while true {
            let reply = try json(readLine())
            let id = reply["id"] as? Int
            // a reply to an earlier request that gave up is skipped; an error with no id can only be about this one
            guard id == lastId || (id == nil && reply["ok"] as? Bool == false) else { continue }
            guard reply["ok"] as? Bool == true else { throw ControlError.remote(reply["error"] as? String ?? "unknown error") }
            guard let data = reply["data"] else { return Data("null".utf8) }
            return try JSONSerialization.data(withJSONObject: data, options: .fragmentsAllowed)
        }
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
            if let end = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<end]
                buffer.removeSubrange(buffer.startIndex...end)
                return Data(line)
            }
            guard buffer.count <= maxLineBytes else { throw ControlError.badLine }
            var chunk = [UInt8](repeating: 0, count: 4096)
            let n = read(fd, &chunk, chunk.count)
            if n > 0 {
                buffer.append(contentsOf: chunk[..<n])
            } else if n < 0 && errno == EINTR {
                continue
            } else if n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                throw ControlError.timeout
            } else {
                throw ControlError.closed
            }
        }
    }
}
