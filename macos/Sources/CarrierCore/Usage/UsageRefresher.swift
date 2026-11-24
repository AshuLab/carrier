import Foundation

/// When the Usage page asks the host again (docs/specs/usage-and-limits.md): as it appears, when someone looks again while it is open (the
/// app active and its window on screen, `PollPace`'s attention), on a Check again, when an epic or a chat session hits a usage limit, and
/// every minute while it is open and looked at: a minimized window, another Space or another app pauses the minute timer. The host keeps
/// quotas for a minute, so only a Check again and a limit that was hit skip its cache (`refresh`).
@MainActor public final class UsageRefresher {
    public static let interval = Duration.seconds(60)

    private let store: UsageStore
    private let sleep: @Sendable (Duration) async throws -> Void
    private var timer: Task<Void, Never>?
    public private(set) var visible = false
    /// Someone is looking: the app is active and its window on screen. Told by the window, as `PollPace` is.
    public private(set) var attentive = true

    /// Whether the minute timer is running: only while the page is open and looked at.
    public var isTimerRunning: Bool { timer != nil }

    public init(store: UsageStore, sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.store = store
        self.sleep = sleep
    }

    public func appear() {
        visible = true
        start()
    }

    public func disappear() {
        visible = false
        stopTimer()
    }

    /// The app became active or not, the window shown or hidden: the timer pauses, and coming back asks again (only if the page is open).
    @discardableResult public func setAttentive(_ value: Bool) -> Task<Void, Never>? {
        guard value != attentive else { return nil }
        attentive = value
        guard value else {
            stopTimer()
            return nil
        }
        return visible ? start() : nil
    }

    /// Asks now and every minute after, while someone is looking; nothing until then.
    @discardableResult private func start() -> Task<Void, Never>? {
        guard attentive else { return nil }
        timer?.cancel()
        timer = Task { [store, sleep] in
            // a cancelled sleep throws and ends the loop; so does a cancel between the sleep and the ask
            while (try? await sleep(Self.interval)) != nil, Task.isCancelled == false { await store.load() }
        }
        return Task { await store.load() }
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    /// Check again.
    @discardableResult public func checkAgain() -> Task<Void, Never> { Task { await store.load(refresh: true) } }

    /// An epic stopped on a usage limit or a chat session said a quota ran out: the quotas the host kept are out of date, open page or not.
    @discardableResult public func limitHit() -> Task<Void, Never> { checkAgain() }
}
