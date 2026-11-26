import Foundation

/// What the card that opens on a session's row in the sidebar says: who it is, the last thing the agent wrote and the facts of where it
/// works. The row has room for a title and a place; this is for a person who stopped to look.
public struct SessionPeek: Equatable {
    public typealias Fact = CardFact

    /// How the state in words is tinted: the colours of the row (violet while it writes, cyan while it waits for what it started, orange when it
    /// waits for the person, green when it ended and was not opened).
    public enum Tone: Equatable { case quiet, working, background, attention, done }

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
    /// What the row's third line says, and more: the card shows the lines changed even for a session with no pull request.
    public var pullRequest: SessionPullRequest?
    public var diff: SessionDiff?
    /// What the agent waits for after its turn ended: its own work (a subagent, a workflow).
    public var background: [BackgroundTask] = []
    /// What runs in the background without the model: a command, a monitor, a dev server. Said apart from the state, not in the tone of work.
    public var processes: [BackgroundTask] = []
    /// The folder the session is grouped under: the project's tile is looked up by it.
    public var base = ""
}

public func sessionPeek(_ row: SessionRow, now: Date, bundle: Bundle? = nil, locale: Locale = .current) -> SessionPeek {
    let place = row.branch == nil ? Copy.sessionBaseFolder(bundle: bundle, locale: locale) : Copy.chatPeekWorktreeOf(workspace: row.workspace, bundle: bundle, locale: locale)
    var facts = [SessionPeek.Fact(label: Copy.chatPeekWhere(bundle: bundle, locale: locale), value: place)]
    if let branch = row.branch {
        let cut = row.branchFrom.flatMap { $0.isEmpty ? nil : Copy.chatPeekCutFrom(branch: $0, bundle: bundle, locale: locale) }
        facts.append(.init(label: Copy.chatPeekBranch(bundle: bundle, locale: locale), value: branch, kind: .branch, detail: cut))
    }
    if row.folder.isEmpty == false {
        let path = (row.folder as NSString).abbreviatingWithTildeInPath
        // a worktree is told by its folder's name, with the whole path under it; a base folder is its own path
        let folder = Copy.chatPeekFolder(bundle: bundle, locale: locale)
        facts.append(row.branch == nil ? .init(label: folder, value: path, kind: .path) : .init(label: folder, value: worktreeFolderName(row), kind: .path, detail: path))
    }
    if row.agent.isEmpty == false { facts.append(.init(label: Copy.chatPeekAgent(bundle: bundle, locale: locale), value: row.agent, kind: .agent)) }
    if let model = TurnSummary(model: row.model).shortModel { facts.append(.init(label: Copy.chatPeekModel(bundle: bundle, locale: locale), value: model)) }
    if row.turns > 0 { facts.append(.init(label: Copy.chatPeekTurns(bundle: bundle, locale: locale), value: "\(row.turns)")) }
    // the words and the colour of the row: "Needs you" is orange, a turn that ended with the agent still waiting for what it started is cyan,
    // and a finished turn the person has not opened says Done, in green
    let (subtitle, tone): (String, SessionPeek.Tone) = switch (row.state, row.status) {
    case (.waiting, _): (Copy.sessionWaitingForYou(bundle: bundle, locale: locale), .attention)
    case (.working, _): (Copy.sessionWorking(bundle: bundle, locale: locale), .working)
    case (_, .working): (Copy.chatPeekWaitingBackground(bundle: bundle, locale: locale), .background)
    case (_, .unread): (Copy.sessionDone(bundle: bundle, locale: locale), .done)
    default: (row.status.title(bundle: bundle, locale: locale), .quiet)
    }
    return SessionPeek(
        title: row.title, name: row.workspace, subtitle: subtitle, tone: tone, lastMessage: row.lastMessage?.isEmpty == false ? row.lastMessage : nil,
        facts: facts, timeline: Copy.chatPeekUpdated(age: spokenAge(row.updatedAt, now: now, locale: locale), bundle: bundle, locale: locale), pullRequest: row.pullRequest, diff: row.diff, background: row.background.filter(\.agentWork), processes: row.processes, base: row.base
    )
}
