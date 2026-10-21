import Foundation
import Testing
@testable import CarrierCore

private func active(
    _ status: PanelEpic.Status = .running, stage: PanelEpic.Stage? = .ship, round: Int? = nil, slices: PanelEpic.Slices? = nil
) -> EpicSubject {
    .active(
        PanelEpic(
            repo: "acme/web", issue: 1, status: status, stage: stage, round: round, maxReviews: 5, blockers: 0, stageSince: 0,
            lastActivityAt: nil, issueUrl: "https://example.test/1", prUrl: nil, lastError: nil, needsHumanReason: nil, slices: slices,
            executionId: nil
        )
    )
}

private let queuedEpic = EpicSubject.queued(.init(repo: "acme/web", issue: 2, title: nil, queuedAt: nil), position: 1)
private let readyEpic = EpicSubject.finished(.init(repo: "acme/web", issue: 3, prNumber: 9, finishedAt: nil, executionId: nil))

@Test func opensOnSlicesInShipAndOnReviewOtherwise() {
    #expect(inspectorTab(active(stage: .ship), chosen: nil) == .slices)
    #expect(inspectorTab(active(stage: .review, round: 1), chosen: nil) == .review)
    #expect(inspectorTab(active(stage: .fix, round: 1), chosen: nil) == .review)
    #expect(inspectorTab(active(.needsHuman, stage: .ship), chosen: nil) == .review)
    #expect(inspectorTab(readyEpic, chosen: nil) == .review)
    #expect(inspectorTab(queuedEpic, chosen: nil) == .review)
    #expect(inspectorTab(nil, chosen: nil) == .review)
}

@Test func aChosenTabHoldsForEveryEpic() {
    for subject in [active(stage: .ship), active(.needsHuman), queuedEpic, readyEpic] {
        #expect(inspectorTab(subject, chosen: .details) == .details)
    }
}

@Test func theChoiceSurvivesARelaunch() {
    let name = "inspector-\(UUID().uuidString)"
    #expect(InspectorStore(defaults: UserDefaults(suiteName: name)!).chosen == nil)
    InspectorStore(defaults: UserDefaults(suiteName: name)!).chosen = .details
    let relaunched = InspectorStore(defaults: UserDefaults(suiteName: name)!)
    #expect(relaunched.chosen == .details)
    #expect(inspectorTab(active(stage: .ship), chosen: relaunched.chosen) == .details)
    relaunched.chosen = nil
    #expect(relaunched.chosen == nil)
}

@Test func slicesCountMergedOverTotal() {
    #expect(inspectorCount(.slices, active(slices: .init(done: 3, total: 5))).text == "3/5")
    #expect(inspectorCount(.slices, active(slices: .init(done: 0, total: 0))).text == nil)
    #expect(inspectorCount(.slices, queuedEpic).text == nil)
    #expect(inspectorCount(.slices, nil).text == nil)
}

@Test func slicesCountFallsBackToTheReply() {
    func slice(_ n: Int, _ state: String) -> EpicReply.Slice {
        .init(number: n, title: "s", state: state, blockedBy: [], prNumber: nil, closedAt: nil, readAt: 0)
    }
    let reply = EpicReply(
        stages: [], rounds: [], slices: [slice(1, "closed"), slice(2, "closed"), slice(3, "waiting")], worktrees: [], branch: nil, pr: nil
    )
    #expect(inspectorCount(.slices, readyEpic, reply: reply).text == "2/3")
}

@Test func reviewCountsTheRoundAndIsOrangeWhenAPersonIsNeeded() {
    #expect(inspectorCount(.review, active(stage: .review, round: 2)) == InspectorCount(text: "R2", needsYou: false))
    #expect(inspectorCount(.review, active(.needsHuman, stage: .review, round: 5)) == InspectorCount(text: "R5", needsYou: true))
    #expect(inspectorCount(.review, active(stage: .ship)).text == nil)
    #expect(inspectorCount(.review, queuedEpic).text == nil)
}

@Test func detailsHasNoCount() {
    #expect(inspectorCount(.details, active(stage: .review, round: 2)).text == nil)
    #expect(inspectorCount(.details, readyEpic).text == nil)
}
