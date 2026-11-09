import Foundation

/// A notification to show: what happened and, when it is about one epic or one chat session, which. `isTest` is the one Settings sends: it shows
/// even while the window is in front. `sound` is whether its banner plays one.
public struct EpicNotification: Equatable {
    public var title: String
    public var body: String
    public var epic: EpicRef?
    public var session: String?
    public var isTest: Bool
    public var sound: Bool

    public init(title: String, body: String, epic: EpicRef? = nil, session: String? = nil, isTest: Bool = false, sound: Bool = true) {
        self.title = title
        self.body = body
        self.epic = epic
        self.session = session
        self.isTest = isTest
        self.sound = sound
    }
}

/// The kinds of notification, each with its switch in Settings (Notifications tab). A problem is off until the person asks.
public struct NotificationKinds: Equatable {
    public var needsYou: Bool
    public var readyForTest: Bool
    public var problem: Bool
    /// A chat session waits for an approval; on until turned off.
    public var chatNeedsAttention: Bool
    /// A chat session finished its turn; off until turned on.
    public var chatDone: Bool

    public init(needsYou: Bool = true, readyForTest: Bool = true, problem: Bool = false, chatNeedsAttention: Bool = true, chatDone: Bool = false) {
        self.needsYou = needsYou
        self.readyForTest = readyForTest
        self.problem = problem
        self.chatNeedsAttention = chatNeedsAttention
        self.chatDone = chatDone
    }
}

/// The notifications that `new` earns against `previous`, the chat sessions listed before and now: a live session that was working
/// and now waits for an approval (Needs attention) or is idle (Done). A session `previous` did not list, an archived one and any
/// other change say nothing; with no `previous` it only seeds. A kind whose switch is off in `kinds` is not notified.
public func chatNotifications(from previous: [SessionRow]?, to new: [SessionRow], kinds: NotificationKinds = NotificationKinds()) -> [EpicNotification] {
    guard let previous else { return [] }
    let before = Dictionary(previous.map { ($0.id, $0.state) }, uniquingKeysWith: { first, _ in first })
    return new.compactMap { row in
        guard row.archived == false, before[row.id] == .working else { return nil }
        switch row.state {
        case .waiting where kinds.chatNeedsAttention: return EpicNotification(title: "\(row.title) needs attention", body: "It waits for an approval", session: row.id)
        case .idle where kinds.chatDone: return EpicNotification(title: "\(row.title) is done", body: "The agent finished its turn", session: row.id)
        default: return nil
        }
    }
}

/// The notifications that `new` earns against `previous`: an epic that needs a person now and did not in `previous`, and one
/// that is in the ready-for-test list now and was not in `previous`'s. With no `previous` it only seeds: nothing is new yet.
/// A problem is the snapshot's own text when it appears or changes, and a watched repo that GitHub refuses now and did not
/// before; both compare with `previous`, so each is said once, until it goes away and comes back. A kind whose switch is off in
/// `kinds` is not notified.
public func notifications(from previous: PanelSnapshot?, to new: PanelSnapshot, kinds: NotificationKinds = NotificationKinds()) -> [EpicNotification] {
    guard let previous else { return [] }
    let neededAPerson = Set(previous.epics.filter { $0.status == .needsHuman }.map { EpicKey(repo: $0.repo, issue: $0.issue) })
    let wasReady = Set(previous.done.map { EpicKey(repo: $0.repo, issue: $0.issue) })

    let needsAPerson = new.epics
        .filter { $0.status == .needsHuman && neededAPerson.contains(EpicKey(repo: $0.repo, issue: $0.issue)) == false }
        .map { EpicNotification(title: "\($0.repo) #\($0.issue) needs attention", body: $0.needsHumanReason ?? "It stopped and waits for a person", epic: EpicRef(repo: $0.repo, issue: $0.issue)) }
    let ready = new.done
        .filter { wasReady.contains(EpicKey(repo: $0.repo, issue: $0.issue)) == false }
        .map { EpicNotification(title: "\($0.repo) #\($0.issue) is ready for test", body: $0.prNumber.map { "Pull request #\($0)" } ?? "Its work is done", epic: EpicRef(repo: $0.repo, issue: $0.issue)) }

    var problems: [EpicNotification] = []
    if let text = new.problem, text != previous.problem {
        problems.append(EpicNotification(title: "Carrier has a problem", body: text))
    }
    let refused = Set((previous.watched ?? []).filter { $0.ok == false }.map(\.repo))
    for watched in new.watched ?? [] where watched.ok == false && refused.contains(watched.repo) == false {
        problems.append(EpicNotification(title: "\(watched.repo) was refused by GitHub", body: watched.error ?? "GitHub refused it"))
    }
    return (kinds.needsYou ? needsAPerson : []) + (kinds.readyForTest ? ready : []) + (kinds.problem ? problems : [])
}

private struct EpicKey: Hashable {
    var repo: String
    var issue: Int
}

/// Where notifications go; the app's is the system's notification centre.
public protocol NotificationCentre {
    func post(_ notifications: [EpicNotification])
}

/// Turns the stream of states into notifications for a centre. It remembers the last snapshot; any state that is not a
/// running Carrier forgets it, so the first snapshot after Carrier was stopped and started again seeds like the first ever.
public final class NotificationWatcher {
    private let centre: NotificationCentre
    private let now: () -> Date
    /// Until when a stop is the app's own (Stop in the menu, the restart of a Settings tab); nil when none was asked for.
    private var expectedStopUntil: Date?
    /// Read on every snapshot, so a switch takes effect at once. An epic that changed while its switch was off is not notified
    /// when the switch goes on: the snapshot is remembered either way.
    private let kinds: () -> NotificationKinds
    private let sound: () -> Bool
    private var previous: PanelSnapshot?
    private var previousSessions: [SessionRow]?

    public init(
        centre: NotificationCentre, kinds: @escaping () -> NotificationKinds = { NotificationKinds() },
        sound: @escaping () -> Bool = { true }, now: @escaping () -> Date = Date.init
    ) {
        self.centre = centre
        self.kinds = kinds
        self.sound = sound
        self.now = now
    }

    /// Every banner plays a sound, or none does, as the switch says when it is posted.
    private func post(_ notifications: [EpicNotification]) {
        let sound = sound()
        centre.post(notifications.map { var made = $0; made.sound = sound; return made })
    }

    /// The app is about to stop Carrier itself: the stop that follows is not a problem. It lapses after `seconds`, so a stop
    /// that never happens does not hide a crash later.
    public func expectStop(for seconds: TimeInterval = 30) {
        expectedStopUntil = now().addingTimeInterval(seconds)
    }

    /// The chat sessions the host lists now, whether or not the window is open. The first list only seeds.
    public func react(toSessions sessions: [SessionRow]) {
        let due = chatNotifications(from: previousSessions, to: sessions, kinds: kinds())
        previousSessions = sessions
        if due.isEmpty == false { post(due) }
    }

    public func react(to state: ConnectionState) {
        guard case .running(let snapshot) = state else {
            if case .stopped = state, previous != nil {
                let asked = expectedStopUntil.map { now() < $0 } ?? false
                expectedStopUntil = nil
                if asked == false, kinds().problem {
                    post([EpicNotification(title: "Carrier stopped", body: "It stopped without being asked. Open the app to start it again.")])
                }
            }
            previous = nil
            return
        }
        let due = notifications(from: previous, to: snapshot, kinds: kinds())
        previous = snapshot
        if due.isEmpty == false { post(due) }
    }
}
