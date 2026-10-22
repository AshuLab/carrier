import Foundation

// What the Review tab shows as plain values: the latest round as a card with three numbered steps and its blockers, and the
// earlier rounds folded under it, newest first (docs/specs/macos-app-redesign.md, story 28). The views map them one to one.
// It works from the `epic` reply plus the subject (which says whether a review or a fix is running right now).

// MARK: blockers

public enum ReviewMark: Equatable {
    /// First time the reviewer raised it (or the first round of an attempt).
    case new
    /// Open since this round, raised again in every round after it.
    case since(Int)
    /// Raised again in the next round.
    case carriedOver
    case fixed

    public var text: String {
        switch self {
        case .new: "new"
        case .since(let round): "since R\(round)"
        case .carriedOver: "carried over"
        case .fixed: "fixed"
        }
    }
}

public struct ReviewBlocker: Equatable {
    public var title: String
    public var url: String?
    public var mark: ReviewMark
    /// The mark came from matching titles, because the reviewer gave no id (or not for every blocker compared).
    public var approximate: Bool
}

// MARK: steps

public enum ReviewStepState: Equatable {
    case done, current, waiting
    /// Carrier stopped here and waits for a person (the limit): orange.
    case stopped
}

public struct ReviewCommit: Equatable {
    /// The first seven characters of the sha.
    public var sha: String
    public var subject: String
}

public struct ReviewStep: Equatable {
    /// 1 Review, 2 Fix, 3 Verdict. A round with no fix has no step 2.
    public var number: Int
    public var state: ReviewStepState
    public var title: String
    public var subtitle: String
    public var blockers: [ReviewBlocker] = []
    /// At most three.
    public var commits: [ReviewCommit] = []
    /// `+ N more`, 0 for none.
    public var moreCommits = 0
}

public struct ReviewChip: Equatable {
    public enum Tone: Equatable { case good, live, attention, neutral }

    public var text: String
    public var tone: Tone
}

/// One round: the same steps whether it is the card or an entry of the history.
public struct ReviewRoundView: Equatable {
    /// Position in the reply, unique even when a requeued epic starts its rounds again from 1.
    public var id: Int
    public var round: Int
    public var chip: ReviewChip
    /// Blockers fewer (negative) or more than the round before it in the same attempt; nil for the first round and for no change.
    public var delta: Int?
    public var steps: [ReviewStep]
    /// Some mark was found by matching titles.
    public var approximate: Bool

    /// "↓ 2", "↑ 1".
    public var deltaText: String? { delta.map { "\($0 < 0 ? "↓" : "↑") \(abs($0))" } }

    public var blockerCount: Int { steps.first?.blockers.filter { $0.mark != .fixed }.count ?? 0 }
}

public struct ReviewCard: Equatable {
    /// "Now · Round 2", "Result · Round 3" once approved.
    public var heading: String
    public var view: ReviewRoundView
}

/// One review thread of the final pull request, as the Review tab shows it.
public struct ReviewThreadRow: Equatable {
    public var id: String
    /// The author, "unknown" for a deleted account, "(bot)" after a bot's name.
    public var author: String
    /// "path:line", or the file alone when GitHub no longer maps the thread to a line.
    public var location: String
    public var resolved: Bool
    /// GitHub says so, or the thread has no line.
    public var outdated: Bool
    /// nil for an empty opening comment: nothing is shown in its place.
    public var firstLine: String?
    public var url: String
}

public struct ReviewThreadsModel: Equatable {
    /// Unresolved first, then resolved; GitHub's order within each.
    public var rows: [ReviewThreadRow]
    /// GitHub has more threads than the list holds.
    public var partial: Bool
}

public struct ReviewTabModel: Equatable {
    /// "round 2 of 5"; nil without a round.
    public var headline: String?
    /// nil with no round yet: the view shows the "review has not started" empty state.
    public var card: ReviewCard?
    /// Earlier rounds, newest first.
    public var history: [ReviewRoundView]
    /// nil when the engine does not send threads: no section. An empty list is a section saying there are none.
    public var threads: ReviewThreadsModel?

    public var isEmpty: Bool { card == nil && history.isEmpty }
}

// MARK: folds

/// The history entries the person opened; they are folded until then. Kept per epic, so the choice holds while it stays selected.
public struct ReviewFolds: Equatable {
    private var opened: Set<String> = []

    public init() {}

    public func isOpen(_ epic: EpicRef, _ id: Int) -> Bool { opened.contains(key(epic, id)) }

    public mutating func toggle(_ epic: EpicRef, _ id: Int) {
        if opened.insert(key(epic, id)).inserted == false { opened.remove(key(epic, id)) }
    }

    private func key(_ epic: EpicRef, _ id: Int) -> String { "\(epic.repo)#\(epic.issue):\(id)" }
}

// MARK: model

private typealias Blocker = EpicReply.Blocker

/// A title compared without caring for case or spacing (the engine's own rule).
private func normal(_ title: String) -> String {
    title.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
}

