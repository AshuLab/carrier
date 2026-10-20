/// A notification to show: which epic, and what happened.
public struct EpicNotification: Equatable {
    public var title: String
    public var body: String
}

/// The notifications that `new` earns against `previous`: an epic that needs a person now and did not in `previous`, and one
/// that is in the ready-for-test list now and was not in `previous`'s. With no `previous` it only seeds: nothing is new yet.
public func notifications(from previous: PanelSnapshot?, to new: PanelSnapshot) -> [EpicNotification] {
    guard let previous else { return [] }
    let neededAPerson = Set(previous.epics.filter { $0.status == .needsHuman }.map { EpicKey(repo: $0.repo, issue: $0.issue) })
    let wasReady = Set(previous.done.map { EpicKey(repo: $0.repo, issue: $0.issue) })

    let needsAPerson = new.epics
        .filter { $0.status == .needsHuman && neededAPerson.contains(EpicKey(repo: $0.repo, issue: $0.issue)) == false }
        .map { EpicNotification(title: "\($0.repo) #\($0.issue) needs you", body: $0.needsHumanReason ?? "It stopped and waits for a person") }
    let ready = new.done
        .filter { wasReady.contains(EpicKey(repo: $0.repo, issue: $0.issue)) == false }
        .map { EpicNotification(title: "\($0.repo) #\($0.issue) is ready for test", body: $0.prNumber.map { "Pull request #\($0)" } ?? "Its work is done") }
    return needsAPerson + ready
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
    private var previous: PanelSnapshot?

    public init(centre: NotificationCentre) {
        self.centre = centre
    }

    public func react(to state: ConnectionState) {
        guard case .running(let snapshot) = state else {
            previous = nil
            return
        }
        let due = notifications(from: previous, to: snapshot)
        previous = snapshot
        if due.isEmpty == false { centre.post(due) }
    }
}
