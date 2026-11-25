import Foundation

// The Carrier home's Running section as plain values (docs/specs/macos-app-redesign.md, story 15): a card per running epic with
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

public func runningSection(_ snapshot: PanelSnapshot, time: TimeFormat = .stored(), bundle: Bundle? = nil, locale: Locale = .current) -> RunningSection {
    let cards = snapshot.epics.filter { $0.status == .running }.map { epic in
        let sessions = (snapshot.sessions ?? []).filter { $0.repo == epic.repo && $0.issue == epic.issue }
        let header = epicHeader(.active(epic), bundle: bundle, locale: locale)
        let (line, progress, steps) = progress(epic, bundle: bundle, locale: locale)
        return RunningCard(
            selection: .epic(repo: epic.repo, issue: epic.issue), title: header.title, subtitle: header.subtitle,
            progressLine: line, progress: progress, steps: steps, agents: sessions.map { agentRow($0, epic: epic, time: time, bundle: bundle, locale: locale) }
        )
    }
    return RunningSection(cards: cards, room: freeRoom(snapshot, bundle: bundle, locale: locale))
}

/// ponytail: the role comes from the stage; the snapshot has a session for each running execution of an epic (an epic with several reviewers has several) and no lane, so a ship row has no lane label.
func agentRow(_ session: PanelSnapshot.Session, epic: PanelEpic, time: TimeFormat = .stored(), bundle: Bundle? = nil, locale: Locale = .current) -> AgentRow {
    let agent = agentName(session.harness)
    let action = session.last?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let role = switch session.stage {
    case .ship: Copy.sessionRoleShip(bundle: bundle, locale: locale)
    case .review: Copy.sessionRoleReview(bundle: bundle, locale: locale)
    case .fix: Copy.sessionRoleFix(bundle: bundle, locale: locale)
    }
    return AgentRow(
        agent: agent, initial: session.harness == "codex" ? "X" : String(agent.prefix(1)),
        role: role,
        round: session.round.map { Copy.epicsRoundLine(round: $0, max: epic.maxReviews, bundle: bundle, locale: locale) },
        action: action.isEmpty ? Copy.epicsWorking(bundle: bundle, locale: locale) : action,
        since: Copy.epicsSince(time: clockTime(session.startedAt, time: time), bundle: bundle, locale: locale),
        running: epic.status == .running
    )
}

func agentName(_ harness: String) -> String {
    switch harness {
    case "claude": "Claude"
    case "codex": "Codex"
    case "agy": "Antigravity"
    default: capitalizingFirst(harness)
    }
}

/// Slices merged over total in ship, round over maximum rounds otherwise.
private func progress(_ epic: PanelEpic, bundle: Bundle?, locale: Locale) -> (String, Double?, RunningCard.Steps?) {
    if epic.stage == .ship || epic.stage == nil {
        if let slices = epic.slices, let line = slicesLine(slices, bundle: bundle, locale: locale) {
            return (line, Double(slices.done) / Double(slices.total), .init(done: slices.done, total: slices.total))
        }
        return (stageName(epic.stage, bundle: bundle, locale: locale), nil, nil)
    }
    guard let round = epic.round, epic.maxReviews > 0 else { return (stageName(epic.stage, bundle: bundle, locale: locale), nil, nil) }
    return (
        Copy.epicsRoundLine(round: round, max: epic.maxReviews, bundle: bundle, locale: locale), Double(round) / Double(epic.maxReviews),
        .init(done: round, total: epic.maxReviews)
    )
}

private func freeRoom(_ snapshot: PanelSnapshot, bundle: Bundle?, locale: Locale) -> FreeRoom {
    let (free, total) = (max(0, snapshot.slots.total - snapshot.slots.busy), snapshot.slots.total)
    let next = snapshot.queue.first.map { "\($0.repo.split(separator: "/").last.map(String.init) ?? $0.repo) #\($0.issue)" }
    let line = next.map { free > 0 ? Copy.epicsRoomStartsNext(name: $0, bundle: bundle, locale: locale) : Copy.epicsRoomStartsWhenFree(name: $0, bundle: bundle, locale: locale) }
        ?? Copy.epicsRoomNothing(bundle: bundle, locale: locale)
    let title = free > 0 ? Copy.epicsRoomFree(count: free, bundle: bundle, locale: locale) : Copy.epicsRoomAllUsed(total: total, bundle: bundle, locale: locale)
    return FreeRoom(title: title, line: line, hasRoom: free > 0)
}
