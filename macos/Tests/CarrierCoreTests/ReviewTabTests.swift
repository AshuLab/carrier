import Foundation
import Testing
@testable import CarrierCore

private let codex = PanelSnapshot.Agent(harness: "codex", model: "gpt-5", provider: nil)
private let claude = PanelSnapshot.Agent(harness: "claude", model: "opus", provider: nil)

private func epic(_ status: PanelEpic.Status = .running, stage: PanelEpic.Stage?, round: Int? = nil) -> EpicSubject {
    var made = PanelEpic(
        repo: "acme/web", issue: 1, status: status, stage: stage, round: round, maxReviews: 5, blockers: 0, stageSince: 0,
        lastActivityAt: nil, issueUrl: "https://example.test/1", prUrl: nil, lastError: nil, needsHumanReason: nil, slices: nil,
        executionId: nil
    )
    made.agents = PanelSnapshot.Agents(author: claude, reviewer: codex)
    return .active(made)
}

/// A blocker as the engine sends it; its mark and approximate flag do not matter to the model (it matches by itself).
private func b(_ title: String, id: String? = nil, mark: String = "new") -> EpicReply.Blocker {
    EpicReply.Blocker(id: id, title: title, url: nil, mark: mark, approximate: id == nil)
}

private func round(
    _ n: Int, _ verdict: String = "changes_requested", _ blockers: [EpicReply.Blocker] = [], fixed: Bool = false, commits: Int = 0
) -> EpicReply.Round {
    EpicReply.Round(
        round: n, reviewer: codex, verdict: verdict, blockers: blockers, reviewMs: 20_000, fixMs: fixed ? 30_000 : nil,
        reviewedSha: "aaaaaaaaaa", fixedSha: fixed ? "bbbbbbbbbb" : nil,
        commits: (0..<commits).map { .init(sha: "c0ffee\($0)abcdef", subject: "fix \($0)") }
    )
}

private func reply(_ rounds: [EpicReply.Round], stage: String? = nil) -> EpicReply {
    EpicReply(
        stages: stage.map { [.init(stage: $0, startedAt: 0, endedAt: nil)] } ?? [], rounds: rounds, slices: [], worktrees: [], branch: nil, pr: nil
    )
}

private func marks(_ round: ReviewRoundView) -> [String] { (round.steps.first?.blockers ?? []).map(\.mark.text) }

// MARK: card and steps

@Test func withNoRoundTheTabIsEmpty() {
    #expect(reviewTab(epic(stage: .ship), reply: reply([])).isEmpty)
    #expect(reviewTab(nil, reply: nil).isEmpty)
    #expect(reviewTab(epic(stage: .ship), reply: reply([])).headline == nil)
}

@Test func roundOneBeingReviewedHasANumberedCardAndNoHistory() throws {
    let model = reviewTab(epic(stage: .review, round: 1), reply: reply([]))
    let card = try #require(model.card)
    #expect(card.heading == "Now · Round 1")
    #expect(model.headline == "round 1 of 5")
    #expect(card.view.chip == ReviewChip(text: "reviewing", tone: .live))
    #expect(card.view.steps.map(\.number) == [1, 2, 3])
    #expect(card.view.steps.map(\.state) == [.current, .waiting, .waiting])
    #expect(model.history.isEmpty)
}

@Test func roundTwoFixingTurnsTheFixStepAndTheVerdictWaits() throws {
    let rounds = [
        round(1, "changes_requested", [b("A"), b("B")], fixed: true, commits: 2),
        round(2, "changes_requested", [b("B", mark: "carried"), b("A", mark: "fixed")]),
    ]
    let model = reviewTab(epic(stage: .fix, round: 2), reply: reply(rounds, stage: "fix"))
    let card = try #require(model.card)
    #expect(card.heading == "Now · Round 2")
    #expect(card.view.chip == ReviewChip(text: "fixing now", tone: .live))
    #expect(card.view.steps.map(\.number) == [1, 2, 3])
    #expect(card.view.steps.map(\.state) == [.done, .current, .waiting])
    #expect(card.view.steps[1].title == "Claude is fixing")
    #expect(card.view.steps[2].title == "Re-review")
    #expect(model.history.map(\.round) == [1])
}

