import CoreGraphics
import Foundation

extension FixtureServer {
    public func stop() {
        lock.lock(); stopped = true; lock.unlock()
        try? FileManager.default.removeItem(atPath: home)
    }

    private var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }

    static func listen(path: String) throws -> Int32 {
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

    func accept(_ listener: Int32, chat: Bool) {
        while isStopped == false {
            var ready = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
            guard poll(&ready, 1, 50) > 0 else { continue }
            let fd = Darwin.accept(listener, nil, nil)
            guard fd >= 0 else { continue }
            Thread.detachNewThread { [self] in
                var on: Int32 = 1
                setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
                serve(fd, chat: chat)
                Darwin.close(fd)
            }
        }
        Darwin.close(listener)
    }

    /// The hello, then one reply per line until the client leaves or the server stops.
    private func serve(_ fd: Int32, chat: Bool) {
        locked { if chat { chatConnected += 1 } else { engineConnected += 1 } }
        guard send(chat ? chatHello : hello, to: fd) else { return }
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
                // this thread lives as long as the connection, so each request frees what it autoreleases (the JSON of the request)
                let sent = autoreleasepool { send(chat ? chatReply(to: Data(line)) : reply(to: Data(line)), to: fd) }
                guard sent else { return }
            }
        }
    }

    /// What the engine's socket was asked so far, by request name, and how many connections it accepted.
    var engineRequests: [String: Int] { locked { engineAsked } }
    var engineConnections: Int { locked { engineConnected } }

    func reply(to line: Data) -> Data {
        let request = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
        if let cmd = request?["cmd"] as? String { locked { engineAsked[cmd, default: 0] += 1 } }
        guard let id = request?["id"] as? Int else { return Self.refused(nil, "request.invalid", "invalid request") }
        guard let cmd = request?["cmd"] as? String else { return Self.refused(id, "request.invalid", "invalid request") }
        if let body = data[cmd] { return Self.line("{\"id\":\(id),\"ok\":true,\"data\":" + String(decoding: body, as: UTF8.self) + "}") }
        if Self.controls.contains(cmd) { return Self.line("{\"id\":\(id),\"ok\":true}") }
        if cmd == "setWatchedRepos" || cmd == "editBehavior", let answer = engineConfigReply(id, request ?? [:]) { return answer }
        if Self.roleRequests.contains(cmd), let answer = engineRolesReply(id, request ?? [:]) { return answer }
        return Self.refused(id, "request.invalid", "unknown request")
    }

    /// What the chat socket was asked so far, by request name.
    var chatRequests: [String: Int] { locked { chatAsked } }

    /// How many connections the chat socket has accepted so far.
    var chatConnections: Int { locked { chatConnected } }

    func locked<Value>(_ body: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    static func line(_ text: String) -> Data { Data((text + "\n").utf8) }

    func send(_ data: Data, to fd: Int32) -> Bool {
        var sent = 0
        while sent < data.count {
            let n = data.withUnsafeBytes { write(fd, $0.baseAddress! + sent, data.count - sent) }
            if n > 0 { sent += n } else if n < 0 && errno == EINTR { continue } else { return false }
        }
        return true
    }
}
