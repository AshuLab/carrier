import Foundation

// The Overview's Running section as plain values (docs/specs/macos-app-redesign.md, story 15): a card per running epic with
// its progress and one row per agent working on it, then a card for the free room. A slot has no identity in the engine, so
// the room is a count and never "slot 2". The views map these one to one.

public struct AgentRow: Equatable {
    /// "Claude", "Codex", "Antigravity".
    public var agent: String
    /// One letter for the avatar.
    public var initial: String
    /// "Builder" while shipping, "Reviewer", "Fixer".
    public var role: String
    /// "round 2/5" for review and fix; nil in ship, where the snapshot does not know the lane.
    public var round: String?
    /// The newest event of the session, or "working" when it has none.
    public var action: String
    /// "since 16:09" in local time.
    public var since: String
    /// The avatar's ring turns only while this is true.
    public var running: Bool
}

public struct RunningCard: Equatable {
    public var selection: Selection
    /// The epic's title, or "repo #issue" while the engine has none.
    public var title: String
    /// "owner/name · #issue".
    public var subtitle: String
    /// "3/5 slices" in ship, "round 2/5" otherwise, the stage when there is no count yet.
    public var progressLine: String
    /// 0...1; nil when there is nothing to count yet.
    public var progress: Double?
    /// What the progress bar counts: slices merged out of all, or the review round out of the most there can be.
    public var steps: Steps?
    public var agents: [AgentRow]

    public struct Steps: Equatable {
        public var done: Int
        public var total: Int
    }
}

public struct FreeRoom: Equatable {
    /// "1 free" or "All 3 in use".
    public var title: String
    /// "api #21 starts on the next check", "api #21 starts when one finishes" or "Nothing waiting".
    public var line: String
    /// False when every slot is taken.
    public var hasRoom = true
}

public struct RunningSection: Equatable {
    /// Empty means nothing runs: the view shows `EmptyState.idle`.
    public var cards: [RunningCard]
    public var room: FreeRoom
}

public func runningSection(_ snapshot: PanelSnapshot, timeZone: TimeZone = .current) -> RunningSection {
    let cards = snapshot.epics.filter { $0.status == .running }.map { epic in
        let sessions = (snapshot.sessions ?? []).filter { $0.repo == epic.repo && $0.issue == epic.issue }
        let header = epicHeader(.active(epic))
        let (line, progress, steps) = progress(epic)
        return RunningCard(
            selection: .epic(repo: epic.repo, issue: epic.issue), title: header.title, subtitle: header.subtitle,
            progressLine: line, progress: progress, steps: steps, agents: sessions.map { agentRow($0, epic: epic, timeZone: timeZone) }
        )
    }
    return RunningSection(cards: cards, room: freeRoom(snapshot))
}

/// ponytail: the role comes from the stage; the snapshot has one session per epic and no lane, so a ship row has no lane label.
func agentRow(_ session: PanelSnapshot.Session, epic: PanelEpic, timeZone: TimeZone = .current) -> AgentRow {
    let agent = agentName(session.harness)
    let clock = DateFormatter()
    (clock.dateFormat, clock.locale, clock.timeZone) = ("HH:mm", Locale(identifier: "en_US_POSIX"), timeZone)
    let action = session.last?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return AgentRow(
        agent: agent, initial: session.harness == "codex" ? "X" : String(agent.prefix(1)),
        role: ["ship": "Builder", "review": "Reviewer", "fix": "Fixer"][session.stage.rawValue] ?? session.stage.rawValue,
        round: session.round.map { "round \($0)/\(epic.maxReviews)" },
        action: action.isEmpty ? "working" : action,
        since: "since " + clock.string(from: Date(timeIntervalSince1970: Double(session.startedAt) / 1000)),
        running: epic.status == .running
    )
}

func agentName(_ harness: String) -> String {
    switch harness {
    case "claude": "Claude"
    case "codex": "Codex"
    case "agy": "Antigravity"
    default: harness.prefix(1).uppercased() + harness.dropFirst()
    }
}

/// Slices merged over total in ship, round over maximum rounds otherwise.
private func progress(_ epic: PanelEpic) -> (String, Double?, RunningCard.Steps?) {
    if epic.stage == .ship || epic.stage == nil {
        if let slices = epic.slices, let line = slicesLine(slices) {
            return (line, Double(slices.done) / Double(slices.total), .init(done: slices.done, total: slices.total))
        }
        return (epic.stage?.rawValue ?? "starting", nil, nil)
    }
    guard let round = epic.round, epic.maxReviews > 0 else { return (epic.stage?.rawValue ?? "starting", nil, nil) }
    return ("round \(round)/\(epic.maxReviews)", Double(round) / Double(epic.maxReviews), .init(done: round, total: epic.maxReviews))
}

private func freeRoom(_ snapshot: PanelSnapshot) -> FreeRoom {
    let (free, total) = (max(0, snapshot.slots.total - snapshot.slots.busy), snapshot.slots.total)
    let next = snapshot.queue.first.map { "\($0.repo.split(separator: "/").last.map(String.init) ?? $0.repo) #\($0.issue)" }
    let line = next.map { "\($0) starts " + (free > 0 ? "on the next check" : "when one finishes") } ?? "Nothing waiting"
    return FreeRoom(title: free > 0 ? "\(free) free" : "All \(total) in use", line: line, hasRoom: free > 0)
}
