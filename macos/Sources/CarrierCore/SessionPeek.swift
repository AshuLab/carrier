import Foundation

/// What the card that opens on a session's row in the sidebar says: who it is, the last thing the agent wrote and the facts of where it
/// works. The row has room for a title and a place; this is for a person who stopped to look.
public struct SessionPeek: Equatable {
    public typealias Fact = CardFact

    /// How the state in words is drawn, as the row's own words are: orange for what needs the person, green for a turn that ended unread.
    public enum Tone: Equatable { case quiet, working, attention, done }

    /// The whole title, which the row cuts.
    public var title: String
    /// The folder's name, the project's icon is made from it.
    public var name: String
    /// The state in words.
    public var subtitle: String
    public var tone: Tone
    /// What the agent last wrote, nil before it answered or when the host does not say.
    public var lastMessage: String?
    public var facts: [Fact]
    /// "updated 2 hours ago".
    public var timeline: String
}

public func sessionPeek(_ row: SessionRow, now: Date) -> SessionPeek {
    var facts = [SessionPeek.Fact(label: "Where", value: row.branch == nil ? "Base folder" : "Worktree")]
    if let branch = row.branch { facts.append(.init(label: "Branch", value: branch, kind: .branch)) }
    if row.folder.isEmpty == false { facts.append(.init(label: "Folder", value: (row.folder as NSString).abbreviatingWithTildeInPath, kind: .path)) }
    if row.agent.isEmpty == false { facts.append(.init(label: "Agent", value: row.agent, kind: .agent)) }
    if let model = TurnSummary(model: row.model).shortModel { facts.append(.init(label: "Model", value: model)) }
    if row.turns > 0 { facts.append(.init(label: "Turns", value: "\(row.turns)")) }
    // the words and the colour of the row: "Needs you" is orange and a finished turn the person has not opened says Done, in green
    let (subtitle, tone): (String, SessionPeek.Tone) = switch (row.state, row.status) {
    case (.waiting, _): ("Waiting for you", .attention)
    case (.working, _): ("Working…", .working)
    case (_, .unread): ("Done", .done)
    default: (row.status.title, .quiet)
    }
    return SessionPeek(
        title: row.title, name: row.workspace, subtitle: subtitle, tone: tone, lastMessage: row.lastMessage?.isEmpty == false ? row.lastMessage : nil,
        facts: facts, timeline: "updated \(spokenAge(row.updatedAt, now: now))"
    )
}
