import Foundation
import Synchronization

/// How often the app asks the chat host and the engine how things are. While the person is looking (the app is active and its window is
/// on screen) every 2 seconds, so a change shows within a moment; otherwise every 5 seconds, which is still prompt for a notification
/// (a session that waits for the person) and a fifth of what it was. Never above a minute: the chat host closes a session that nobody has
/// asked after a minute, and the app asking is what keeps the open ones awake (`clientJoined` in the host).
public final class PollPace: Sendable {
    public static let shared = PollPace()
    public static let attentiveSeconds: TimeInterval = 2
    public static let backgroundSeconds: TimeInterval = 5

    private let attentive = Mutex(false)

    public init() {}

    /// Called from the main thread when the app becomes or stops being active, and when its window shows, hides or closes.
    public func set(attentive value: Bool) { attentive.withLock { $0 = value } }

    /// The wait before the next ask.
    public var seconds: TimeInterval { attentive.withLock { $0 } ? Self.attentiveSeconds : Self.backgroundSeconds }
}
