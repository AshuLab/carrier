import Foundation

/// What the card that opens on a session's row in the sidebar says: who it is, the last thing the agent wrote and the facts of where it
/// works. The row has room for a title and a place; this is for a person who stopped to look.
public struct SessionPeek: Equatable {
    public struct Fact: Equatable {
        public var label: String
        public var value: String
    }

    /// The whole title, which the row cuts.
    public var title: String
    /// The folder's name, the project's icon is made from it.
    public var name: String
    /// The state in words.
    public var subtitle: String
    /// What the agent last wrote, nil before it answered or when the host does not say.
    public var lastMessage: String?
    public var facts: [Fact]
    /// "updated 2 hours ago".
    public var timeline: String
}

public func sessionPeek(_ row: SessionRow, now: Date) -> SessionPeek {
    var facts = [SessionPeek.Fact(label: "Where", value: row.branch.map { "Worktree · \($0)" } ?? "Base folder")]
    if row.folder.isEmpty == false { facts.append(.init(label: "Folder", value: (row.folder as NSString).abbreviatingWithTildeInPath)) }
    if row.agent.isEmpty == false { facts.append(.init(label: "Agent", value: row.agent)) }
    if let model = TurnSummary(model: row.model).shortModel { facts.append(.init(label: "Model", value: model)) }
    if row.turns > 0 { facts.append(.init(label: "Turns", value: "\(row.turns)")) }
    let subtitle: String = switch row.state {
    case .waiting: "Waiting for you"
    case .working: "Working…"
    case .idle, .done: row.status.title
    }
    return SessionPeek(
        title: row.title, name: row.workspace, subtitle: subtitle, lastMessage: row.lastMessage?.isEmpty == false ? row.lastMessage : nil,
        facts: facts, timeline: "updated \(spokenAge(row.updatedAt, now: now))"
    )
}
