import Foundation
import Synchronization

// The app's reads of the chat host (docs/macos/sessions.md#how-the-app-reads-the-chat-host): one connection kept for the socket, one place where a miss is told, and the sessions
// list read once for everyone who wants it.

/// The sessions as of one read of the host.
public struct SessionsUpdate: Equatable, Sendable {
    public let active: [ChatSession]
    public let archived: [ChatSession]
    /// The host did not answer this time: the lists are the last good ones (empty when none was ever read), never an empty list the host did not say.
    public let stale: Bool
    /// Both lists were read in this cycle and the host answered: what the terminals' pruning needs to see a session gone for good.
    public let authoritative: Bool
    /// The last update, given again to someone who just began to listen: not a read made for them, so it is not authoritative.
    public let replayed: Bool
    /// When the read began: a list read before something happened cannot say how it came out.
    public let readAt: Date

    public init(active: [ChatSession], archived: [ChatSession], stale: Bool = false, authoritative: Bool = false, replayed: Bool = false, readAt: Date = Date()) {
        (self.active, self.archived, self.stale, self.authoritative, self.replayed, self.readAt) = (active, archived, stale, authoritative, replayed, readAt)
    }
}

/// The wait before the next read of the sessions: the pace while the host answers, and once for each read in a row that failed, double the last wait
/// (the first miss waits twice the pace: 4 seconds at a pace of 2), up to 10 seconds while someone can see the window (a host restarted by hand shows
/// within that, as the window's own poll did) and up to 30 when nobody can.
func sessionsPollWait(pace: TimeInterval, failures: Int, looking: Bool) -> TimeInterval {
    failures == 0 ? pace : min(pace * Double(1 << min(failures, 5)), looking ? 10 : 30)
}

/// The rules for reading the sessions. The active list is read every time. The archived one every `archivedEvery` seconds (the host builds all of
/// it each time), at once after an archive, a restore or a delete of the app's own (`invalidateArchived`), and when a session leaves the active list
/// without being in the archived one (something other than the app archived or deleted it: the terminals of a session are pruned only once the
/// archived list has answered for it). A host that does not answer changes nothing: the lists stay as they were, and the archived one is read
/// again when it answers; one that fails only on the archived list keeps the archived rows it had.
final class SessionsReader: Sendable {
    private struct State {
        var active: [ChatSession] = []
        var archived: [ChatSession] = []
        var archivedAt: Date?
        /// The ids the last active list had: one that is gone from it and is not in the archived list was archived or deleted by something other than the app.
        var activeIds: Set<String> = []
        var invalidated = false
    }

    private let archivedEvery: TimeInterval
    private let now: @Sendable () -> Date
    private let state = Mutex(State())

    init(archivedEvery: TimeInterval = 60, now: @escaping @Sendable () -> Date = { Date() }) {
        self.archivedEvery = archivedEvery
        self.now = now
    }

    /// The archived list is read again at the next `read`, whatever its age. Callable from any thread.
    func invalidateArchived() { state.withLock { $0.invalidated = true } }

    /// One cycle through `list`; the failure is what the host's miss was, for whoever tells it.
    func read(_ list: (Bool) async throws -> [ChatSession]) async -> (update: SessionsUpdate, failure: Error?) {
        let signpost = Signposts.poll.beginInterval("sessions poll", id: Signposts.poll.makeSignpostID())
        var outcome = "failed"
        defer { Signposts.poll.endInterval("sessions poll", signpost, "\(outcome, privacy: .public)") }
        let started = now()
        let active: [ChatSession]
        do { active = try await list(false) } catch {
            let last = state.withLock { state in
                state.archivedAt = nil
                return state
            }
            return (SessionsUpdate(active: last.active, archived: last.archived, stale: true, readAt: started), error)
        }
        let (due, invalidated, gone) = state.withLock { state in
            let invalidated = state.invalidated
            state.invalidated = false
            let gone = state.activeIds.subtracting(active.map(\.id)).subtracting(state.archived.map(\.id))
            let aged = state.archivedAt.map { now().timeIntervalSince($0) >= archivedEvery } ?? true
            return (invalidated || !gone.isEmpty || aged, invalidated, gone)
        }
        var refreshed = false
        if due {
            if let listed = try? await list(true) {
                state.withLock {
                    $0.archived = listed
                    $0.archivedAt = now()
                }
                refreshed = true
            } else if invalidated {
                invalidateArchived() // the app asked for a read and it failed: asked again at the next cycle
            }
        }
        let archived = state.withLock { state in
            state.active = active
            // what left the active list is remembered until the archived list has answered for it
            if refreshed || gone.isEmpty { state.activeIds = Set(active.map(\.id)) }
            return state.archived
        }
        outcome = "ok"
        return (SessionsUpdate(active: active, archived: archived, authoritative: refreshed, readAt: started), nil)
    }
}

