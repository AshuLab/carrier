import Foundation

// What an epic's view shows as plain values: the pipeline strip, the header with its links and the two tabs
// (docs/specs/macos-app-redesign.md, stories 17 and 18). The views map them one to one. Everything works from the snapshot
// alone; the `epic` reply, when the engine answers it, adds the time of each finished stage and the number of rounds.

/// Where an epic is, found by repository and number in the snapshot.
public enum EpicSubject: Equatable {
    /// `position` counts from 1.
    case queued(PanelSnapshot.QueuedEpic, position: Int)
    case active(PanelEpic)
    case finished(PanelSnapshot.DoneEpic)

    public var repo: String {
        switch self {
        case .queued(let epic, _): epic.repo
        case .active(let epic): epic.repo
        case .finished(let epic): epic.repo
        }
    }

    /// The empty state the Agent output tab shows while no agent has started; only a queued epic has one.
    public var outputEmptyState: EmptyState? {
        if case .queued = self { return .waitingForSlot }
        return nil
    }

    public var issue: Int {
        switch self {
        case .queued(let epic, _): epic.issue
        case .active(let epic): epic.issue
        case .finished(let epic): epic.issue
        }
    }
}

extension PanelSnapshot {
    public func subject(repo: String, issue: Int) -> EpicSubject? {
        if let epic = epics.first(where: { $0.repo == repo && $0.issue == issue }) { return .active(epic) }
        if let at = queue.firstIndex(where: { $0.repo == repo && $0.issue == issue }) { return .queued(queue[at], position: at + 1) }
        if let done = done.first(where: { $0.repo == repo && $0.issue == issue }) { return .finished(done) }
        return nil
    }
}

// MARK: pipeline

public enum StepState: Equatable {
    case done, current, waiting, problem
}

public struct PipelineStep: Equatable {
    public var name: String
    public var state: StepState
    /// After the name: the time of a finished stage, the round of the current one (`r2/5`), `1st in queue`.
    public var label: String?
}

/// Queued, Ship, Review/Fix and Ready, each with its state. The names are short so the line never wraps.
public func pipelineSteps(_ subject: EpicSubject, reply: EpicReply? = nil, now: Int) -> [PipelineStep] {
    let names = ["Queued", "Ship", "Review/Fix", "Ready"]
    func steps(_ states: [StepState], _ labels: [String?]) -> [PipelineStep] {
        (0..<4).map { PipelineStep(name: names[$0], state: states[$0], label: labels[$0]) }
    }
    let queuedFor = took(reply, ["queued"])
    let shipTook = took(reply, ["ship"])

    switch subject {
    case .queued(_, let position):
        return steps([.current, .waiting, .waiting, .waiting], ["\(ordinal(position)) in queue", nil, nil, nil])
    case .finished(let done):
        let rounds = reply.map { $0.rounds.count }.flatMap { $0 > 0 ? "\($0) \($0 == 1 ? "round" : "rounds")" : nil }
        return steps(
            [.done, .done, .done, .done],
            [queuedFor.map(formatDuration), shipTook.map(formatDuration), rounds, done.finishedAt.map { agoLine($0, now: now) }]
        )
    case .active(let epic):
        let waitedFor = queuedFor ?? epic.queuedAt.flatMap { queued in epic.startedAt.map { $0 - queued } }
        let at = epic.stage == .review || epic.stage == .fix ? 2 : 1
        let stuck = epic.status == .needsHuman
        var states = [StepState.done, .waiting, .waiting, .waiting]
        for i in 1...3 { states[i] = i < at ? .done : i == at ? (stuck ? .problem : .current) : .waiting }
        var labels: [String?] = [waitedFor.map(formatDuration), nil, nil, nil]
        if at == 2 {
            labels[1] = shipTook.map(formatDuration)
            labels[2] = reviewLabel(epic)
        } else if stuck == false {
            labels[1] = formatDuration(now - epic.stageSince)
        }
        return steps(states, labels)
    }
}

private func reviewLabel(_ epic: PanelEpic) -> String? {
    if epic.needsHumanKind == "review_limit" { return "limit \(epic.maxReviews)/\(epic.maxReviews)" }
    return epic.round.map { "r\($0)/\(epic.maxReviews)" }
}

/// The time spent in `stages` that have ended, from the reply; nil without one.
private func took(_ reply: EpicReply?, _ stages: Set<String>) -> Int? {
    let spans = (reply?.stages ?? []).filter { stages.contains($0.stage) }.compactMap { stage in stage.endedAt.map { $0 - stage.startedAt } }
    return spans.isEmpty ? nil : spans.reduce(0, +)
}

/// 1st, 2nd, 3rd, 4th, 11th, 22nd.
public func ordinal(_ n: Int) -> String {
    let suffix = (11...13).contains(n % 100) ? "th" : ["th", "st", "nd", "rd", "th", "th", "th", "th", "th", "th"][n % 10]
    return "\(n)\(suffix)"
}

// MARK: header

public struct EpicHeader: Equatable {
    /// The epic's title, or "repo #issue" while the engine has none.
    public var title: String
    /// "owner/name · #issue".
    public var subtitle: String
    /// Without the `solve:` ones.
    public var labels: [String]
    public var prURL: String?
    /// "PR #50"; nil without a number.
    public var prLabel: String?
    public var issueURL: String
}

public func epicHeader(_ subject: EpicSubject, reply: EpicReply? = nil) -> EpicHeader {
    let (repo, issue) = (subject.repo, subject.issue)
    var title: String?
    var labels: [String] = []
    var prURL: String?
    var issueURL = "https://github.com/\(repo)/issues/\(issue)"
    switch subject {
    case .queued(let epic, _): title = epic.title
    case .finished(let done): prURL = donePullURL(done)
    case .active(let epic):
        (title, labels, prURL, issueURL) = (epic.title, epic.labels ?? [], epic.prUrl, epic.issueUrl)
    }
    prURL = prURL ?? reply?.pr?.url
    let number = reply?.pr?.number ?? prURL.flatMap { URL(string: $0)?.lastPathComponent }.flatMap(Int.init)
    return EpicHeader(
        title: title.flatMap { $0.isEmpty ? nil : $0 } ?? "\(repo) #\(issue)",
        subtitle: "\(repo) · #\(issue)",
        labels: labels.filter { $0.hasPrefix("solve:") == false },
        prURL: prURL,
        prLabel: number.map { "PR #\($0)" },
        issueURL: issueURL
    )
}

// MARK: tabs

public enum EpicTab: CaseIterable {
    case agentOutput, filesChanged

    public var title: String {
        switch self {
        case .agentOutput: "Agent output"
        case .filesChanged: "Files changed"
        }
    }

    /// The tab's label: Files changed carries the count only when it is above zero.
    public func title(filesChanged: Int) -> String {
        self == .filesChanged && filesChanged > 0 ? "\(title) · \(filesChanged)" : title
    }
}

/// How many files the epic changed: each path once, whatever number of sessions touched it.
public func filesChangedCount(_ reply: FilesReply?) -> Int {
    Set((reply?.sections ?? []).flatMap { $0.files.map(\.path) }).count
}
