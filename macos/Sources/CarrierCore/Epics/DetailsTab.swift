import Foundation

// The Details tab as plain values: four groups of rows, Timing, Progress, Pull request and Run
// (docs/specs/macos-app-redesign.md, story 29). The views map them one to one. A value the engine did not send is a dash,
// never a guess; an older engine that sends none of the new fields gets the rows the snapshot alone can fill.

public struct DetailsRow: Equatable {
    /// Which fact the row is, so a front-end picks its icon by it and not by the words of its label.
    public enum Field: Equatable { case stage, lastActivity, started, totalTime, slices, reviewRound, blockers, pullRequest, checks, branch, agent, lanes, repository, other }
    public enum Tone: Equatable { case normal, good, attention, bad, dim }
    /// How the value is drawn: plain text, or a badge (a coloured capsule; the accent colour with an arrow when it has a `url`).
    public enum Style: Equatable { case text, badge }

    public var field: Field = .other
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

public func detailsTab(
    _ subject: EpicSubject?, reply: EpicReply?, sessions: SessionsReply? = nil, now: Int, time: TimeFormat = .stored(), bundle: Bundle? = nil,
    locale: Locale = .current
) -> DetailsTabModel {
    guard let subject else { return DetailsTabModel(groups: []) }
    var active: PanelEpic?
    var finished: PanelSnapshot.DoneEpic?
    var cancelled = false
    var queuedAt: Int?
    var queuePlace: String?
    switch subject {
    case .active(let epic): active = epic
    case .finished(let done): finished = done
    case .ended(let epic): (finished, cancelled) = (epic.asDone, epic.status == .cancelled)
    case .queued(let epic, let position): (queuedAt, queuePlace) = (epic.queuedAt, queuePlaceLine(position, bundle: bundle, locale: locale))
    }
    func row(
        _ field: DetailsRow.Field, _ label: String, _ note: String? = nil, _ value: String?, tone: DetailsRow.Tone = .normal, style: DetailsRow.Style = .text,
        url: String? = nil
    ) -> DetailsRow {
        guard let value else { return DetailsRow(field: field, label: label, note: note, value: DetailsRow.dash, tone: .dim) }
        return DetailsRow(field: field, label: label, note: note, value: value, tone: tone, style: style, url: url)
    }
    func say(_ key: (Bundle?, Locale) -> String) -> String { key(bundle, locale) }

    // Timing
    let started = active?.startedAt ?? reply?.stages.first { $0.stage != "queued" }?.startedAt
    let stageRow: DetailsRow
    if let active {
        let name = Copy.epicsDetailsStage(stage: active.stage.map(\.detailsStage) ?? .ship, bundle: bundle, locale: locale)
        stageRow = row(
            .stage, say(Copy.epicsDetailsLabelStage), active.status == .needsHuman ? Copy.epicsDetailsNeedsYou(stage: name, bundle: bundle, locale: locale) : name,
            formatDuration(now - active.stageSince)
        )
    } else if let finished {
        let note = cancelled ? say(Copy.epicsStateCancelled) : say(Copy.epicsDetailsFinished)
        stageRow = row(.stage, say(Copy.epicsDetailsLabelStage), note, finished.finishedAt.map { agoLine($0, now: now, time: time, bundle: bundle, locale: locale) })
    } else {
        stageRow = row(.stage, say(Copy.epicsDetailsLabelStage), queuePlace, queuedAt.map { formatDuration(now - $0) })
    }
    let end = finished.map { $0.finishedAt } ?? active.map { _ in now }
    // Only a running epic has a last activity; for the others the Stage row already says when it ended or how long it waits
    var timing = [stageRow]
    if let active {
        timing.append(row(
            .lastActivity, say(Copy.epicsDetailsLabelLastActivity), active.status == .needsHuman ? say(Copy.epicsDetailsNoMovement) : say(Copy.epicsDetailsAgentOutput),
            active.lastActivityAt.map { agoLine($0, now: now, time: time, bundle: bundle, locale: locale) } ?? say(Copy.epicsDetailsNoActivity)
        ))
    }
    timing += [
        row(.started, say(Copy.epicsDetailsLabelStarted), nil, started.map { timeText(Date(ms: $0), now: Date(ms: now), format: time.asClock, bundle: bundle) }),
        row(.totalTime, say(Copy.epicsDetailsLabelTotalTime), nil, started.flatMap { start in end.map { formatDuration($0 - start) } }),
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
    let roundLabel = say(Copy.epicsDetailsLabelReviewRound)
    let roundRow: DetailsRow
    if inShip {
        roundRow = row(.reviewRound, roundLabel, say(Copy.epicsDetailsRoundAfterShip), nil)
    } else if let active, let round = active.round ?? lastRound {
        let limit = active.needsHumanKind == "review_limit"
        roundRow = row(
            .reviewRound, roundLabel, limit ? say(Copy.epicsDetailsRoundLimit) : say(Copy.epicsDetailsInProgress),
            Copy.epicsDetailsOf(done: round, total: active.maxReviews, bundle: bundle, locale: locale), tone: limit ? .attention : .normal, style: .badge
        )
    } else {
        roundRow = row(
            .reviewRound, roundLabel, finished == nil ? say(Copy.epicsDetailsInProgress) : cancelled ? say(Copy.epicsDetailsRoundCancelled) : say(Copy.epicsDetailsRoundApproved),
            lastRound.map { "\($0)" }, tone: finished == nil || cancelled ? .normal : .good, style: .badge
        )
    }
    let blockers = active?.blockers ?? reply?.rounds.last.map { round in round.blockers.filter { $0.mark != "fixed" }.count }
    let progress = [
        row(
            .slices, say(Copy.epicsDetailsLabelSlices),
            sliceCounts.map { $0.done == $0.total ? say(Copy.epicsSlicesAllMerged) : Copy.epicsDetailsLeft(count: $0.total - $0.done, bundle: bundle, locale: locale) },
            sliceCounts.map { Copy.epicsDetailsOf(done: $0.done, total: $0.total, bundle: bundle, locale: locale) }
        ),
        roundRow,
        row(
            .blockers, say(Copy.epicsDetailsLabelBlockers),
            blockers.map { $0 == 0 ? say(Copy.epicsDetailsNoneOpen) : Copy.epicsDetailsBlockersOpen(count: $0, bundle: bundle, locale: locale) },
            blockers.map { $0 == 0 ? say(Copy.epicsDetailsNone) : "\($0)" },
            tone: blockers.map { $0 == 0 ? .good : .bad } ?? .normal, style: .badge
        ),
    ]

    // Pull request
    let header = epicHeader(subject, reply: reply, bundle: bundle, locale: locale)
    let pullLabel = say(Copy.epicsDetailsLabelPullRequest)
    let pullRow: DetailsRow
    if let label = header.prLabel {
        pullRow = row(.pullRequest, pullLabel, say(Copy.epicsDetailsOpensOnGithub), label, style: .badge, url: header.prURL)
    } else if inShip {
        pullRow = row(.pullRequest, pullLabel, say(Copy.epicsDetailsOpensWhenMerged), say(Copy.epicsDetailsNotYet), tone: .dim)
    } else {
        pullRow = row(.pullRequest, pullLabel, nil, nil)
    }
    let checksLabel = say(Copy.epicsDetailsLabelChecks)
    let checksRow: DetailsRow
    if let pull = reply?.pr {
        if let checks = pull.checks, checks.passing + checks.failing + checks.pending > 0 {
            let parts = [
                checks.passing > 0 ? Copy.epicsDetailsChecksPassing(count: checks.passing, bundle: bundle, locale: locale) : nil,
                checks.failing > 0 ? Copy.epicsDetailsChecksFailing(count: checks.failing, bundle: bundle, locale: locale) : nil,
                checks.pending > 0 ? Copy.epicsDetailsChecksPending(count: checks.pending, bundle: bundle, locale: locale) : nil,
            ].compactMap { $0 }
            checksRow = row(
                .checks, checksLabel, say(Copy.epicsDetailsOnThePr), parts.joined(separator: " · "),
                tone: checks.failing > 0 ? .bad : checks.pending > 0 ? .attention : .good, style: .badge,
                url: header.prURL.map { $0 + "/checks" }
            )
        } else {
            checksRow = row(.checks, checksLabel, say(Copy.epicsDetailsOnThePr), say(Copy.epicsDetailsNoChecks), tone: .dim)
        }
    } else {
        checksRow = row(.checks, checksLabel, nil, nil)
    }
    let branch = reply?.branch ?? active?.branch
    let branchURL = branch.flatMap { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) }.map { "https://github.com/\(subject.repo)/tree/\($0)" }
    let pull = [pullRow, checksRow, row(.branch, say(Copy.epicsDetailsLabelBranch), nil, branch, style: .badge, url: branchURL)]

    // Run: while running, the agent whose turn it is (the reviewer during a review) and the lanes; once finished, who built it and
    // who reviewed it, from the sessions that ran
    var run: [DetailsRow] = []
    if let active {
        let agent = active.agents.map { active.stage == .review ? $0.reviewer : $0.author }
        let lanes = (reply?.worktrees ?? []).filter { $0.kind == "lane" }.count
        run = [
            row(.agent, say(Copy.epicsDetailsLabelAgent), agent?.model, agent.map { agentLabel($0) }),
            row(.lanes, say(Copy.epicsDetailsLabelLanes), nil, reply == nil ? nil : lanes > 0 ? "\(lanes)" : say(Copy.epicsDetailsNone)),
        ]
    } else if finished != nil {
        for (label, role) in [(say(Copy.sessionRoleShip), "author"), (say(Copy.sessionRoleReview), "reviewer")] {
            if let agent = sessions?.sessions.first(where: { $0.role == role })?.agent { run.append(row(.other, label, agent.model, agentLabel(agent))) }
        }
    }
    run.append(row(.repository, say(Copy.epicsDetailsLabelRepository), nil, subject.repo, style: .badge, url: "https://github.com/\(subject.repo)"))

    return DetailsTabModel(groups: [
        DetailsGroup(title: say(Copy.epicsDetailsGroupTiming), rows: timing), DetailsGroup(title: say(Copy.epicsDetailsGroupProgress), rows: progress),
        DetailsGroup(title: pullLabel, rows: pull), DetailsGroup(title: say(Copy.epicsDetailsGroupRun), rows: run),
    ])
}

private extension PanelEpic.Stage {
    var detailsStage: Copy.EpicsDetailsStage {
        switch self {
        case .ship: .ship
        case .review: .review
        case .fix: .fix
        }
    }
}
