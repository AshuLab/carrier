import Foundation
import Testing
@testable import CarrierCore

private func epic(
    _ repo: String, _ issue: Int, _ status: PanelEpic.Status = .running, stage: PanelEpic.Stage? = .ship, round: Int? = nil,
    slices: PanelEpic.Slices? = nil, kind: String? = nil, reason: String? = nil, title: String? = nil
) -> PanelEpic {
    var epic = PanelEpic(
        repo: repo, issue: issue, status: status, stage: stage, round: round, maxReviews: 5, blockers: 0, stageSince: 0,
        lastActivityAt: nil, issueUrl: "https://example.test/\(issue)", prUrl: nil, lastError: nil, needsHumanReason: reason,
        slices: slices, executionId: nil
    )
    epic.needsHumanKind = kind
    epic.title = title
    return epic
}

private func snapshot(
    _ epics: [PanelEpic] = [], queue: [PanelSnapshot.QueuedEpic] = [], done: [PanelSnapshot.DoneEpic] = [], busy: Int = 0, total: Int = 3
) -> PanelSnapshot {
    PanelSnapshot(
        now: 125_000, slots: .init(busy: busy, total: total), queue: queue, epics: epics, startedAt: 0, repos: 1, nextCheckAt: nil,
        problem: nil, paused: false, done: done
    )
}

private func queued(_ repo: String, _ issue: Int) -> PanelSnapshot.QueuedEpic { .init(repo: repo, issue: issue, title: nil, queuedAt: nil) }

@Test func eachStateHasItsGroupRowAndDetailLine() throws {
    let all = snapshot(
        [
            epic("acme/web", 1, stage: .ship, slices: .init(done: 3, total: 5)),
            epic("acme/web", 2, stage: .review, round: 2, slices: .init(done: 5, total: 5)),
            epic("acme/api", 3, .needsHuman, kind: "review_limit"),
        ],
        queue: [queued("acme/api", 4)],
        done: [.init(repo: "acme/web", issue: 5, prNumber: 9, finishedAt: 5_000, executionId: nil)]
    )
    let groups = sidebarGroups(all, by: .status)
    #expect(groups.map(\.title) == ["Needs you", "Running", "Up next", "Ready for test"])
    #expect(groups[0].rows.map(\.detail) == ["review limit reached"])
    #expect(groups[1].rows.map(\.detail) == ["ship · 3/5 slices", "review · round 2/5"])
    #expect(groups[2].rows.map(\.detail) == ["waiting for a slot"])
    #expect(groups[3].rows.map(\.detail) == ["2m 00s ago"])
    let first = try #require(groups[0].rows.first)
    #expect(first.name == "api" && first.issue == 3 && first.state == .needsYou && first.selection == .epic(repo: "acme/api", issue: 3))
}

@Test func theStatusGroupsKeepTheSnapshotOrderAndOnlyReadyHidesWhenEmpty() {
    let groups = sidebarGroups(snapshot([epic("acme/web", 9), epic("acme/web", 2)]), by: .status)
    #expect(groups.map(\.title) == ["Needs you", "Running", "Up next"])
    #expect(groups[0].rows.isEmpty && groups[2].rows.isEmpty)
    #expect(groups[1].rows.map(\.issue) == [9, 2])
}

@Test func theKindOfInterventionIsSaidInWords() {
    func line(_ kind: String?, _ reason: String? = nil) -> String {
        sidebarGroups(snapshot([epic("a/b", 1, .needsHuman, kind: kind, reason: reason)]), by: .status)[0].rows[0].detail
    }
    #expect(line("timeout") == "timed out" && line("auth") == "authentication failed" && line("pr_invalid") == "pull request invalid")
    #expect(line("something_new", "the engine's words") == "the engine's words")
    #expect(line(nil) == "needs you")
}

@Test func aRunningEpicWithNoStageOrCountStillHasALine() {
    let rows = sidebarGroups(snapshot([epic("a/b", 1, stage: nil), epic("a/b", 2, stage: .fix)]), by: .status)[1].rows
    #expect(rows.map(\.detail) == ["starting", "fix"])
}

@Test func groupingByRepositoryOrdersSectionsByNameAndRowsByIssue() {
    let all = snapshot(
        [epic("acme/web", 8), epic("acme/api", 7, .needsHuman)], queue: [queued("acme/web", 3)],
        done: [.init(repo: "acme/api", issue: 1, prNumber: nil, finishedAt: nil, executionId: nil)]
    )
    let groups = sidebarGroups(all, by: .repo)
    #expect(groups.map(\.title) == ["api", "web"])
    #expect(groups[0].rows.map(\.issue) == [1, 7] && groups[1].rows.map(\.issue) == [3, 8])
    #expect(groups[0].rows[0].detail == "a while ago")
}

@Test func anEpicWithNoKnownTitleStillGetsARow() {
    let rows = sidebarGroups(snapshot([epic("acme/web", 4), epic("acme/web", 5, title: "Add login")], queue: [queued("acme/api", 6)]), by: .status)
    #expect(rows[1].rows.map(\.tooltip) == ["web #4", "Add login"])
    #expect(rows[2].rows[0].tooltip == "api #6")
}

@Test func theGroupsOfAnEmptySnapshotAreEmpty() {
    #expect(sidebarGroups(snapshot(), by: .repo).isEmpty)
    #expect(sidebarGroups(snapshot(), by: .status).allSatisfy { $0.rows.isEmpty })
}

@Test func thePillIsGreyAtZeroGreenInBetweenAndOrangeWhenFullWithAQueue() {
    #expect(sidebarPill(snapshot(busy: 0)) == SidebarPill(text: "0/3", tone: .gray))
    #expect(sidebarPill(snapshot(queue: [queued("a/b", 1)], busy: 0)).tone == .gray)
    #expect(sidebarPill(snapshot(busy: 2)) == SidebarPill(text: "2/3", tone: .green))
    #expect(sidebarPill(snapshot(busy: 3)) == SidebarPill(text: "3/3", tone: .green))
    #expect(sidebarPill(snapshot(queue: [queued("a/b", 1)], busy: 2)).tone == .green)
    #expect(sidebarPill(snapshot(queue: [queued("a/b", 1)], busy: 3)) == SidebarPill(text: "3/3", tone: .orange))
}

@Test func theGroupByChoiceSurvivesARelaunch() {
    let name = "carrier-sidebar-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    #expect(SidebarStore(defaults: defaults).groupBy == .status)
    SidebarStore(defaults: defaults).groupBy = .repo
    #expect(SidebarStore(defaults: defaults).groupBy == .repo)
    defaults.set("nonsense", forKey: "sidebar.groupBy")
    #expect(SidebarStore(defaults: defaults).groupBy == .status)
}

@Test func selectingARowOverviewOrSettingsUpdatesTheSelection() throws {
    let shell = WindowShell()
    let row = try #require(sidebarGroups(snapshot([epic("acme/web", 4)]), by: .status)[1].rows.first)
    for next in [row.selection, .settings, .overview] {
        shell.selection = next
        #expect(shell.selection == next)
    }
}
