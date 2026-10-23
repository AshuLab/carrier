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
    /// Merged or cancelled, from the snapshot's finished window.
    case ended(PanelSnapshot.FinishedEpic)

    public var repo: String {
        switch self {
        case .queued(let epic, _): epic.repo
        case .active(let epic): epic.repo
        case .finished(let epic): epic.repo
        case .ended(let epic): epic.repo
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
        case .ended(let epic): epic.issue
        }
    }
}

extension PanelSnapshot {
    public func subject(repo: String, issue: Int) -> EpicSubject? {
        if let epic = epics.first(where: { $0.repo == repo && $0.issue == issue }) { return .active(epic) }
        if let at = queue.firstIndex(where: { $0.repo == repo && $0.issue == issue }) { return .queued(queue[at], position: at + 1) }
        if let done = done.first(where: { $0.repo == repo && $0.issue == issue }) { return .finished(done) }
        if let ended = finished.first(where: { $0.repo == repo && $0.issue == issue }) { return .ended(ended) }
        return nil
    }
}

// MARK: pipeline

/// Why a stuck epic is stuck, for the colour it is drawn in: a person's input, or something that failed.
public enum Attention: Equatable {
    case input, error
    /// nil kind and kinds the app does not know are `.input`: a person has to act either way.
    public init(kind: String?) {
        switch kind {
        case "retries_exhausted", "timeout", "auth", "workspace", "pr_invalid": self = .error
        default: self = .input
        }
    }
}

public enum StepState: Equatable {
    case done, current, waiting, input, error, cancelled
}

public struct PipelineStep: Equatable {
    public var name: String
    public var state: StepState
    /// Only the words of a stuck or cancelled step; never a time or a count.
    public var label: String?
    /// True only for Review / Fix while the epic is in review or fix and not stuck.
    public var loops: Bool
}

/// Queued, Ship, Review / Fix and Ready, each with its state; a stuck or cancelled step carries its words.
public func pipelineSteps(_ subject: EpicSubject, reply: EpicReply? = nil) -> [PipelineStep] {
    let names = ["Queued", "Ship", "Review / Fix", "Ready"]
    func steps(_ states: [StepState], words: String? = nil, loops: Bool = false) -> [PipelineStep] {
        (0..<4).map {
            PipelineStep(
                name: names[$0], state: states[$0], label: [.input, .error, .cancelled].contains(states[$0]) ? words : nil,
                loops: loops && $0 == 2 && states[$0] == .current
            )
        }
    }

    switch subject {
    case .queued:
        return steps([.current, .waiting, .waiting, .waiting])
    case .finished:
        return steps([.done, .done, .done, .done])
    case .ended(let epic):
        // a merged epic went through every step; a cancelled one stopped at the first step it had not reached
        if epic.status == .merged { return steps([.done, .done, .done, .done]) }
        let shipped = reply?.stages.contains { $0.stage == "ship" && $0.endedAt != nil } ?? false
        let reached = [true, shipped, reply.map { $0.rounds.isEmpty == false } ?? false, false]
        var states = reached.map { $0 ? StepState.done : .waiting }
        states[reached.firstIndex(of: false) ?? 3] = .cancelled
        return steps(states, words: "cancelled")
    case .active(let epic):
        let at = epic.stage == .review || epic.stage == .fix ? 2 : 1
        let stuck: StepState = Attention(kind: epic.needsHumanKind) == .error ? .error : .input
        var states = [StepState.done, .waiting, .waiting, .waiting]
        for i in 1...3 { states[i] = i < at ? .done : i == at ? (epic.status == .needsHuman ? stuck : .current) : .waiting }
        return steps(states, words: interventionLine(epic), loops: at == 2)
    }
}

/// 1st, 2nd, 3rd, 4th, 11th, 22nd.
public func ordinal(_ n: Int) -> String {
    let suffix = (11...13).contains(n % 100) ? "th" : ["th", "st", "nd", "rd", "th", "th", "th", "th", "th", "th"][n % 10]
    return "\(n)\(suffix)"
}

// MARK: header

public struct EpicHeader: Equatable {
    /// The epic's title, or "Epic #issue" while the engine has none.
    public var title: String
    /// "owner/name · #issue".
    public var subtitle: String
    public var repo: String
    public var issue: Int
    /// Without the `solve:` ones.
    public var labels: [String]
    public var prURL: String?
    /// "PR #50"; nil without a number.
    public var prLabel: String?
    public var issueURL: String
    /// The glyph beside the title.
    public var state: EpicMenuState
    /// The state in words, for the pill: "Running · review · round 2/5", "Needs you · review limit reached", "Up next · 2nd in queue", "Ready for test", "Done", "Cancelled · closed before start".
    public var status: String
}

public func epicHeader(_ subject: EpicSubject, reply: EpicReply? = nil) -> EpicHeader {
    let (repo, issue) = (subject.repo, subject.issue)
    var title: String?
    var labels: [String] = []
    var state = EpicMenuState.ready
    var status = "Ready for test"
    var prURL: String?
    var issueURL = "https://github.com/\(repo)/issues/\(issue)"
    switch subject {
    case .queued(let epic, let position): (title, state, status) = (epic.title, .waiting, "Up next · \(ordinal(position)) in queue")
    case .finished(let done): (title, prURL) = (done.title, donePullURL(done))
    case .ended(let epic):
        (title, labels, prURL) = (epic.title, epic.labels, donePullURL(epic.asDone))
        (state, status) = epic.status == .merged ? (.done, "Done") : (.cancelled, epic.cancelReason.flatMap { $0.isEmpty ? nil : "Cancelled · \($0)" } ?? "Cancelled")
    case .active(let epic):
        (title, labels, prURL, issueURL) = (epic.title, epic.labels ?? [], epic.prUrl, epic.issueUrl)
        (state, status) = epic.status == .running ? (.running, "Running · \(runningLine(epic))") : (.needsYou, "Needs you · \(interventionLine(epic))")
    }
    prURL = prURL ?? reply?.pr?.url
    let number = reply?.pr?.number ?? prURL.flatMap { URL(string: $0)?.lastPathComponent }.flatMap(Int.init)
    return EpicHeader(
        title: title.flatMap { $0.isEmpty ? nil : $0 } ?? "Epic #\(issue)",
        subtitle: "\(repo) · #\(issue)",
        repo: repo,
        issue: issue,
        labels: labels.filter { $0.hasPrefix("solve:") == false },
        prURL: prURL,
        prLabel: number.map { "PR #\($0)" },
        issueURL: issueURL,
        state: state,
        status: status
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