/// One connection to the chat host, kept between requests: its hello is read once, and its socket work runs on a queue of its own, one request at a
/// time (the host answers a connection in order anyway), so no thread of the cooperative pool waits on it.
final class ChatConnection: @unchecked Sendable {
    private let queue = DispatchQueue(label: "carrier.chat-link")
    /// Confined to `queue`.
    private var client: ControlClient?
    private var connectedTo: String?

    /// Runs `work` on the connection, which is opened (and the hello read) when there is none, the host went away, or the path is another one.
    /// A connection that broke is dropped, and a request that finds it closed is made once more on a new one (the host may have been replaced
    /// since the last one); an error reply is the caller's, and the connection stays.
    /// Two known costs: requests run one at a time, so a host that takes the connection and does not answer holds each queued one for its own timeout in turn
    /// (the last of N waits about N times the timeout, and the timeout drops the connection); and a caller that is cancelled still waits for its reply, which the
    /// continuation cannot be told to stop waiting for.
    func perform<Value>(path: String, _ work: @escaping @Sendable (ControlClient) throws -> Value) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try self.perform(path, work) }) }
        }
    }

    private func perform<Value>(_ path: String, _ work: (ControlClient) throws -> Value) throws -> Value {
        for attempt in 0..<2 {
            var reused = true
            if client == nil || connectedTo != path || client?.peerClosed == true {
                reused = false
                try open(path)
            }
            guard let client else { throw ControlError.closed }
            do { return try work(client) } catch let error as ControlError {
                if case .remote = error { throw error }
                drop()
                // a connection that had been idle may have been closed by a host that went away a moment ago
                if error == .closed, reused, attempt == 0 { continue }
                throw error
            } catch {
                drop()
                throw error
            }
        }
        throw ControlError.closed
    }

    private func open(_ path: String) throws {
        drop()
        guard let fresh = ControlClient.connect(path: path) else { throw ControlError.closed }
        do { _ = try fresh.supportedHello() } catch {
            fresh.close()
            throw error
        }
        client = fresh
        connectedTo = path
    }

    private func drop() {
        client?.close()
        client = nil
    }
}