/// The same blocker in two rounds: by id when both have one, else by title.
private func same(_ a: Blocker, _ b: Blocker) -> Bool {
    if let x = a.id, let y = b.id { return x == y }
    return normal(a.title) == normal(b.title)
}

/// The blockers a round left open: the reply also lists, marked fixed, the earlier ones that disappeared.
private func open(_ round: EpicReply.Round) -> [Blocker] { round.blockers.filter { $0.mark != "fixed" } }

public func reviewTab(_ subject: EpicSubject?, reply: EpicReply?) -> ReviewTabModel {
    let rounds = reply?.rounds ?? []
    var epic: PanelEpic?
    if case .active(let active)? = subject { epic = active }
    let running = epic?.status == .running
    let lastStage = reply?.stages.last
    let fixing = (running && epic?.stage == .fix) || (lastStage?.stage == "fix" && lastStage?.endedAt == nil)
    let reviewing = (running && epic?.stage == .review) || (lastStage?.stage == "review" && lastStage?.endedAt == nil)
    let shipping = running && epic?.stage == .ship
    let maxReviews = epic?.maxReviews

    // Attempts: a round number that does not go up starts again after a requeue.
    var attempt = Array(repeating: 0, count: rounds.count)
    for i in rounds.indices.dropFirst() { attempt[i] = attempt[i - 1] + (rounds[i].round <= rounds[i - 1].round ? 1 : 0) }

    func hasFix(_ round: EpicReply.Round) -> Bool { round.fixedSha != nil || round.fixMs != nil }

    func previous(_ i: Int) -> Int? { i > 0 && attempt[i - 1] == attempt[i] ? i - 1 : nil }
    func next(_ i: Int) -> Int? { i + 1 < rounds.count && attempt[i + 1] == attempt[i] ? i + 1 : nil }

    /// The blocker of round `i` against the rounds before it: new, or open since the first round of an unbroken run.
    func stillOpen(_ blocker: Blocker, _ i: Int) -> ReviewBlocker {
        guard let before = previous(i) else { return ReviewBlocker(title: blocker.title, url: blocker.url, mark: .new, approximate: false) }
        var since = rounds[i].round
        var approximate = blocker.id == nil || open(rounds[before]).contains { $0.id == nil }
        var at = before
        var match = blocker
        while let found = open(rounds[at]).first(where: { same(match, $0) }) {
            since = rounds[at].round
            match = found
            approximate = approximate || found.id == nil
            guard let earlier = previous(at) else { break }
            at = earlier
        }
        return ReviewBlocker(title: blocker.title, url: blocker.url, mark: since == rounds[i].round ? .new : .since(since), approximate: approximate)
    }

    /// The blockers shown in round `i`: those it left open, each `carried over` or `fixed` by the round after it; while it has no
    /// round after it (the latest of its attempt) they are still open. An approved round shows what it resolved.
    func blockers(_ i: Int) -> [ReviewBlocker] {
        let round = rounds[i]
        if round.verdict == "approved" {
            return round.blockers.filter { $0.mark == "fixed" }.map {
                ReviewBlocker(title: $0.title, url: $0.url, mark: .fixed, approximate: $0.approximate)
            }
        }
        return open(round).map { blocker in
            guard let after = next(i) else { return stillOpen(blocker, i) }
            let carried = open(rounds[after]).contains { same(blocker, $0) }
            let approximate = blocker.id == nil || open(rounds[after]).contains { $0.id == nil }
            return ReviewBlocker(title: blocker.title, url: blocker.url, mark: carried ? .carriedOver : .fixed, approximate: approximate)
        }
    }

    /// `index` nil is the round being reviewed, which has no result yet.
    func view(_ index: Int?, round number: Int, latest: Bool) -> ReviewRoundView {
        let result = index.map { rounds[$0] }
        let author = epic?.agents.map { agentLabel($0.author) } ?? "The author"
        let reviewer = result.map { agentLabel($0.reviewer) } ?? epic?.agents.map { agentLabel($0.reviewer) } ?? "The reviewer"
        let list = index.map(blockers) ?? []
        let nextExists = index.flatMap(next) != nil
        let isFixing = latest && fixing && result?.verdict == "changes_requested"

        var steps: [ReviewStep] = []
        guard let result else {
            steps = [
                ReviewStep(number: 1, state: .current, title: "\(reviewer) is reviewing", subtitle: "round \(number)"),
                ReviewStep(number: 2, state: .waiting, title: "Fix", subtitle: "if it finds blockers"),
                ReviewStep(number: 3, state: .waiting, title: "Verdict", subtitle: "after the review"),
            ]
            return ReviewRoundView(id: rounds.count, round: number, chip: ReviewChip(text: "reviewing", tone: .live), delta: nil, steps: steps, approximate: false)
        }
        let count = result.blockers.filter { $0.mark != "fixed" }.count
        let counts = result.verdict == "approved" ? "no blockers" : "\(count) blocker\(count == 1 ? "" : "s")"
        steps.append(
            ReviewStep(
                number: 1, state: .done, title: "\(reviewer) reviewed",
                subtitle: ([counts] + (result.reviewMs.map { [formatDuration($0)] } ?? [])).joined(separator: " · "), blockers: list
            )
        )
        let commits = result.commits
        if result.verdict == "changes_requested" || hasFix(result) {
            if isFixing {
                steps.append(ReviewStep(number: 2, state: .current, title: "\(author) is fixing", subtitle: "fixing now"))
            } else if hasFix(result) {
                steps.append(
                    ReviewStep(
                        number: 2, state: .done,
                        title: commits.isEmpty ? "\(author) pushed a fix" : "\(author) pushed \(commits.count) commit\(commits.count == 1 ? "" : "s")",
                        subtitle: result.fixMs.map(formatDuration) ?? "",
                        commits: commits.prefix(3).map { ReviewCommit(sha: String($0.sha.prefix(7)), subject: $0.subject) },
                        moreCommits: max(0, commits.count - 3)
                    )
                )
            } else {
                steps.append(ReviewStep(number: 2, state: .waiting, title: "Fix", subtitle: "waiting for the author"))
            }
        }
        switch result.verdict {
        case "approved":
            steps.append(ReviewStep(number: 3, state: .done, title: "Approved", subtitle: "Ready for test"))
        case "limit_reached":
            steps.append(ReviewStep(number: 3, state: .stopped, title: "Limit reached", subtitle: "Carrier stopped and is waiting for you"))
        default:
            steps.append(
                nextExists
                    ? ReviewStep(number: 3, state: .done, title: "Re-reviewed", subtitle: "in round \(number + 1)")
                    : ReviewStep(number: 3, state: .waiting, title: "Re-review", subtitle: "\(reviewer) checks again when the fixes are in")
            )
        }

        let chip: ReviewChip
        switch result.verdict {
        case "approved": chip = ReviewChip(text: "approved", tone: .good)
        case "limit_reached": chip = ReviewChip(text: "still open", tone: .attention)
        default:
            if isFixing {
                chip = ReviewChip(text: "fixing now", tone: .live)
            } else if nextExists {
                let carried = list.filter { $0.mark == .carriedOver }.count
                chip = carried == 0 ? ReviewChip(text: "all fixed", tone: .good) : ReviewChip(text: "\(carried) carried over", tone: .attention)
            } else {
                chip = ReviewChip(text: "changes requested", tone: .neutral)
            }
        }

        var delta: Int?
        if let index, let before = previous(index) {
            let change = open(result).count - open(rounds[before]).count
            delta = change == 0 ? nil : change
        }
        return ReviewRoundView(id: index ?? rounds.count, round: number, chip: chip, delta: delta, steps: steps, approximate: list.contains { $0.approximate })
    }

    // The round being reviewed has no result yet: a review is running, the last round is not approved (that one is the result)
    // and nothing is waiting for a fix.
    let latest = rounds.indices.last
    let settled = latest.map { rounds[$0].verdict == "approved" || (rounds[$0].verdict == "changes_requested" && hasFix(rounds[$0]) == false) } ?? false
    let pending = reviewing && settled == false

    // A requeued epic is back in ship: the card waits for its review and the earlier rounds stay as history.
    var card: ReviewCard?
    var historyEnd = rounds.count
    if pending {
        // after a requeue the numbering starts again from 1
        let number = epic?.round ?? latest.map { rounds[$0].verdict == "changes_requested" ? rounds[$0].round + 1 : 1 } ?? 1
        card = ReviewCard(heading: "Now · Round \(number)", view: view(nil, round: number, latest: true))
    } else if let latest, shipping == false {
        let round = view(latest, round: rounds[latest].round, latest: true)
        card = ReviewCard(heading: "\(rounds[latest].verdict == "approved" ? "Result" : "Now") · Round \(rounds[latest].round)", view: round)
        historyEnd = latest
    }
    let history = rounds[..<historyEnd].indices.reversed().map { view($0, round: rounds[$0].round, latest: false) }
    let headline = card.map { "round \($0.view.round)" + (maxReviews.map { " of \($0)" } ?? "") }
    return ReviewTabModel(headline: headline, card: card, history: history, threads: reply?.threads.map { threadsModel($0, truncated: reply?.threadsTruncated == true) })
}

private func threadsModel(_ threads: [EpicReply.ReviewThread], truncated: Bool) -> ReviewThreadsModel {
    let rows = (threads.filter { $0.resolved == false } + threads.filter(\.resolved)).map { thread in
        let name = thread.author ?? "unknown"
        return ReviewThreadRow(
            id: thread.id, author: thread.bot ? "\(name) (bot)" : name,
            location: thread.line.map { "\(thread.path):\($0)" } ?? thread.path,
            resolved: thread.resolved, outdated: thread.outdated || thread.line == nil,
            firstLine: thread.firstLine.isEmpty ? nil : thread.firstLine, url: thread.url
        )
    }
    return ReviewThreadsModel(rows: rows, partial: truncated)
}

func agentLabel(_ agent: PanelSnapshot.Agent) -> String {
    switch agent.harness {
    case "claude": "Claude"
    case "codex": "Codex"
    case "agy": "Antigravity"
    default: agent.harness.prefix(1).uppercased() + agent.harness.dropFirst()
    }
}
