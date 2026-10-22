/// A notification to show: which epic, and what happened.
public struct EpicNotification: Equatable {
    public var title: String
    public var body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

/// The two kinds of notification, each with its switch in Settings (Notifications tab).
public struct NotificationKinds: Equatable {
    public var needsYou: Bool
    public var readyForTest: Bool

    public init(needsYou: Bool = true, readyForTest: Bool = true) {
        self.needsYou = needsYou
        self.readyForTest = readyForTest
    }
}

/// The notifications that `new` earns against `previous`: an epic that needs a person now and did not in `previous`, and one
/// that is in the ready-for-test list now and was not in `previous`'s. With no `previous` it only seeds: nothing is new yet.
/// A kind whose switch is off in `kinds` is not notified.
public func notifications(from previous: PanelSnapshot?, to new: PanelSnapshot, kinds: NotificationKinds = NotificationKinds()) -> [EpicNotification] {
    guard let previous else { return [] }
    let neededAPerson = Set(previous.epics.filter { $0.status == .needsHuman }.map { EpicKey(repo: $0.repo, issue: $0.issue) })
    let wasReady = Set(previous.done.map { EpicKey(repo: $0.repo, issue: $0.issue) })

    let needsAPerson = new.epics
        .filter { $0.status == .needsHuman && neededAPerson.contains(EpicKey(repo: $0.repo, issue: $0.issue)) == false }
        .map { EpicNotification(title: "\($0.repo) #\($0.issue) needs you", body: $0.needsHumanReason ?? "It stopped and waits for a person") }
    let ready = new.done
        .filter { wasReady.contains(EpicKey(repo: $0.repo, issue: $0.issue)) == false }
        .map { EpicNotification(title: "\($0.repo) #\($0.issue) is ready for test", body: $0.prNumber.map { "Pull request #\($0)" } ?? "Its work is done") }
    return (kinds.needsYou ? needsAPerson : []) + (kinds.readyForTest ? ready : [])
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
    /// Read on every snapshot, so a switch takes effect at once. An epic that changed while its switch was off is not notified
    /// when the switch goes on: the snapshot is remembered either way.
    private let kinds: () -> NotificationKinds
    private var previous: PanelSnapshot?

    public init(centre: NotificationCentre, kinds: @escaping () -> NotificationKinds = { NotificationKinds() }) {
        self.centre = centre
        self.kinds = kinds
    }

    public func react(to state: ConnectionState) {
        guard case .running(let snapshot) = state else {
            previous = nil
            return
        }
        let due = notifications(from: previous, to: snapshot, kinds: kinds())
        previous = snapshot
        if due.isEmpty == false { centre.post(due) }
    }
}
