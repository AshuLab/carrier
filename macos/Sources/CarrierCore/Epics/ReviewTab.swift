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

    public func text(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        switch self {
        case .new: Copy.epicsMarkNew(bundle: bundle, locale: locale)
        case .since(let round): Copy.epicsMarkSince(round: round, bundle: bundle, locale: locale)
        case .carriedOver: Copy.epicsMarkCarriedOver(bundle: bundle, locale: locale)
        case .fixed: Copy.epicsMarkFixed(bundle: bundle, locale: locale)
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
    /// The non-blocking findings of a review, after its blockers.
    public var observations: [EpicReply.Observation] = []
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
    /// nil when the engine does not send threads, or sends none for an epic with no pull request yet: no section. An empty list on an epic with a pull request is a section saying there are none.
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

public func reviewTab(_ subject: EpicSubject?, reply: EpicReply?, bundle: Bundle? = nil, locale: Locale = .current) -> ReviewTabModel {
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
        let author = epic?.agents.map { agentLabel($0.author) } ?? Copy.epicsReviewTheAuthor(bundle: bundle, locale: locale)
        let reviewer = result.map { agentLabel($0.reviewer) } ?? epic?.agents.map { agentLabel($0.reviewer) } ?? Copy.epicsReviewTheReviewer(bundle: bundle, locale: locale)
        let list = index.map(blockers) ?? []
        let nextExists = index.flatMap(next) != nil
        let isFixing = latest && fixing && result?.verdict == "changes_requested"

        var steps: [ReviewStep] = []
        guard let result else {
            steps = [
                ReviewStep(number: 1, state: .current, title: Copy.epicsReviewIsReviewing(who: reviewer, bundle: bundle, locale: locale), subtitle: Copy.epicsReviewRound(round: number, bundle: bundle, locale: locale)),
                ReviewStep(number: 2, state: .waiting, title: Copy.sessionPlaceFix(bundle: bundle, locale: locale), subtitle: Copy.epicsReviewIfBlockers(bundle: bundle, locale: locale)),
                ReviewStep(number: 3, state: .waiting, title: Copy.epicsReviewVerdict(bundle: bundle, locale: locale), subtitle: Copy.epicsReviewAfterReview(bundle: bundle, locale: locale)),
            ]
            return ReviewRoundView(
                id: rounds.count, round: number, chip: ReviewChip(text: Copy.epicsChipReviewing(bundle: bundle, locale: locale), tone: .live), delta: nil, steps: steps, approximate: false
            )
        }
        let count = result.blockers.filter { $0.mark != "fixed" }.count
        let counts = result.verdict == "approved" ? Copy.epicsNoBlockers(bundle: bundle, locale: locale) : Copy.epicsBlockers(count: count, bundle: bundle, locale: locale)
        steps.append(
            ReviewStep(
                number: 1, state: .done, title: Copy.epicsReviewReviewed(who: reviewer, bundle: bundle, locale: locale),
                subtitle: ([counts] + (result.reviewMs.map { [formatDuration($0)] } ?? [])).joined(separator: " · "), blockers: list,
                observations: result.observations
            )
        )
        let commits = result.commits
        if result.verdict == "changes_requested" || hasFix(result) {
            if isFixing {
                steps.append(ReviewStep(number: 2, state: .current, title: Copy.epicsReviewIsFixing(who: author, bundle: bundle, locale: locale), subtitle: Copy.epicsChipFixingNow(bundle: bundle, locale: locale)))
            } else if hasFix(result) {
                steps.append(
                    ReviewStep(
                        number: 2, state: .done,
                        title: commits.isEmpty
                            ? Copy.epicsReviewPushedFix(who: author, bundle: bundle, locale: locale)
                            : Copy.epicsReviewPushedCommits(who: author, count: commits.count, bundle: bundle, locale: locale),
                        subtitle: result.fixMs.map(formatDuration) ?? "",
                        commits: commits.prefix(3).map { ReviewCommit(sha: String($0.sha.prefix(7)), subject: $0.subject) },
                        moreCommits: max(0, commits.count - 3)
                    )
                )
            } else {
                steps.append(ReviewStep(number: 2, state: .waiting, title: Copy.sessionPlaceFix(bundle: bundle, locale: locale), subtitle: Copy.epicsReviewWaitingAuthor(bundle: bundle, locale: locale)))
            }
        }
        switch result.verdict {
        case "approved":
            steps.append(ReviewStep(number: 3, state: .done, title: Copy.epicsReviewApproved(bundle: bundle, locale: locale), subtitle: EpicMenuState.ready.label(bundle: bundle, locale: locale)))
        case "limit_reached":
            steps.append(
                ReviewStep(number: 3, state: .stopped, title: Copy.epicsReviewLimit(bundle: bundle, locale: locale), subtitle: Copy.epicsReviewLimitDetail(bundle: bundle, locale: locale))
            )
        default:
            steps.append(
                nextExists
                    ? ReviewStep(number: 3, state: .done, title: Copy.epicsReviewReReviewed(bundle: bundle, locale: locale), subtitle: Copy.epicsReviewInRound(round: number + 1, bundle: bundle, locale: locale))
                    : ReviewStep(
                        number: 3, state: .waiting, title: Copy.epicsReviewReReview(bundle: bundle, locale: locale),
                        subtitle: Copy.epicsReviewChecksAgain(who: reviewer, bundle: bundle, locale: locale)
                    )
            )
        }

        let chip: ReviewChip
        switch result.verdict {
        case "approved": chip = ReviewChip(text: Copy.epicsChipApproved(bundle: bundle, locale: locale), tone: .good)
        case "limit_reached": chip = ReviewChip(text: Copy.epicsChipStillOpen(bundle: bundle, locale: locale), tone: .attention)
        default:
            if isFixing {
                chip = ReviewChip(text: Copy.epicsChipFixingNow(bundle: bundle, locale: locale), tone: .live)
            } else if nextExists {
                let carried = list.filter { $0.mark == .carriedOver }.count
                chip = carried == 0
                    ? ReviewChip(text: Copy.epicsChipAllFixed(bundle: bundle, locale: locale), tone: .good)
                    : ReviewChip(text: Copy.epicsChipCarriedOver(count: carried, bundle: bundle, locale: locale), tone: .attention)
            } else {
                chip = ReviewChip(text: Copy.epicsChipChangesRequested(bundle: bundle, locale: locale), tone: .neutral)
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
        card = ReviewCard(heading: Copy.epicsReviewHeading(kind: .now, round: number, bundle: bundle, locale: locale), view: view(nil, round: number, latest: true))
    } else if let latest, shipping == false {
        let round = view(latest, round: rounds[latest].round, latest: true)
        let kind: Copy.EpicsReviewHeading = rounds[latest].verdict == "approved" ? .result : .now
        card = ReviewCard(heading: Copy.epicsReviewHeading(kind: kind, round: rounds[latest].round, bundle: bundle, locale: locale), view: round)
        historyEnd = latest
    }
    let history = rounds[..<historyEnd].indices.reversed().map { view($0, round: rounds[$0].round, latest: false) }
    let headline = card.map { card in
        maxReviews.map { Copy.epicsReviewHeadlineOf(round: card.view.round, max: $0, bundle: bundle, locale: locale) } ?? Copy.epicsReviewRound(round: card.view.round, bundle: bundle, locale: locale)
    }
    let threads = reply?.threads.flatMap { $0.isEmpty && reply?.pr == nil ? nil : threadsModel($0, truncated: reply?.threadsTruncated == true, bundle: bundle, locale: locale) }
    return ReviewTabModel(headline: headline, card: card, history: history, threads: threads)
}

private func threadsModel(_ threads: [EpicReply.ReviewThread], truncated: Bool, bundle: Bundle?, locale: Locale) -> ReviewThreadsModel {
    let rows = (threads.filter { $0.resolved == false } + threads.filter(\.resolved)).map { thread in
        let name = thread.author ?? Copy.epicsThreadUnknown(bundle: bundle, locale: locale)
        return ReviewThreadRow(
            id: thread.id, author: thread.bot ? Copy.epicsThreadBot(name: name, bundle: bundle, locale: locale) : name,
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