@Test func anApprovedRoundIsTheResult() throws {
    let rounds = [round(1, "changes_requested", [b("A")], fixed: true), round(2, "approved", [b("A", mark: "fixed")])]
    let model = reviewTab(epic(stage: .review, round: 2), reply: reply(rounds))
    let card = try #require(model.card)
    #expect(card.heading == "Result · Round 2")
    #expect(card.view.chip == ReviewChip(text: "approved", tone: .good))
    #expect(card.view.steps.map(\.title) == ["Codex reviewed", "Approved"])
    #expect(card.view.steps.map(\.number) == [1, 3])
    #expect(marks(card.view) == ["fixed"])
}

@Test func theLimitRoundStaysOpenAndSaysCarrierStopped() throws {
    let rounds = [
        round(1, "changes_requested", [b("A")], fixed: true),
        round(2, "limit_reached", [b("A", mark: "carried")]),
    ]
    let model = reviewTab(epic(.needsHuman, stage: .review, round: 2), reply: reply(rounds))
    let card = try #require(model.card)
    #expect(card.heading == "Now · Round 2")
    #expect(card.view.chip == ReviewChip(text: "still open", tone: .attention))
    let verdict = try #require(card.view.steps.last)
    #expect(verdict.state == .stopped)
    #expect(verdict.title == "Limit reached")
    #expect(verdict.subtitle == "Carrier stopped and is waiting for you")
    #expect(marks(card.view) == ["since R1"])
}

@Test func aRequeuedEpicStartsItsRoundsAgainAndKeepsTheOldOnesAsHistory() throws {
    let old = [
        round(1, "changes_requested", [b("A")], fixed: true),
        round(2, "limit_reached", [b("A", mark: "carried")]),
    ]
    let fresh = [round(1, "changes_requested", [b("A")])]
    let model = reviewTab(epic(stage: .fix, round: 1), reply: reply(old + fresh, stage: "fix"))
    #expect(model.card?.view.round == 1)
    #expect(model.history.map(\.round) == [2, 1])
    // the new attempt does not compare with the old one: A is new again, and there is no delta against round 2 of the old
    #expect(marks(try #require(model.card).view) == ["new"])
    #expect(model.card?.view.delta == nil)
    // the old limit round is still a limit round
    #expect(model.history[0].chip.text == "still open")
    #expect(Set(([model.card!.view] + model.history).map(\.id)).count == 3)
}

@Test func aRequeuedEpicBackInShipHasNoCardButKeepsTheHistory() {
    let old = [round(1, "changes_requested", [b("A")], fixed: true), round(2, "limit_reached", [b("A", mark: "carried")])]
    let model = reviewTab(epic(stage: .ship), reply: reply(old))
    #expect(model.card == nil)
    #expect(model.history.map(\.round) == [2, 1])
}

@Test func theFixCommitsShowThreeLinesAndAMoreCount() throws {
    let rounds = [round(1, "changes_requested", [b("A")], fixed: true, commits: 5), round(2, "approved", [b("A", mark: "fixed")])]
    let model = reviewTab(epic(stage: .review, round: 2), reply: reply(rounds))
    let fix = try #require(model.history.first?.steps.first { $0.number == 2 })
    #expect(fix.title == "Claude pushed 5 commits")
    #expect(fix.commits.map(\.sha) == ["c0ffee0", "c0ffee1", "c0ffee2"])
    #expect(fix.moreCommits == 2)
}

// MARK: blocker marks

@Test func withIdsAPersistingBlockerIsNewThenSinceItsFirstRoundAndNothingIsApproximate() throws {
    let rounds = [
        round(1, "changes_requested", [b("Token", id: "b1")], fixed: true),
        round(2, "changes_requested", [b("Token reworded", id: "b1", mark: "carried"), b("Log", id: "b2")], fixed: true),
        round(3, "changes_requested", [b("Token reworded again", id: "b1", mark: "carried")]),
    ]
    let model = reviewTab(epic(stage: .fix, round: 3), reply: reply(rounds, stage: "fix"))
    let card = try #require(model.card).view
    #expect(marks(card) == ["since R1"])
    #expect(card.approximate == false)
    // the earlier rounds say what became of theirs
    #expect(model.history.map(marks) == [["carried over", "fixed"], ["carried over"]])
    #expect(model.history.flatMap { $0.steps.first?.blockers ?? [] }.allSatisfy { $0.approximate == false })
    #expect(model.history.map(\.approximate) == [false, false])
}

