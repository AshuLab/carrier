import Foundation

/// A notification to show: what happened and, when it is about one epic, which. `isTest` is the one Settings sends: it shows
/// even while the window is in front. `sound` is whether its banner plays one. `quiet` is posted inside the quiet hours: no
/// banner and no sound, it waits in the Notification Center.
public struct EpicNotification: Equatable {
    public var title: String
    public var body: String
    public var epic: EpicRef?
    public var isTest: Bool
    public var sound: Bool
    public var quiet: Bool

    public init(title: String, body: String, epic: EpicRef? = nil, isTest: Bool = false, sound: Bool = true, quiet: Bool = false) {
        self.title = title
        self.body = body
        self.epic = epic
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

    public init(needsYou: Bool = true, readyForTest: Bool = true, problem: Bool = false) {
        self.needsYou = needsYou
        self.readyForTest = readyForTest
        self.problem = problem
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
    private let quietHours: () -> QuietHours
    private var previous: PanelSnapshot?

    public init(
        centre: NotificationCentre, kinds: @escaping () -> NotificationKinds = { NotificationKinds() },
        sound: @escaping () -> Bool = { true }, quietHours: @escaping () -> QuietHours = { QuietHours() },
        now: @escaping () -> Date = Date.init
    ) {
        self.centre = centre
        self.kinds = kinds
        self.sound = sound
        self.quietHours = quietHours
        self.now = now
    }

    /// Every banner plays a sound, or none does, as the switch says when it is posted; inside the quiet hours all are quiet and
    /// none plays one.
    private func post(_ notifications: [EpicNotification]) {
        let quiet = quietHours().contains(now())
        let sound = sound() && quiet == false
        centre.post(notifications.map { var made = $0; made.sound = sound; made.quiet = quiet; return made })
    }

    /// The app is about to stop Carrier itself: the stop that follows is not a problem. It lapses after `seconds`, so a stop
    /// that never happens does not hide a crash later.
    public func expectStop(for seconds: TimeInterval = 30) {
        expectedStopUntil = now().addingTimeInterval(seconds)
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
