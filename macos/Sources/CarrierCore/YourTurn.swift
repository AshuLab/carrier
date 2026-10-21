import Foundation

// The Overview's Your turn section as plain values (docs/specs/macos-app-redesign.md, story 14): what needs the person,
// in order, each with the link its action opens. The view maps them one to one.

public struct YourTurnItem: Equatable {
    public enum Kind: Equatable {
        case problem, needsYou, ready
    }

    public var kind: Kind
    /// "agent-forge #231"; "Carrier" for the engine's own problem.
    public var title: String
    public var detail: String
    /// Clicking the row selects this; nil for the engine problem.
    public var selection: Selection?
    /// Open issue (needs you). Only a web link survives `browserURL`.
    public var issueLink: URL?
    /// Open PR (ready).
    public var prLink: URL?
}

/// Order: the engine problem, then epics that need a person (most recent first), then finished epics in the snapshot's order.
/// Empty means nothing needs the person: the view shows `EmptyState.nothingNeedsYou`.
public func yourTurn(_ snapshot: PanelSnapshot) -> [YourTurnItem] {
    func name(_ repo: String, _ issue: Int) -> String { "\(repo.split(separator: "/").last.map(String.init) ?? repo) #\(issue)" }

    let problem = snapshot.problem.map {
        YourTurnItem(kind: .problem, title: "Carrier", detail: $0, selection: nil, issueLink: nil, prLink: nil)
    }
    // ponytail: recency is when the epic stopped, else its last activity, else its stage start; nothing better in the snapshot
    func stoppedAt(_ epic: PanelEpic) -> Int { epic.finishedAt ?? epic.lastActivityAt ?? epic.stageSince }
    let needsYou = snapshot.epics.filter { $0.status == .needsHuman }.sorted { stoppedAt($0) > stoppedAt($1) }.map { epic in
        var parts = [needsYouLine(epic)]
        if epic.blockers > 0 { parts.append("\(blockersLine(epic.blockers)) open") }
        parts.append(agoLine(stoppedAt(epic), now: snapshot.now))
        return YourTurnItem(
            kind: .needsYou, title: name(epic.repo, epic.issue), detail: parts.joined(separator: " · "),
            selection: .epic(repo: epic.repo, issue: epic.issue), issueLink: browserURL(epic.issueUrl), prLink: nil
        )
    }
    let ready = snapshot.done.map { done in
        var parts = ["Ready for test"]
        if let pr = done.prNumber { parts.append("PR #\(pr)") }
        parts.append(agoLine(done.finishedAt, now: snapshot.now))
        return YourTurnItem(
            kind: .ready, title: name(done.repo, done.issue), detail: parts.joined(separator: " · "),
            selection: .epic(repo: done.repo, issue: done.issue), issueLink: nil, prLink: donePullURL(done).flatMap(browserURL)
        )
    }
    return (problem.map { [$0] } ?? []) + needsYou + ready
}

/// The kind, capitalised, then the engine's own reason when it adds something; review limit also says the round.
private func needsYouLine(_ epic: PanelEpic) -> String {
    let kind = interventionLine(epic)
    var line = kind.prefix(1).uppercased() + kind.dropFirst()
    if epic.needsHumanKind == "review_limit", let round = epic.round { line += " (\(round)/\(epic.maxReviews))" }
    if epic.needsHumanKind != nil, let reason = epic.needsHumanReason, reason.isEmpty == false, reason.lowercased() != kind {
        line += " · \(reason)"
    }
    return line
}
