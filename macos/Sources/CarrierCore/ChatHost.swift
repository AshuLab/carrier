import Foundation

// The app's side of the chat host's socket (docs/specs/chat-host.md, sessions-in-the-app.md): the requests it needs so far,
// a monitor that says whether the host answers, and the rule for the Sessions + flag. The slices that use more requests add them to `ChatHost`.

public struct ChatAgent: Decodable, Equatable {
    public let name: String
    public let harness: String
    public let model: String?
    /// Whether the agent's binary was found on the host's machine.
    public let found: Bool

    public init(name: String, harness: String, model: String? = nil, found: Bool) {
        self.name = name
        self.harness = harness
        self.model = model
        self.found = found
    }
}

/// A session as the host's `list` carries it: times are milliseconds since the epoch.
public struct ChatSession: Decodable, Equatable {
    public enum State: String, Decodable { case working, waitingApproval = "waiting_approval", idle }

    public let id: String
    public let agent: String
    public let harness: String
    public let folder: String
    public let title: String?
    public let state: State
    public let createdAt: Int
    public let lastActiveAt: Int
    public let archived: Bool
    /// Set for a session in a worktree: `base` is the repository's folder, which is where the session is grouped.
    public let workspace: Workspace?
    /// Whether the session's agent process runs: a closed one is resumed before a message is sent to it.
    public let live: Bool

    public struct Workspace: Decodable, Equatable {
        public let base: String
        public let branch: String?
    }
}

/// What the app needs from the chat host's socket; the real one speaks to the socket, tests use a fake.
public protocol ChatHost {
    func agents() async throws -> [ChatAgent]
    func list(archived: Bool) async throws -> [ChatSession]
}

/// The chat host over its socket: one connection per call (a host with no client attached may end itself), with the blocking
/// socket work off the caller's thread. A host that is not there, or goes away mid-call, is `ControlError.closed`; an error reply is `.remote`.
public struct SocketChatHost: ChatHost {
    private let socketPath: () -> String

    public init(socketPath: @escaping () -> String = { chatSocketPath() }) { self.socketPath = socketPath }

    public func agents() async throws -> [ChatAgent] {
        let path = socketPath()
        return try await Task.detached { try chatRequest(path, "agents", requires: .agents) }.value
    }

    public func list(archived: Bool) async throws -> [ChatSession] {
        let path = socketPath()
        let reply: ChatSessionsReply = try await Task.detached { try chatRequest(path, "list", requires: .list, fields: ",\"archived\":\(archived)") }.value
        return reply.sessions
    }
}

private struct ChatSessionsReply: Decodable { let sessions: [ChatSession] }

/// Connects, reads the hello, makes one request the host said it can answer and decodes its reply.
func chatRequest<Reply: Decodable>(_ path: String, _ command: String, requires capability: ControlClient.Capability, fields: String = "") throws -> Reply {
    guard let client = ControlClient.connect(path: path) else { throw ControlError.closed }
    defer { client.close() }
    guard try client.hello().protocolVersion == 1 else { throw ControlError.remote("incompatible chat host") }
    guard let data = try client.request(command, requires: capability, fields: fields) else {
        throw ControlError.remote("the chat host does not support \(command)")
    }
    do { return try JSONDecoder().decode(Reply.self, from: data) } catch { throw ControlError.badLine }
}

public enum ChatHostState: Equatable {
    case stopped
    case running(agents: [ChatAgent])
}

/// Keeps what the app knows of the chat host current: asks for the agents every `interval`, on a new connection each time so
/// the app does not hold the host up. Anything but an answer is `.stopped`. `run()` blocks, so it belongs on its own thread;
/// `wait` is how it sleeps and returns false to end `run()`.
public final class ChatMonitor {
    private let socketPath: () -> String
    private let interval: TimeInterval
    private let wait: (TimeInterval) -> Bool
    private let log: (String) -> Void
    private let onChange: (ChatHostState) -> Void

    public init(
        socketPath: @escaping () -> String = { chatSocketPath() },
        interval: TimeInterval = 3,
        wait: @escaping (TimeInterval) -> Bool = { Thread.sleep(forTimeInterval: $0); return true },
        log: @escaping (String) -> Void = { FileHandle.standardError.write(Data("carrier: \($0)\n".utf8)) },
        onChange: @escaping (ChatHostState) -> Void
    ) {
        self.socketPath = socketPath
        self.interval = interval
        self.wait = wait
        self.log = log
        self.onChange = onChange
    }

    public func run() {
        repeat {
            do {
                onChange(.running(agents: try chatRequest(socketPath(), "agents", requires: .agents)))
            } catch ControlError.closed {
                onChange(.stopped)
            } catch {
                log("chat host: \(error)")
                onChange(.stopped)
            }
        } while wait(interval)
    }
}

public let hostNotRunning = "The chat host is not running"

/// Why the Sessions + is off, nil when it can start a session: the host answers and at least one of its agents has its binary.
public func cannotStartReason(host: ChatHostState) -> String? {
    switch host {
    case .stopped: hostNotRunning
    case .running(let agents): agents.contains(where: \.found) ? nil : "No agent found: install claude or codex"
    }
}
