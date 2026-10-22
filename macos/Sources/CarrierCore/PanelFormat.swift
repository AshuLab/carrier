import Foundation

// What the window writes about a snapshot, the same wording as the terminal panel (src/terminal/dashboard/dashboard.ts).
// Times are ms since epoch; `now` is the snapshot's own clock.

/// "45s", "3m", "2h 03m", "1d 4h": seconds only under a minute, so a counter on screen changes once a minute from then on.
public func formatDuration(_ ms: Int) -> String {
    let s = max(0, ms) / 1000
    let (d, h, m) = (s / 86_400, s % 86_400 / 3600, s % 3600 / 60)
    if d > 0 { return "\(d)d \(h)h" }
    if h > 0 { return "\(h)h \(String(format: "%02d", m))m" }
    if m > 0 { return "\(m)m" }
    return "\(s)s"
}

public struct StageStep: Equatable {
    public var name: String
    public var current: Bool
}

/// ship, review, fix with the current one marked; none is marked while the epic has no stage yet.
public func stageChain(_ stage: PanelEpic.Stage?) -> [StageStep] {
    [PanelEpic.Stage.ship, .review, .fix].map { StageStep(name: $0.rawValue, current: $0 == stage) }
}

/// "3/5 slices"; nil when the epic has no count or no slices.
public func slicesLine(_ slices: PanelEpic.Slices?) -> String? {
    guard let slices, slices.total > 0 else { return nil }
    return "\(slices.done)/\(slices.total) slices"
}

/// "round 2/5"; nil before the first review.
public func roundLine(_ epic: PanelEpic) -> String? {
    epic.round.map { "round \($0)/\(epic.maxReviews)" }
}

public func blockersLine(_ blockers: Int) -> String { "\(blockers) \(blockers == 1 ? "blocker" : "blockers")" }

public func stageTimeLine(_ epic: PanelEpic, now: Int) -> String { "\(formatDuration(now - epic.stageSince)) in stage" }

public func activityLine(_ epic: PanelEpic, now: Int) -> String {
    epic.lastActivityAt.map { "active \(formatDuration(now - $0)) ago" } ?? "no activity yet"
}

public func uptimeLine(_ snapshot: PanelSnapshot) -> String { "up \(formatDuration(snapshot.now - snapshot.startedAt))" }

public func reposLine(_ repos: Int) -> String { "watching \(repos) \(repos == 1 ? "repo" : "repos")" }

/// The Overview's toolbar subtitle: "5 repos · up 22m · next check in 3m".
public func overviewSubtitle(_ snapshot: PanelSnapshot, repos: Int) -> String {
    ["\(repos) \(repos == 1 ? "repo" : "repos")", uptimeLine(snapshot), nextCheckLine(snapshot)].joined(separator: " · ")
}

public func nextCheckLine(_ snapshot: PanelSnapshot) -> String {
    guard let at = snapshot.nextCheckAt else { return "starting" }
    return at <= snapshot.now ? "checking now" : "next check in \(formatDuration(at - snapshot.now))"
}

/// "2m 05s ago"; "a while ago" when the engine has no time.
public func agoLine(_ at: Int?, now: Int) -> String { at.map { "\(formatDuration(now - $0)) ago" } ?? "a while ago" }

/// A link from the engine as a URL the browser may open: https or http only.
public func browserURL(_ string: String) -> URL? {
    guard let url = URL(string: string), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return nil }
    return url
}

/// The finished epic's links; the snapshot gives the repo ("owner/name") and the numbers, GitHub is where they live.
public func doneIssueURL(_ done: PanelSnapshot.DoneEpic) -> String { "https://github.com/\(done.repo)/issues/\(done.issue)" }

public func donePullURL(_ done: PanelSnapshot.DoneEpic) -> String? {
    done.prNumber.map { "https://github.com/\(done.repo)/pull/\($0)" }
}
