import Foundation

/// One connection as the test's fake Carrier sees it.
struct ServerConnection {
    let fd: Int32

    func send(_ text: String) { _ = Array(text.utf8).withUnsafeBytes { write(fd, $0.baseAddress, $0.count) } }

    /// The next line the client sent, nil when it closed.
    func readLine() -> String? {
        var line = [UInt8]()
        var byte: UInt8 = 0
        while read(fd, &byte, 1) == 1 {
            if byte == 0x0A { return String(decoding: line, as: UTF8.self) }
            line.append(byte)
        }
        return nil
    }

    /// The `id` of the request line the client sent next.
    func readRequestId() -> Int? {
        guard let line = readLine(), let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return nil }
        return json["id"] as? Int
    }

    func close() { Darwin.close(fd) }
}

/// A Unix socket server on a short temporary path (a socket path holds 103 bytes and the default temp folder takes about 70).
/// Each accepted connection runs `handler` on its own thread, then is closed.
final class TestServer {
    let path: String
    private let listener: Int32
    private var stopped = false
    private let lock = NSLock()

    init(handler: @escaping (ServerConnection) -> Void) {
        let path = "/tmp/cc-\(UUID().uuidString.prefix(8)).sock"
        self.path = path
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path.utf8) }
        let listener = socket(AF_UNIX, SOCK_STREAM, 0)
        self.listener = listener
        _ = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        listen(listener, 4)
        Thread.detachNewThread { [self] in
            while isStopped == false {
                var ready = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
                guard poll(&ready, 1, 50) > 0 else { continue }
                let fd = accept(listener, nil, nil)
                guard fd >= 0 else { continue }
                Thread.detachNewThread {
                    var on: Int32 = 1
                    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
                    handler(ServerConnection(fd: fd))
                    close(fd)
                }
            }
            close(listener)
        }
    }

    private var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }

    func stop() {
        lock.lock(); stopped = true; lock.unlock()
        unlink(path)
    }
}
