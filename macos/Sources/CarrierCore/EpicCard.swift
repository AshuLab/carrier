import Foundation

/// What the card that opens on a Carrier row in the sidebar says: who it is, how far along it is, the facts of where it stands and
/// when it happened. The row says one thing; this is for a person who stopped to look.
public struct EpicCard: Equatable {
    public struct Step: Equatable {
        public var name: String
        public var state: StepState
        /// How much of the step is done, 0 to 1: the slices closed on Ship, the review round of the limit on Review / Fix. nil when
        /// nothing says, and the step is drawn whole.
        public var progress: Double?
    }

    public struct Fact: Equatable {
        public var label: String
        public var value: String
    }

    public var title: String
    /// The repository's name, never its owner: the project's icon is made from it.
    public var name: String
    /// "owner/name · #issue".
    public var subtitle: String
    /// Ship, Review / Fix and Ready; empty for an epic that has not started, where three empty steps say nothing.
    public var steps: [Step]
    public var facts: [Fact]
    /// "queued 2h ago · started 1h 50m ago".
    public var timeline: String?
}

public func epicCard(_ subject: EpicSubject, now: Int) -> EpicCard {
    let header = epicHeader(subject)
    var steps: [EpicCard.Step] = []
    var facts: [EpicCard.Fact] = []
    var times: [String] = []
    func ago(_ label: String, _ at: Int?) { if let at { times.append("\(label) \(agoLine(at, now: now))") } }

    switch subject {
    case .queued(let epic, _):
        ago("queued", epic.queuedAt)
    case .active(let epic):
        steps = pipelineSteps(subject).dropFirst().map { step in
            let progress: Double? = switch step.name {
            case "Ship": epic.slices.flatMap { $0.total > 0 ? Double($0.done) / Double($0.total) : nil }
            case "Review / Fix": epic.round.map { Double($0) / Double(max(epic.maxReviews, 1)) }
            default: nil
            }
            return EpicCard.Step(name: step.name, state: step.state, progress: step.state == .done || step.state == .waiting ? nil : progress)
        }
        facts.append(.init(label: "In this step", value: formatDuration(now - epic.stageSince)))
        if let round = roundLine(epic) { facts.append(.init(label: "Review", value: round)) }
        if let slices = epic.slices, slices.total > 0 { facts.append(.init(label: "Slices", value: "\(slices.done)/\(slices.total) closed")) }
        ago("queued", epic.queuedAt)
        ago("started", epic.startedAt)
    case .finished(let done):
        steps = pipelineSteps(subject).dropFirst().map { EpicCard.Step(name: $0.name, state: $0.state, progress: nil) }
        ago("finished", done.finishedAt)
    case .ended(let epic):
        steps = pipelineSteps(subject).dropFirst().map { EpicCard.Step(name: $0.name, state: $0.state, progress: nil) }
        if epic.status == .cancelled, let reason = epic.cancelReason, reason.isEmpty == false { facts.append(.init(label: "Reason", value: reason)) }
        ago("finished", epic.finishedAt)
    }
    if let pr = header.prLabel { facts.append(.init(label: "PR", value: String(pr.dropFirst(3)))) }
    if case .active(let epic) = subject, let branch = epic.branch, branch.isEmpty == false { facts.append(.init(label: "Branch", value: branch)) }

    return EpicCard(title: header.title, name: header.repo.split(separator: "/").last.map(String.init) ?? header.repo, subtitle: header.subtitle, steps: steps, facts: facts, timeline: times.isEmpty ? nil : times.joined(separator: " · "))
}

/// What the card of a row does when the pointer moves: it opens after a rest on the row, stays while the pointer is on the row or on the
/// card itself (which a person has to be able to reach to use what is in it), and closes a moment after the pointer left both, the
/// time to cross the gap between them.
public enum HoverCardStep: Equatable {
    case open(after: Duration), close(after: Duration), keep
}

public func hoverCardStep(onRow: Bool, onCard: Bool, shown: Bool, closedAt: Date?, now: Date) -> HoverCardStep {
    if onCard || (onRow && shown) { return .keep }
    if onRow { return .open(after: hoverCardDelay(closedAt: closedAt, now: now)) }
    return shown ? .close(after: .milliseconds(250)) : .keep
}

/// How long the pointer rests on a row before its card opens: 0.6 s, and no wait while another card closed a moment ago, so moving
/// down the list reads one card after another.
public func hoverCardDelay(closedAt: Date?, now: Date) -> Duration {
    guard let closedAt, now.timeIntervalSince(closedAt) < 0.3 else { return .milliseconds(600) }
    return .zero
}
