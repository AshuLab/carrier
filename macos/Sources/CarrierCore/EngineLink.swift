import Foundation
import Synchronization

// The app's reads of the engine (docs/macos/app-shell.md#how-the-app-reads-the-engine): one connection for the state, however many ask for it,
// and the window's epic requests on a second one while it is open.

/// The app's one reader of the engine's control socket.
/// The menu and the window both want the engine's state: `states()` gives it to each, and one `ControlMonitor` reads it for them all, so the engine builds
/// and serializes one `snapshot` a read and not one per listener. The first listener starts the reads and the last one stops them; one that comes later is
/// given the last state at once, and `refresh` reads again now and not at the end of the wait (the window opens on a state of the moment, not of the last read).
/// The wait is the app's `PollPace`, which follows who is looking; a connection that breaks is told once as `.stopped` and tried again every `retry` seconds.
///
/// The engine answers each connection in order, and a `files` or an `epic` waits on git for as long as seconds, so the epic view's requests do not share the
/// connection of the snapshots: they would hold the menu's state back (and past the client's timeout, which reads as the engine being stopped).
/// `setTick` gives them one connection of their own, opened while the window has a tick set and closed when it is taken away; the actions (pause, resume,
/// check now, reload) keep theirs, one per request.
public final class EngineLink: @unchecked Sendable {
    public static let shared = EngineLink(path: { controlSocketPath() })

    private struct State {
        var listeners: [Int: AsyncStream<ConnectionState>.Continuation] = [:]
        var nextListener = 0
        var latest: ConnectionState?
        /// Set while the state is being read: the flag of the monitor's thread, which ends it.
        var reading: StopFlag?
        var tick: ((ControlClient) throws -> Void)?
        /// Set while the epic view's connection is open.
        var epic: StopFlag?
    }

    private let path: () -> String
    private let pace: () -> TimeInterval
    private let retry: TimeInterval
    private let log: (String) -> Void
    private let state = Mutex(State())
    /// Held for as long as the epic view's connection lives, so a tick put back after one taken away starts when that one is done: the epic poller is for one thread at a time.
    private let epicThread = NSLock()

    public init(
        path: @escaping () -> String, pace: @escaping () -> TimeInterval = { PollPace.shared.seconds }, retry: TimeInterval = 3,
        log: @escaping (String) -> Void = { FileHandle.standardError.write(Data("carrier: \($0)\n".utf8)) }
    ) {
        self.path = path
        self.pace = pace
        self.retry = retry
        self.log = log
    }

    /// The state of the engine as of the last read, then each read after it, until what iterates it ends. A listener that does not keep up is given only the newest.
    public func states() -> AsyncStream<ConnectionState> {
        let (stream, continuation) = AsyncStream.makeStream(of: ConnectionState.self, bufferingPolicy: .bufferingNewest(1))
        let (id, latest, start) = state.withLock { state -> (Int, ConnectionState?, StopFlag?) in
            let id = state.nextListener
            state.nextListener += 1
            state.listeners[id] = continuation
            guard state.reading == nil else { return (id, state.latest, nil) }
            let flag = StopFlag()
            state.reading = flag
            return (id, state.latest, flag)
        }
        continuation.onTermination = { [weak self] _ in self?.stopListening(id) }
        if let latest { continuation.yield(latest) }
        if let start { Thread.detachNewThread { self.read(until: start) } }
        return stream
    }

    /// Reads the state now and not at the end of the wait.
    public func refresh() {
        let reading = state.withLock { $0.reading }
        reading?.wake()
    }

    /// Sets what the window asks of the engine at each pass (its epic's requests), or takes it away with nil when it closes. Set, it runs on a
    /// connection of its own at the same pace, and not at all while nil.
    public func setTick(_ tick: ((ControlClient) throws -> Void)?) {
        let start = state.withLock { state -> StopFlag? in
            state.tick = tick
            if tick == nil {
                state.epic?.set()
                state.epic = nil
                return nil
            }
            guard state.epic == nil else { return nil }
            let flag = StopFlag()
            state.epic = flag
            return flag
        }
        if let start { Thread.detachNewThread { self.readEpic(until: start) } }
    }

    private func stopListening(_ id: Int) {
        let stopped = state.withLock { state -> StopFlag? in
            state.listeners[id] = nil
            guard state.listeners.isEmpty else { return nil }
            // no one is told what was before when someone listens again: the last state would be as old as the pause
            state.latest = nil
            defer { state.reading = nil }
            return state.reading
        }
        stopped?.set()
    }

    private func read(until stop: StopFlag) {
        ControlMonitor(
            socketPath: path, pollEvery: pace, retryInterval: retry, wait: stop.wait, log: log,
            onChange: { [self] in publish($0, from: stop) }
        ).run()
    }

    private func readEpic(until stop: StopFlag) {
        epicThread.lock()
        defer { epicThread.unlock() }
        guard stop.isSet == false else { return }
        // what this connection reports of the engine is the other one's to tell
        ControlMonitor(
            socketPath: path, pollEvery: pace, retryInterval: retry, wait: stop.wait, log: { [log] in log("epic connection: \($0)") }, readsSnapshot: false,
            tick: { [self] client in try state.withLock { $0.tick }?(client) }, onChange: { _ in }
        ).run()
    }

    /// Told to everyone who listens; a read that was the last of a monitor already let go is not.
    private func publish(_ new: ConnectionState, from stop: StopFlag) {
        let heard = state.withLock { state -> [AsyncStream<ConnectionState>.Continuation] in
            guard state.reading === stop else { return [] }
            state.latest = new
            return Array(state.listeners.values)
        }
        for listener in heard { listener.yield(new) }
    }
}
