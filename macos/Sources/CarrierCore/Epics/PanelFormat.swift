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
public func slicesLine(_ slices: PanelEpic.Slices?, bundle: Bundle? = nil, locale: Locale = .current) -> String? {
    guard let slices, slices.total > 0 else { return nil }
    return Copy.epicsSlicesLine(done: slices.done, total: slices.total, bundle: bundle, locale: locale)
}

/// "round 2/5"; nil before the first review.
public func roundLine(_ epic: PanelEpic, bundle: Bundle? = nil, locale: Locale = .current) -> String? {
    epic.round.map { Copy.epicsRoundLine(round: $0, max: epic.maxReviews, bundle: bundle, locale: locale) }
}

/// "ship", "review", "fix", or "starting" while the epic has no stage yet.
func stageName(_ stage: PanelEpic.Stage?, bundle: Bundle? = nil, locale: Locale = .current) -> String {
    switch stage {
    case .ship?: Copy.sidebarStageShip(bundle: bundle, locale: locale)
    case .review?: Copy.sidebarStageReview(bundle: bundle, locale: locale)
    case .fix?: Copy.sidebarStageFix(bundle: bundle, locale: locale)
    case nil: Copy.sidebarStageStarting(bundle: bundle, locale: locale)
    }
}

public func uptimeLine(_ snapshot: PanelSnapshot, bundle: Bundle? = nil, locale: Locale = .current) -> String {
    Copy.epicsUptime(duration: formatDuration(snapshot.now - snapshot.startedAt), bundle: bundle, locale: locale)
}

/// The Carrier home's toolbar subtitle: "5 repos · up 22m · next check in 3m".
public func overviewSubtitle(_ snapshot: PanelSnapshot, repos: Int, bundle: Bundle? = nil, locale: Locale = .current) -> String {
    [Copy.epicsRepos(count: repos, bundle: bundle, locale: locale), uptimeLine(snapshot, bundle: bundle, locale: locale), nextCheckLine(snapshot, bundle: bundle, locale: locale)]
        .joined(separator: " · ")
}

/// "in 3m", "checking now" or "starting": what the Carrier box says beside its Next check label.
public func nextCheckValue(_ snapshot: PanelSnapshot, bundle: Bundle? = nil, locale: Locale = .current) -> String {
    guard let at = snapshot.nextCheckAt else { return Copy.epicsNextCheckStarting(bundle: bundle, locale: locale) }
    return at <= snapshot.now ? Copy.epicsNextCheckNow(bundle: bundle, locale: locale) : Copy.epicsNextCheckIn(duration: formatDuration(at - snapshot.now), bundle: bundle, locale: locale)
}

/// "next check in 3m", "checking now" or "starting".
public func nextCheckLine(_ snapshot: PanelSnapshot, bundle: Bundle? = nil, locale: Locale = .current) -> String {
    guard let at = snapshot.nextCheckAt, at > snapshot.now else { return nextCheckValue(snapshot, bundle: bundle, locale: locale) }
    return Copy.epicsNextCheckLine(duration: formatDuration(at - snapshot.now), bundle: bundle, locale: locale)
}

/// "2m 05s ago", or the time of the event when Time format is clock; "a while ago" when the engine has no time.
public func agoLine(_ at: Int?, now: Int, time: TimeFormat = .stored(), bundle: Bundle? = nil, locale: Locale = .current) -> String {
    at.map { agoText($0, now: now, format: time) } ?? Copy.epicsAgoUnknown(bundle: bundle, locale: locale)
}

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
