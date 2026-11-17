import Foundation

/// What the card that opens on a session's row in the sidebar says: who it is, the last thing the agent wrote and the facts of where it
/// works. The row has room for a title and a place; this is for a person who stopped to look.
public struct SessionPeek: Equatable {
    public struct Fact: Equatable {
        public var label: String
        public var value: String
        /// A path or a branch, which the card sets in monospace.
        public var monospaced = false
    }

    /// How the state in words is tinted: the colours of the row (violet while it writes, cyan while it waits for what it started, orange when it
    /// waits for the person, green when it ended and was not opened).
    public enum Tone: Equatable { case working, background, waiting, done, quiet }

    /// The whole title, which the row cuts.
    public var title: String
    /// The folder's name, the project's icon is made from it.
    public var name: String
    /// The state in words.
    public var subtitle: String
    public var tone: Tone = .quiet
    /// What the agent last wrote, nil before it answered or when the host does not say.
    public var lastMessage: String?
    public var facts: [Fact]
    /// "updated 2 hours ago".
    public var timeline: String
    /// What the row's third line says, and more: the card shows the lines changed even for a session with no pull request.
    public var pullRequest: SessionPullRequest?
    public var diff: SessionDiff?
    /// What the agent waits for after its turn ended.
    public var background: [BackgroundTask] = []
}

public func sessionPeek(_ row: SessionRow, now: Date) -> SessionPeek {
    var facts = [SessionPeek.Fact(label: "Where", value: row.branch.map { "Worktree · \($0)" } ?? "Base folder", monospaced: row.branch != nil)]
    if row.folder.isEmpty == false { facts.append(.init(label: "Folder", value: (row.folder as NSString).abbreviatingWithTildeInPath, monospaced: true)) }
    if row.agent.isEmpty == false { facts.append(.init(label: "Agent", value: row.agent)) }
    if let model = TurnSummary(model: row.model).shortModel { facts.append(.init(label: "Model", value: model)) }
    if row.turns > 0 { facts.append(.init(label: "Turns", value: "\(row.turns)")) }
    let (subtitle, tone): (String, SessionPeek.Tone) = switch row.state {
    case .waiting: ("Waiting for you", .waiting)
    case .working: ("Working…", .working)
    case .idle, .done:
        if row.background.isEmpty == false { ("Waiting on background work…", .background) } else if row.status == .unread { ("Done", .done) } else { (row.status.title, .quiet) }
    }
    return SessionPeek(
        title: row.title, name: row.workspace, subtitle: subtitle, tone: tone, lastMessage: row.lastMessage?.isEmpty == false ? row.lastMessage : nil,
        facts: facts, timeline: "updated \(spokenAge(row.updatedAt, now: now))", pullRequest: row.pullRequest, diff: row.diff, background: row.background
    )
}
