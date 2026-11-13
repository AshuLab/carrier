import Foundation

/// When the Usage page asks the host again (docs/specs/usage-and-limits.md): as it appears, as the app becomes active while it is open, on a
/// Check again, when an epic or a chat session hits a usage limit, and every minute while it is on screen. The host keeps quotas for a minute,
/// so only a Check again and a limit that was hit skip its cache (`refresh`).
@MainActor public final class UsageRefresher {
    public static let interval = Duration.seconds(60)

    private let store: UsageStore
    private let sleep: @Sendable (Duration) async throws -> Void
    private var timer: Task<Void, Never>?
    public private(set) var visible = false

    /// Whether the minute timer is running: only between `appear` and `disappear`.
    public var isTimerRunning: Bool { timer != nil }

    public init(store: UsageStore, sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.store = store
        self.sleep = sleep
    }

    public func appear() {
        visible = true
        Task { await store.load() }
        timer?.cancel()
        timer = Task { [store, sleep] in
            // a cancelled sleep throws and ends the loop; so does a cancel between the sleep and the ask
            while (try? await sleep(Self.interval)) != nil, Task.isCancelled == false { await store.load() }
        }
    }

    public func disappear() {
        visible = false
        timer?.cancel()
        timer = nil
    }

    /// The app became active: asked again only if the page is open.
    @discardableResult public func appBecameActive() -> Task<Void, Never>? {
        guard visible else { return nil }
        return Task { await store.load() }
    }

    /// Check again.
    @discardableResult public func checkAgain() -> Task<Void, Never> { Task { await store.load(refresh: true) } }

    /// An epic stopped on a usage limit or a chat session said a quota ran out: the quotas the host kept are out of date, open page or not.
    @discardableResult public func limitHit() -> Task<Void, Never> { checkAgain() }
}
