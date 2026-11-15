import Foundation
import Testing
@testable import CarrierCore

private func blocker(_ id: String?, _ title: String, _ mark: String, url: String? = nil, approximate: Bool = false) -> EpicReply.Blocker {
    EpicReply.Blocker(id: id, title: title, url: url, mark: mark, approximate: approximate)
}

private func round(_ number: Int, _ verdict: String, blockers: [EpicReply.Blocker] = [], observations: [EpicReply.Observation] = []) -> EpicReply.Round {
    EpicReply.Round(
        round: number, reviewer: .init(harness: "codex", model: "gpt-5", provider: nil), verdict: verdict, blockers: blockers, observations: observations,
        reviewMs: nil, fixMs: nil, reviewedSha: nil, fixedSha: nil, commits: []
    )
}

private func reply(_ rounds: [EpicReply.Round], pr: Bool = true) -> EpicReply {
    EpicReply(
        stages: [], rounds: rounds, slices: [], worktrees: [], branch: nil,
        pr: pr ? EpicReply.PullRequest(number: 743, url: "https://example.test/pull/743", draft: false, mergeState: "CLEAN", reviewDecision: nil, checks: nil) : nil
    )
}

private let suggestion = EpicReply.Observation(id: "s1", title: "Rename it", url: "https://example.test/pull/743#discussion_s1")

@Test func aReviewerRoundShowsItsBlockersThenItsSuggestionsWithTheMarksTheReplyGives() throws {
    let card = try #require(findingsCard(
        reply([round(1, "changes_requested", blockers: [blocker("b1", "Expiry", "new", url: "https://x.test/1"), blocker("b2", "Refresh", "new")], observations: [suggestion])]),
        stage: "review", round: 1
    ))
    #expect(card.title == "Changes requested" && card.verdict == .changesRequested && card.summary == "2 blockers · 1 suggestion")
    #expect(card.rows.map(\.kind) == [.blocker, .blocker, .suggestion] && card.rows.map(\.id) == ["b1", "b2", "s1"])
    #expect(card.rows.map(\.mark) == [.new, .new, nil])
    #expect(card.rows[0].url == "https://x.test/1" && card.rows[1].url == nil)
    #expect(card.prNumber == 743 && card.prURL == "https://example.test/pull/743")
}

@Test func aSecondRoundMarksCarriedAndFixedAndPutsTheFixedOneLast() throws {
    let card = try #require(findingsCard(
        reply([round(2, "changes_requested", blockers: [blocker("b1", "Expiry", "fixed"), blocker(nil, "Refresh", "carried", approximate: true), blocker("b3", "Leak", "new")])]),
        stage: "review", round: 2
    ))
    #expect(card.rows.map(\.mark) == [.carried, .new, .fixed] && card.rows.map(\.isFixed) == [false, false, true])
    #expect(card.rows[0].id == nil && card.rows[0].approximate)
    #expect(card.summary == "2 blockers open · 1 fixed")
}

@Test func theVerdictAndTheWordingOfTheSummary() throws {
    let ready = try #require(findingsCard(reply([round(3, "approved", observations: [suggestion, suggestion])]), stage: "review", round: 3))
    #expect(ready.title == "Ready" && ready.verdict == .ready && ready.summary == "0 blockers · 2 suggestions")
    let clean = try #require(findingsCard(reply([round(3, "approved")]), stage: "review", round: 3))
    #expect(clean.title == "Ready" && clean.summary == "no findings" && clean.rows.isEmpty)
    // the review limit is still changes requested, its blockers carried
    let limit = try #require(findingsCard(reply([round(5, "limit_reached", blockers: [blocker("b3", "Leak", "carried")])]), stage: "review", round: 5))
    #expect(limit.title == "Changes requested" && limit.summary == "1 blocker" && limit.rows[0].mark == .carried)
}

@Test func aMarkThisAppDoesNotKnowShowsNoChip() throws {
    let card = try #require(findingsCard(reply([round(1, "changes_requested", blockers: [blocker("b1", "t", "reopened")])]), stage: "review", round: 1))
    #expect(card.rows[0].mark == nil)
}

@Test func theFixerSeesTheOpenBlockersOfItsRoundAndTheOnesTheNextRoundVerified() throws {
    let rounds = [
        round(1, "changes_requested", blockers: [blocker("b1", "Expiry", "new"), blocker("b2", "Refresh", "new")]),
        round(2, "changes_requested", blockers: [blocker("b1", "Expiry", "fixed"), blocker("b2", "Refresh", "carried")]),
    ]
    // round 1's fixer: b1 was verified fixed by round 2, b2 was not
    let first = try #require(findingsCard(reply(rounds), stage: "fix", round: 1))
    #expect(first.rows.map(\.id) == ["b2", "b1"] && first.rows.map(\.mark) == [.new, .fixed])
    #expect(first.summary == "1 blocker open · 1 fixed")
    // round 2's fixer, still running: round 2's own fixed one is not its to answer; no later round yet
    let second = try #require(findingsCard(reply(rounds), stage: "fix", round: 2))
    #expect(second.rows.map(\.id) == ["b2"] && second.rows[0].mark == .carried)
}

@Test func theFixerOfAnApprovedRoundAnswersItsSuggestions() throws {
    let card = try #require(findingsCard(reply([round(3, "approved", observations: [suggestion])]), stage: "fix", round: 3))
    #expect(card.rows.map(\.kind) == [.suggestion] && card.title == "Ready")
}

@Test func thereIsNoCardWithoutARoundOrForTheBuilder() {
    let rounds = [round(1, "changes_requested", blockers: [blocker("b1", "t", "new")])]
    #expect(findingsCard(reply(rounds), stage: "ship", round: nil) == nil)
    #expect(findingsCard(reply(rounds), stage: "review", round: 2) == nil)
    #expect(findingsCard(reply(rounds), stage: "review", round: nil) == nil)
    #expect(findingsCard(nil, stage: "review", round: 1) == nil)
    // a fixer with nothing to answer
    #expect(findingsCard(reply([round(3, "approved")]), stage: "fix", round: 3) == nil)
    // no pull request yet: the header has none to link
    #expect(findingsCard(reply(rounds, pr: false), stage: "review", round: 1)?.prNumber == nil)
}

@Test func theFixtureReplyGivesTheReviewerAndTheFixerTheirRounds() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/reply-epic.json")
    let epic = try JSONDecoder().decode(EpicReply.self, from: Data(contentsOf: url))
    let first = try #require(findingsCard(epic, stage: "review", round: 1))
    #expect(first.rows.map(\.mark) == [.new, .new, nil] && first.summary == "2 blockers · 1 suggestion")
    let second = try #require(findingsCard(epic, stage: "review", round: 2))
    #expect(second.rows.map(\.mark) == [.carried, .new, .fixed])
    let fixer = try #require(findingsCard(epic, stage: "fix", round: 1))
    #expect(fixer.rows.filter { $0.kind == .blocker }.map(\.mark) == [.new, .fixed])
}