@Test func withoutIdsTheMarksComeFromTitlesAndAreApproximate() throws {
    let rounds = [
        round(1, "changes_requested", [b("Token")], fixed: true),
        round(2, "changes_requested", [b("Token", mark: "carried"), b("Log")], fixed: true),
        round(3, "changes_requested", [b("Token", mark: "carried")]),
    ]
    let model = reviewTab(epic(stage: .fix, round: 3), reply: reply(rounds, stage: "fix"))
    let card = try #require(model.card).view
    #expect(marks(card) == ["since R1"])
    #expect(card.approximate)
    #expect(model.history.map(marks) == [["carried over", "fixed"], ["carried over"]])
    // round 1 has nothing before it: new is certain there, but what became of it is not
    #expect(model.history[1].approximate)
}

@Test func theFirstRoundWithoutIdsIsNotApproximateWhileItIsTheLatest() throws {
    let model = reviewTab(epic(stage: .fix, round: 1), reply: reply([round(1, "changes_requested", [b("A")])], stage: "fix"))
    let card = try #require(model.card).view
    #expect(marks(card) == ["new"])
    #expect(card.approximate == false)
}

@Test func aTitleThatChangesByCaseAndWhitespaceOnlyIsTheSameBlocker() throws {
    let rounds = [
        round(1, "changes_requested", [b("Token   expiry is NOT checked")], fixed: true),
        round(2, "changes_requested", [b(" token expiry is not  checked ")]),
    ]
    let model = reviewTab(epic(stage: .fix, round: 2), reply: reply(rounds, stage: "fix"))
    #expect(marks(try #require(model.card).view) == ["since R1"])
    #expect(marks(model.history[0]) == ["carried over"])
}

@Test func aDifferentTitleWithoutIdsIsANewBlockerAndTheOldOneIsFixed() throws {
    let rounds = [
        round(1, "changes_requested", [b("Token")], fixed: true),
        round(2, "changes_requested", [b("Logging")]),
    ]
    let model = reviewTab(epic(stage: .fix, round: 2), reply: reply(rounds, stage: "fix"))
    #expect(marks(try #require(model.card).view) == ["new"])
    #expect(marks(model.history[0]) == ["fixed"])
}

// MARK: delta

@Test func theDeltaChipCountsFewerMoreAndEqualBlockersAndIsAbsentInTheFirstRound() throws {
    let rounds = [
        round(1, "changes_requested", [b("A"), b("B"), b("C")], fixed: true),
        round(2, "changes_requested", [b("A"), b("B")], fixed: true),
        round(3, "changes_requested", [b("A"), b("B")], fixed: true),
        round(4, "changes_requested", [b("A"), b("B"), b("C"), b("D")]),
    ]
    let model = reviewTab(epic(stage: .fix, round: 4), reply: reply(rounds, stage: "fix"))
    #expect(model.card?.view.delta == 2)
    #expect(model.card?.view.deltaText == "↑ 2")
    #expect(model.history.map(\.delta) == [nil, -1, nil])
    #expect(model.history[1].deltaText == "↓ 1")
    #expect(model.history[2].deltaText == nil)
}

// MARK: history

@Test func theHistoryIsNewestFirstAndFoldedUntilOpened() {
    let rounds = [
        round(1, "changes_requested", [b("A")], fixed: true),
        round(2, "changes_requested", [b("B")], fixed: true),
        round(3, "changes_requested", [b("C")]),
    ]
    let model = reviewTab(epic(stage: .fix, round: 3), reply: reply(rounds, stage: "fix"))
    #expect(model.history.map(\.round) == [2, 1])

    let here = EpicRef(repo: "acme/web", issue: 1)
    let elsewhere = EpicRef(repo: "acme/web", issue: 2)
    var folds = ReviewFolds()
    #expect(model.history.allSatisfy { folds.isOpen(here, $0.id) == false })
    folds.toggle(here, model.history[0].id)
    #expect(folds.isOpen(here, model.history[0].id))
    #expect(folds.isOpen(here, model.history[1].id) == false)
    // it holds for the epic and is not another epic's
    #expect(folds.isOpen(here, model.history[0].id))
    #expect(folds.isOpen(elsewhere, model.history[0].id) == false)
    // the same round keeps its id when the reply grows
    let grown = reviewTab(epic(stage: .review, round: 4), reply: reply(rounds + [round(4, "approved")]))
    #expect(grown.history.first { $0.round == 2 }?.id == model.history[0].id)
    folds.toggle(here, model.history[0].id)
    #expect(folds.isOpen(here, model.history[0].id) == false)
}

