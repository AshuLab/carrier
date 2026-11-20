import Foundation
import Synchronization

/// How often the app asks the chat host and the engine how things are. While the person is looking (the app is active and its window is
/// on screen) every 2 seconds, so a change shows within a moment; otherwise every 5 seconds, which is still prompt for a notification
/// (a session that waits for the person) and a fifth of what it was, and every 10 in Low Power Mode. Never above a minute: the chat host
/// closes a session that nobody has asked after a minute, and the app asking is what keeps the open ones awake (`clientJoined` in the host).
/// It has no state of its own to decide: `Viewing` writes it, for the threads that cannot read an object of the main actor.
public final class PollPace: Sendable {
    public static let shared = PollPace()
    public static let attentiveSeconds: TimeInterval = 2
    public static let backgroundSeconds: TimeInterval = 5
    public static let lowPowerSeconds: TimeInterval = 10

    private struct Mirror {
        var state = ViewingState.hidden
        var lowPower = false
    }

    private let mirror = Mutex(Mirror())

    public init() {}

    /// Called by `Viewing` when something it tells changed.
    public func set(_ state: ViewingState, lowPower: Bool) { mirror.withLock { $0 = Mirror(state: state, lowPower: lowPower) } }

    /// The wait before the next ask.
    public var seconds: TimeInterval {
        let now = mirror.withLock { $0 }
        if now.state == .focused { return Self.attentiveSeconds }
        return now.lowPower ? Self.lowPowerSeconds : Self.backgroundSeconds
    }

    /// The wait of what only serves the window (its sessions list, the epic it shows): `seconds` while someone can see it, and the pause of a
    /// conversation while not, which a change of who looks cuts short. Never above a minute, as the host hears from the app to keep sessions awake.
    public var windowSeconds: TimeInterval { looking ? seconds : conversationPause }

    /// Someone can see the window.
    public var looking: Bool {
        let state = mirror.withLock { $0.state }
        return state == .focused || state == .visible
    }
}

/// The wait between two reads of the chat host, which can be cut short: after the person archives a session, the list is read at once and
/// not at the next tick. A `wake` that comes before the wait starts (while a read is in flight) makes the next wait return at once.
public final class PollNap: Sendable {
    private struct State {
        var sleeping: Task<Void, Never>?
        var woken = false
        var wakes = 0
    }

    private let state = Mutex(State())

    public init() {}

    /// How many times it was woken, for the tests of who wakes it.
    var wakes: Int { state.withLock { $0.wakes } }

    public func wake() {
        state.withLock {
            $0.wakes += 1
            $0.woken = true
            $0.sleeping?.cancel()
        }
    }

    public func sleep(seconds: TimeInterval) async {
        let nap = Task<Void, Never> { _ = try? await Task.sleep(for: .seconds(seconds)) }
        let skip = state.withLock { state in
            if state.woken { return true }
            state.sleeping = nap
            return false
        }
        if skip { nap.cancel() } else { await nap.value }
        state.withLock {
            $0.sleeping = nil
            $0.woken = false
        }
    }
}

/// Set from the main thread when a window closes; the thread that works for that window sleeps in `wait`, which `set` cuts short at once.
/// The thread sleeps for real in between: it used to wake ten times a second to look at the flag.
public final class StopFlag: @unchecked Sendable {
    private let condition = NSCondition()
    private var stopped = false

    public init() {}

    public var isSet: Bool {
        condition.lock()
        defer { condition.unlock() }
        return stopped
    }

    public func set() {
        condition.lock()
        stopped = true
        condition.broadcast()
        condition.unlock()
    }

    /// Sleeps `seconds`, or less when `set` is called meanwhile; false once it is set, which ends the caller's loop.
    public func wait(_ seconds: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        condition.lock()
        defer { condition.unlock() }
        // a wake-up with the flag still down (spurious) waits again until the deadline
        while stopped == false, condition.wait(until: deadline) {}
        return stopped == false
    }
}
