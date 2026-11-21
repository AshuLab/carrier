import Foundation
import Synchronization

/// How often the app asks the chat host and the engine how things are. While the person is looking (the app is active and its window is
/// on screen) every 2 seconds, so a change shows within a moment; otherwise every 5 seconds, which is still prompt for a notification
/// (a session that waits for the person) and a fifth of what it was, and every 10 in Low Power Mode. This pace keeps no session awake: the chat
/// host closes an idle session that no request about it names for ten minutes, and listing the sessions names none (a conversation's own `events` do).
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
        mirror.withLock { $0.state.canBeSeen }
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

/// What ends a thread that works for the app: the thread sleeps in `wait`, which `set` cuts short at once and ends for good, and `wake` cuts short
/// once (a `wake` that comes while the thread works makes its next wait return at once, as `PollNap` does).
/// The thread sleeps for real in between: it used to wake ten times a second to look at the flag.
public final class StopFlag: @unchecked Sendable {
    private let condition = NSCondition()
    private var stopped = false
    private var woken = false

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

    /// The next `wait` returns at once, or the one under way does.
    public func wake() {
        condition.lock()
        woken = true
        condition.broadcast()
        condition.unlock()
    }

    /// Sleeps `seconds`, or less when `set` or `wake` is called meanwhile; false once it is set, which ends the caller's loop.
    public func wait(_ seconds: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        condition.lock()
        defer { condition.unlock() }
        // a wake-up with neither flag up (spurious) waits again until the deadline
        while stopped == false, woken == false, condition.wait(until: deadline) {}
        woken = false
        return stopped == false
    }
}
