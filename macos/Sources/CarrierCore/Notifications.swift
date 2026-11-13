import Foundation

/// A notification to show: what happened and, when it is about one epic or one chat session, which. `isTest` is the one Settings sends: it shows
/// even while the window is in front. `sound` is whether its banner plays one. `quiet` is posted inside the quiet hours: no
/// banner and no sound, it waits in the Notification Center.
public struct EpicNotification: Equatable {
    public var title: String
    public var body: String
    public var epic: EpicRef?
    public var session: String?
    public var isTest: Bool
    public var sound: Bool
    public var quiet: Bool

    public init(title: String, body: String, epic: EpicRef? = nil, session: String? = nil, isTest: Bool = false, sound: Bool = true, quiet: Bool = false) {
        self.title = title
        self.body = body
        self.epic = epic
        self.session = session
        self.isTest = isTest
        self.sound = sound
        self.quiet = quiet
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

private func needsAttention(_ epic: PanelEpic) -> EpicNotification {
    EpicNotification(title: "\(epic.repo) #\(epic.issue) needs attention", body: epic.needsHumanReason ?? "It stopped and waits for a person", epic: EpicRef(repo: epic.repo, issue: epic.issue))
}

private func needsAttention(_ row: SessionRow) -> EpicNotification {
    EpicNotification(title: "\(row.title) needs attention", body: "It waits for an approval", session: row.id)
}

/// How long a Needs attention waits before it notifies again; the person's choice in Settings.
public enum ReminderInterval: Int, CaseIterable {
    case never = 0, quarterHour = 900, hour = 3600

    public var title: String {
        switch self {
        case .never: "Never"
        case .quarterHour: "After 15 minutes"
        case .hour: "After an hour"
        }
    }
}

/// Which of the items that still need attention (an epic or a session, by key) are due a reminder at `now`: those whose last
/// notification is at least `every` old. An item with no last notification yet is not due (its first one is still to come), one
/// that is not in `needing` any more is not either, and with `.never` nothing is.
public func remindersDue(needing: Set<String>, lastNotified: [String: Date], every: ReminderInterval, now: Date) -> [String] {
    guard every != .never else { return [] }
    return needing.filter { key in lastNotified[key].map { now.timeIntervalSince($0) >= TimeInterval(every.rawValue) } ?? false }.sorted()
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
        case .waiting where kinds.chatNeedsAttention: return needsAttention(row)
        case .idle where kinds.chatDone: return EpicNotification(title: "\(row.title) is done", body: "The agent finished its turn", session: row.id)
        default: return nil
        }
    }
}

/// What the Dock icon counts: the epics that need a person plus the live chat sessions waiting for an approval. No snapshot (Carrier
/// not running) counts no epics.
public func dockBadgeCount(snapshot: PanelSnapshot?, sessions: [SessionRow]) -> Int {
    (snapshot?.epics.filter { $0.status == .needsHuman }.count ?? 0) + sessions.filter { $0.state == .waiting && $0.archived == false }.count
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
        .map(needsAttention)
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
    /// Until when a stop is the app's own (Stop in the menu, the start of the chat host); nil when none was asked for.
    private var expectedStopUntil: Date?
    /// Read on every snapshot, so a switch takes effect at once. An epic that changed while its switch was off is not notified
    /// when the switch goes on: the snapshot is remembered either way.
    private let kinds: () -> NotificationKinds
    private let sound: () -> Bool
    private let quietHours: () -> QuietHours
    private let showsBadge: () -> Bool
    private let setBadge: (Int) -> Void
    private let reminder: () -> ReminderInterval
    private var previous: PanelSnapshot?
    private var previousSessions: [SessionRow]?
    /// When each item that needs attention (by key) last notified, or was first seen needing it.
    private var lastNotified: [String: Date] = [:]

    public init(
        centre: NotificationCentre, kinds: @escaping () -> NotificationKinds = { NotificationKinds() },
        sound: @escaping () -> Bool = { true }, quietHours: @escaping () -> QuietHours = { QuietHours() },
        showsBadge: @escaping () -> Bool = { true }, setBadge: @escaping (Int) -> Void = { _ in },
        reminder: @escaping () -> ReminderInterval = { .never }, now: @escaping () -> Date = Date.init
    ) {
        self.centre = centre
        self.kinds = kinds
        self.sound = sound
        self.quietHours = quietHours
        self.showsBadge = showsBadge
        self.setBadge = setBadge
        self.reminder = reminder
        self.now = now
    }

    /// Every banner plays a sound, or none does, as the switch says when it is posted; inside the quiet hours all are quiet and
    /// none plays one.
    private func post(_ notifications: [EpicNotification]) {
        let quiet = quietHours().contains(now())
        let sound = sound() && quiet == false
        centre.post(notifications.map { var made = $0; made.sound = sound; made.quiet = quiet; return made })
    }

    /// The Dock badge: the count of what the two last states hold, or none while the switch is off. Also called when the switch changes.
    public func refreshBadge() {
        setBadge(showsBadge() ? dockBadgeCount(snapshot: previous, sessions: previousSessions ?? []) : 0)
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
        refreshBadge()
        if due.isEmpty == false { post(due) }
        track()
    }

    /// What still needs attention now, by key, for the kinds that are switched on.
    private func needing() -> [String: EpicNotification] {
        let kinds = kinds()
        var found: [String: EpicNotification] = [:]
        if kinds.needsYou {
            for epic in previous?.epics ?? [] where epic.status == .needsHuman { found["epic \(epic.repo)#\(epic.issue)"] = needsAttention(epic) }
        }
        if kinds.chatNeedsAttention {
            for row in previousSessions ?? [] where row.state == .waiting && row.archived == false { found["session \(row.id)"] = needsAttention(row) }
        }
        return found
    }

    /// Forgets what stopped needing attention and starts the clock of what began to: the original notification, when there was
    /// one, is posted in the same call.
    private func track() {
        let needing = needing()
        lastNotified = lastNotified.filter { needing[$0.key] != nil }
        for key in needing.keys where lastNotified[key] == nil { lastNotified[key] = now() }
    }

    /// Called by the app's timer: notifies again, as the original would be, whatever still needs attention for the interval.
    public func remind() {
        track()
        let needing = needing()
        let due = remindersDue(needing: Set(needing.keys), lastNotified: lastNotified, every: reminder(), now: now())
        guard due.isEmpty == false else { return }
        for key in due { lastNotified[key] = now() }
        post(due.compactMap { needing[$0] })
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
            refreshBadge()
            track()
            return
        }
        let due = notifications(from: previous, to: snapshot, kinds: kinds())
        previous = snapshot
        refreshBadge()
        if due.isEmpty == false { post(due) }
        track()
    }
}
