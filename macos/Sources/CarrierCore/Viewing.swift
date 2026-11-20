import Foundation
import Observation

/// Whether anyone can see the app: it is in front (`focused`), its window is on screen but another app is in front (`visible`), its
/// window is closed, minimized or covered whole (`hidden`), or the screens, the Mac or the user's session are asleep (`asleep`).
public enum ViewingState: Sendable, Equatable { case focused, visible, hidden, asleep }

/// The one rule of how the three inputs combine: a sleeping Mac wins over everything, then the window being on screen, then the app being in front.
public func viewingState(appActive: Bool, windowShown: Bool, asleep: Bool) -> ViewingState {
    if asleep { return .asleep }
    if windowShown == false { return .hidden }
    return appActive ? .focused : .visible
}

/// What the app knows about whether someone looks at it, in one place, for views and models on the main actor to read (`PollPace` is the
/// copy for the threads that cannot). It is told by the window: nothing else decides who is looking.
@MainActor @Observable public final class Viewing {
    public static let shared = Viewing()

    public private(set) var state: ViewingState = .hidden
    /// The Mac is in Low Power Mode: work that nobody asked for waits longer.
    public private(set) var lowPower = false

    /// Someone can see the window, so a thing that only shows there has a reason to move.
    public var animates: Bool { state == .focused || state == .visible }

    public init() {}

    /// Takes the inputs. Observation notifies only when a value differs, so an update that changes nothing wakes no one; `PollPace` is cheap to set again.
    public func update(appActive: Bool, windowShown: Bool, asleep: Bool, lowPower: Bool, pace: PollPace = .shared) {
        let next = viewingState(appActive: appActive, windowShown: windowShown, asleep: asleep)
        state = next
        self.lowPower = lowPower
        pace.set(next, lowPower: lowPower)
    }
}

/// How long a conversation waits before it reads its session again, for who is looking and whether the agent is working: the turn's own
/// pace while someone can see it, a slow one for an idle session, and a growing one while the host does not answer (0.5 s, doubling, up to
/// 30). nil is a pause, which the caller waits at most `conversationPause`: a change of who is looking cuts it short.
public func conversationWait(state: ViewingState, turnRunning: Bool, failures: Int) -> TimeInterval? {
    guard state == .focused || state == .visible else { return nil }
    if failures > 0 { return min(0.5 * pow(2, Double(failures - 1)), 30) }
    if turnRunning { return conversationTurnWait }
    return state == .focused ? 2 : 5
}

/// How often a turn that is running is read, while someone can see it.
public let conversationTurnWait: TimeInterval = 0.25

/// The longest a conversation goes without asking while nobody looks: a wake-up that gets lost costs one ask every 30 seconds, and the chat
/// host, which closes a session that nobody asked about for a minute, still hears from the app.
public let conversationPause: TimeInterval = 30

/// Whether the menu bar icon's bar may bounce: the person left it on, the screens and the Mac are awake (nobody sees it otherwise) and it is not
/// Low Power Mode. Not about the window: the bounce is there to be seen with the window closed. It costs the window server about four points of a
/// core, measured, for a bar of four points.
public func iconAnimates(setting: Bool, state: ViewingState, lowPower: Bool) -> Bool { setting && state != .asleep && lowPower == false }