/// The app's one reader of the chat host's socket.
/// One connection is kept for what the app asks again and again (the sessions, a conversation's `events`, the hello's capabilities), so a poll
/// opens no connection and a hello is read once; the host answers a connection one request at a time, so only requests that return at once go
/// here: anything that can take long (`send`, `resume`, `usage`, a clone) is an action and keeps its own connection (`SocketChatHost`).
/// The sessions are read by one loop for everyone who listens (`sessions()`), at the pace of `PollPace`, and a miss is told once, here.
/// The loop does not renew the keep-alive of any session (the host closes an idle one that no request names for ten minutes): a conversation's own `events` do.
public actor ChatLink {
    private static let links = Mutex<[String: ChatLink]>([:])

    /// The link for the socket at `path`.
    public static func link(for path: String) -> ChatLink {
        links.withLock { links in
            if let link = links[path] { return link }
            let link = ChatLink(path: path)
            links[path] = link
            return link
        }
    }

    private let path: String
    private let connection = ChatConnection()
    private let reader: SessionsReader
    private let nap = PollNap()
    private let pace: @Sendable () -> TimeInterval
    private let looking: @Sendable () -> Bool
    private let sleep: (@Sendable (TimeInterval) async -> Void)?
    private let log: @Sendable (String) -> Void
    private var reads: [Bool: (generation: Int, task: Task<[ChatSession], Error>)] = [:]
    /// Bumped by each `refresh`: a read that began under an older one cannot say how things are after what the refresh was told of.
    private nonisolated let refreshes = Mutex(0)
    private var listeners: [Int: AsyncStream<SessionsUpdate>.Continuation] = [:]
    private var listenerCount = 0
    private var latest: SessionsUpdate?
    private var loop: Task<Void, Never>?
    private var answering = true

    /// `sleep` replaces the wait between two reads of the sessions (the tests'); without it the wait is a nap that `refresh` cuts short.
    init(
        path: String, archivedEvery: TimeInterval = 60, now: @escaping @Sendable () -> Date = { Date() },
        pace: @escaping @Sendable () -> TimeInterval = { PollPace.shared.seconds }, looking: @escaping @Sendable () -> Bool = { PollPace.shared.looking },
        sleep: (@Sendable (TimeInterval) async -> Void)? = nil,
        log: @escaping @Sendable (String) -> Void = { NSLog("Carrier: %@", $0) }
    ) {
        self.path = path
        reader = SessionsReader(archivedEvery: archivedEvery, now: now)
        self.pace = pace
        self.looking = looking
        self.sleep = sleep
        self.log = log
    }

    /// What the sessions were at the last read, then each read after it, until the task that iterates ends. The first one listening starts the reads
    /// and the last one stops them.
    public func sessions() -> AsyncStream<SessionsUpdate> {
        let (stream, continuation) = AsyncStream.makeStream(of: SessionsUpdate.self, bufferingPolicy: .bufferingNewest(1))
        let id = listenerCount
        listenerCount += 1
        listeners[id] = continuation
        continuation.onTermination = { [weak self] _ in Task { await self?.stopListening(id) } }
        if let latest { continuation.yield(SessionsUpdate(active: latest.active, archived: latest.archived, stale: latest.stale, replayed: true, readAt: latest.readAt)) }
        if loop == nil { loop = Task { await self.run() } }
        return stream
    }

    private func stopListening(_ id: Int) {
        listeners[id] = nil
        if listeners.isEmpty {
            loop?.cancel()
            loop = nil
            nap.wake()
        }
    }

    /// Reads the sessions now and not at the end of the wait; with `archived`, the archived list too (after an archive, a restore or a delete).
    /// A wake that comes while a read is under way makes the next wait return at once.
    public nonisolated func refresh(archived: Bool) {
        refreshes.withLock { $0 += 1 }
        if archived { reader.invalidateArchived() }
        nap.wake()
    }

    private func run() async {
        var failures = 0
        while Task.isCancelled == false {
            let (update, failure) = await reader.read { try await self.list(archived: $0) }
            if Task.isCancelled { return }
            if update.stale {
                failures += 1
                // a host that is not there yet, or goes away, is not an event: the first miss after an answer is said, the rest are not
                if answering, let failure { log("the chat host does not answer, asking again in a while: \(failure)") }
                answering = false
            } else {
                failures = 0
                answering = true
            }
            publish(update)
            let wait = sessionsPollWait(pace: pace(), failures: failures, looking: looking())
            if let sleep { await sleep(wait) } else { await nap.sleep(seconds: wait) }
        }
    }

    /// A miss is told once, with the last lists that were good: the ones after it add nothing, and what is told is never an empty list for a host that did not answer.
    private func publish(_ update: SessionsUpdate) {
        if update.stale, latest?.stale == true { return }
        latest = update
        for listener in listeners.values { listener.yield(update) }
    }

    /// The sessions the host lists, active or archived. Two asks at the same time share one request, unless a `refresh` came between them: the read
    /// that began before it still answers its own callers, and the ask after it makes a read of its own.
    public func list(archived: Bool) async throws -> [ChatSession] {
        let generation = refreshes.withLock { $0 }
        if let read = reads[archived], read.generation == generation { return try await read.task.value }
        let read = Task<[ChatSession], Error> {
            defer { if reads[archived]?.generation == generation { reads[archived] = nil } }
            let reply: ChatSessionsReply = try await self.read("list", requires: .list, fields: ",\"archived\":\(archived)")
            return reply.sessions
        }
        reads[archived] = (generation, read)
        return try await read.value
    }

    /// One request the host said it can answer, on the kept connection, decoded into `Reply`.
    public func read<Reply: Decodable>(
        _ command: String, requires capability: ControlClient.Capability, fields: String = "", also: [(capability: ControlClient.Capability, fields: String)] = []
    ) async throws -> Reply {
        try await connection.perform(path: path) { try chatExchange($0, command, requires: capability, fields: fields, also: also) }
    }

    /// What the hello of the kept connection said the host can do: read once, when the connection was opened.
    public func capabilities() async throws -> Set<ControlClient.Capability> {
        try await connection.perform(path: path) { $0.capabilities }
    }
}
