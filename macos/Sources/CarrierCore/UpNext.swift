import Foundation

// The Overview's Up next section as plain values: the epics waiting for a slot, in line, each opening its epic view.

public struct UpNextRow: Equatable {
    public var selection: Selection
    /// The epic's title, or "repo #issue" while the engine has none.
    public var title: String
    /// "1st in queue · waiting 12m 05s"; the wait is left out when the engine has no time.
    public var line: String
}

public func upNext(_ snapshot: PanelSnapshot) -> [UpNextRow] {
    snapshot.queue.enumerated().map { index, epic in
        let header = epicHeader(.queued(epic, position: index + 1))
        let waiting = epic.queuedAt.map { " · waiting \(formatDuration(snapshot.now - $0))" } ?? ""
        return UpNextRow(selection: .epic(repo: epic.repo, issue: epic.issue), title: header.title, line: "\(ordinal(index + 1)) in queue\(waiting)")
    }
}