@Test func aRequeuedEpicReviewingAgainShowsRoundOneAndKeepsTheLimitRoundInTheHistory() throws {
    let old = [round(1, "changes_requested", [b("A")], fixed: true), round(2, "limit_reached", [b("A", mark: "carried")])]
    let model = reviewTab(epic(stage: .review, round: 1), reply: reply(old, stage: "review"))
    #expect(model.card?.heading == "Now · Round 1")
    #expect(model.card?.view.chip.text == "reviewing")
    #expect(model.history.map(\.round) == [2, 1])
}

// MARK: threads

private func thread(
    _ id: String, line: Int? = 10, resolved: Bool = false, outdated: Bool = false, author: String? = "ana", bot: Bool = false, firstLine: String = "note"
) -> EpicReply.ReviewThread {
    EpicReply.ReviewThread(
        id: id, path: "src/a.ts", line: line, resolved: resolved, outdated: outdated, author: author, bot: bot, firstLine: firstLine,
        commentCount: 1, url: "https://example.test/\(id)"
    )
}

private func threadsModel(_ threads: [EpicReply.ReviewThread]?, truncated: Bool? = nil, hasPullRequest: Bool = true) -> ReviewThreadsModel? {
    var made = reply([])
    made.threads = threads
    made.threadsTruncated = truncated
    if hasPullRequest { made.pr = EpicReply.PullRequest(number: 51, url: "https://github.com/acme/web/pull/51", draft: false, mergeState: "clean", reviewDecision: nil, checks: nil) }
    return reviewTab(epic(stage: .review, round: 1), reply: made).threads
}

@Test func threadsAreUnresolvedFirstThenResolvedInGithubsOrder() {
    let model = threadsModel([thread("a", resolved: true), thread("b"), thread("c", resolved: true), thread("d")])
    #expect(model?.rows.map(\.id) == ["b", "d", "a", "c"])
    #expect(model?.rows.map(\.resolved) == [false, false, true, true])
    #expect(model?.rows[0].url == "https://example.test/b")
}

@Test func aThreadSaysWhoWroteItAndWhere() {
    let rows = threadsModel([thread("a"), thread("b", author: "ci", bot: true), thread("c", author: nil)])?.rows
    #expect(rows?.map(\.author) == ["ana", "ci (bot)", "unknown"])
    #expect(rows?[0].location == "src/a.ts:10")
    #expect(rows?[0].outdated == false)
}

@Test func aThreadWithNoLineIsItsFileAloneAndOutdated() {
    let row = threadsModel([thread("a", line: nil)])?.rows[0]
    #expect(row?.location == "src/a.ts")
    #expect(row?.outdated == true)
    #expect(threadsModel([thread("b", outdated: true)])?.rows[0].outdated == true)
}

@Test func anEmptyFirstLineShowsNothing() {
    let rows = threadsModel([thread("a", firstLine: ""), thread("b")])?.rows
    #expect(rows?.map(\.firstLine) == [nil, "note"])
}

@Test func theListSaysItIsPartialOnlyWhenTheEngineSaysSo() {
    #expect(threadsModel([thread("a")], truncated: true)?.partial == true)
    #expect(threadsModel([thread("a")], truncated: false)?.partial == false)
    #expect(threadsModel([thread("a")])?.partial == false)
}

@Test func withoutThreadsFromTheEngineThereIsNoSectionAndWithNoneThereIsAnEmptyOne() {
    #expect(threadsModel(nil) == nil)
    #expect(reviewTab(nil, reply: nil).threads == nil)
    #expect(threadsModel([])?.rows.isEmpty == true)
}

@Test func anEpicWithNoPullRequestYetHasNoThreadsSectionEvenWhenTheListIsEmpty() {
    #expect(threadsModel([], hasPullRequest: false) == nil)
    #expect(threadsModel([thread("a")], hasPullRequest: false)?.rows.count == 1)
}
