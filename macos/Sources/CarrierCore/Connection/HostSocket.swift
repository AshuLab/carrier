import Foundation

/// What a host's socket says when it is asked.
public enum HostHello: Equatable {
    /// No one listens on the socket.
    case nobody
    /// Someone answered but its hello could not be read.
    case unreadable
    case said(ControlClient.Hello)
}

/// Asking a host's socket whether it answers and what its hello says: the models that start a host or probe it take this, and their tests take a fake.
public protocol HostSocket: Sendable {
    /// Blocks, briefly: call it off the main thread.
    func answers(at path: String) -> Bool
    func hello(at path: String) -> HostHello
}

/// `HostSocket` on a `ControlClient`.
public struct ControlSocket: HostSocket {
    public init() {}

    public func answers(at path: String) -> Bool {
        guard let client = ControlClient.connect(path: path) else { return false }
        client.close()
        return true
    }

    public func hello(at path: String) -> HostHello {
        guard let client = ControlClient.connect(path: path) else { return .nobody }
        defer { client.close() }
        guard let hello = try? client.hello() else { return .unreadable }
        return .said(hello)
    }
}
