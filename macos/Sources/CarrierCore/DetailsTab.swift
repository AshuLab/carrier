import Foundation

// The Details tab as plain values: four groups of rows, Timing, Progress, Pull request and Run
// (docs/specs/macos-app-redesign.md, story 29). The views map them one to one. A value the engine did not send is a dash,
// never a guess; an older engine that sends none of the new fields gets the rows the snapshot alone can fill.

public struct DetailsRow: Equatable {
    public enum Tone: Equatable { case normal, good, attention, bad, dim }
    /// How the value is drawn: plain text, or a badge (a coloured capsule; the accent colour with an arrow when it has a `url`).
    public enum Style: Equatable { case text, badge }

    public var label: String
    /// The small line under the label.
    public var note: String?
    public var value: String
    public var tone: Tone = .normal
    public var style: Style = .text
    /// Where the value goes when it is clicked: the pull request, its checks, the branch, the repository.
    public var url: String?

    static let dash = "—"
}

public struct DetailsGroup: Equatable {
    public var title: String
    public var rows: [DetailsRow]
}

public struct DetailsTabModel: Equatable {
    public var groups: [DetailsGroup]
}

public func detailsTab(_ subject: EpicSubject?, reply: EpicReply?, now: Int, timeZone: TimeZone = .current) -> DetailsTabModel {
    guard let subject else { return DetailsTabModel(groups: []) }
    var active: PanelEpic?
    var finished: PanelSnapshot.DoneEpic?
    var queuedAt: Int?
    var queuePlace: String?
    switch subject {
    case .active(let epic): active = epic
    case .finished(let done): finished = done
    case .queued(let epic, let position): (queuedAt, queuePlace) = (epic.queuedAt, "\(ordinal(position)) in queue")
    }
    func row(
        _ label: String, _ note: String? = nil, _ value: String?, tone: DetailsRow.Tone = .normal, style: DetailsRow.Style = .text, url: String? = nil
    ) -> DetailsRow {
        guard let value else { return DetailsRow(label: label, note: note, value: DetailsRow.dash, tone: .dim) }
        return DetailsRow(label: label, note: note, value: value, tone: tone, style: style, url: url)
    }

    // Timing
    let started = active?.startedAt ?? reply?.stages.first { $0.stage != "queued" }?.startedAt
    let stageRow: DetailsRow
    if let active {
        let name = [PanelEpic.Stage.ship: "Shipping", .review: "In review", .fix: "Fixing"][active.stage ?? .ship] ?? "Working"
        stageRow = row("Stage", active.status == .needsHuman ? "\(name) · needs you" : name, formatDuration(now - active.stageSince))
    } else if let finished {
        stageRow = row("Stage", "Finished", finished.finishedAt.map { agoLine($0, now: now) })
    } else {
        stageRow = row("Stage", queuePlace, queuedAt.map { formatDuration(now - $0) })
    }
    let end = finished.map { $0.finishedAt } ?? active.map { _ in now }
    let timing = [
        stageRow,
        row(
            "Last activity", active.map { $0.status == .needsHuman ? "no movement since" : "agent output" },
            active?.lastActivityAt.map { agoLine($0, now: now) }
        ),
        row("Started", nil, started.map { dateLine($0, now: now, timeZone: timeZone) }),
        row("Total time", nil, started.flatMap { start in end.map { formatDuration($0 - start) } }),
    ]

    // Progress
    let all = (reply?.slices ?? []).filter { $0.state != "skipped" }
    var sliceCounts: (done: Int, total: Int)?
    if let counts = active?.slices, counts.total > 0 {
        sliceCounts = (counts.done, counts.total)
    } else if all.isEmpty == false {
        sliceCounts = (all.filter { $0.state == "closed" }.count, all.count)
    }
    let inShip = queuePlace != nil || (active != nil && (active?.stage ?? .ship) == .ship)
    let lastRound = reply?.rounds.last?.round
    let roundRow: DetailsRow
    if inShip {
        roundRow = row("Review round", "starts after ship", nil)
    } else if let active, let round = active.round ?? lastRound {
        let limit = active.needsHumanKind == "review_limit"
        roundRow = row(
            "Review round", limit ? "limit reached" : "in progress", "\(round) of \(active.maxReviews)",
            tone: limit ? .attention : .normal, style: .badge
        )
    } else {
        roundRow = row("Review round", finished == nil ? "in progress" : "approved", lastRound.map { "\($0)" }, tone: finished == nil ? .normal : .good, style: .badge)
    }
    let blockers = active?.blockers ?? reply?.rounds.last.map { round in round.blockers.filter { $0.mark != "fixed" }.count }
    let progress = [
        row(
            "Slices", sliceCounts.map { $0.done == $0.total ? "all merged" : "\($0.total - $0.done) left" },
            sliceCounts.map { "\($0.done) of \($0.total)" }
        ),
        roundRow,
        row(
            "Blockers", blockers.map { $0 == 0 ? "none open" : "open" }, blockers.map { $0 == 0 ? "none" : "\($0)" },
            tone: blockers.map { $0 == 0 ? .good : .bad } ?? .normal, style: .badge
        ),
    ]

    // Pull request
    let header = epicHeader(subject, reply: reply)
    let pullRow: DetailsRow
    if let label = header.prLabel {
        pullRow = row("Pull request", "opens on GitHub", label, style: .badge, url: header.prURL)
    } else if inShip {
        pullRow = row("Pull request", "opens when every slice is merged", "not yet", tone: .dim)
    } else {
        pullRow = row("Pull request", nil, nil)
    }
    let checksRow: DetailsRow
    if let pull = reply?.pr {
        if let checks = pull.checks, checks.passing + checks.failing + checks.pending > 0 {
            let parts = [(checks.passing, "passing"), (checks.failing, "failing"), (checks.pending, "pending")].filter { $0.0 > 0 }
            checksRow = row(
                "Checks", "on the PR", parts.map { "\($0.0) \($0.1)" }.joined(separator: " · "),
                tone: checks.failing > 0 ? .bad : checks.pending > 0 ? .attention : .good, style: .badge,
                url: header.prURL.map { $0 + "/checks" }
            )
        } else {
            checksRow = row("Checks", "on the PR", "no checks", tone: .dim)
        }
    } else {
        checksRow = row("Checks", nil, nil)
    }
    let branch = reply?.branch ?? active?.branch
    let branchURL = branch.flatMap { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) }.map { "https://github.com/\(subject.repo)/tree/\($0)" }
    let pull = [pullRow, checksRow, row("Branch", nil, branch, style: .badge, url: branchURL)]

    // Run: the agent whose turn it is, the reviewer while a review runs and the author otherwise
    let agent = active?.agents.map { active?.stage == .review ? $0.reviewer : $0.author }
    let lanes = (reply?.worktrees ?? []).filter { $0.kind == "lane" }.count
    let run = [
        row("Agent", agent?.model, agent.map { agentLabel($0) }),
        row("Lanes", nil, lanes > 0 ? "\(lanes)" : nil),
        row("Repository", nil, subject.repo, style: .badge, url: "https://github.com/\(subject.repo)"),
    ]

    return DetailsTabModel(groups: [
        DetailsGroup(title: "Timing", rows: timing), DetailsGroup(title: "Progress", rows: progress),
        DetailsGroup(title: "Pull request", rows: pull), DetailsGroup(title: "Run", rows: run),
    ])
}

/// "Today 14:02", "Yesterday 11:14", "Oct 19 14:02".
private func dateLine(_ at: Int, now: Int, timeZone: TimeZone) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let date = Date(timeIntervalSince1970: Double(at) / 1000)
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = timeZone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "HH:mm"
    let time = formatter.string(from: date)
    let today = Date(timeIntervalSince1970: Double(now) / 1000)
    if calendar.isDate(date, inSameDayAs: today) { return "Today \(time)" }
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), calendar.isDate(date, inSameDayAs: yesterday) {
        return "Yesterday \(time)"
    }
    formatter.dateFormat = "MMM d HH:mm"
    return formatter.string(from: date)
}
