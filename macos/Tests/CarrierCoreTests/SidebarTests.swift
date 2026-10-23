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
    #expect(groups[3].rows.map(\.detail) == ["2m ago"])
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

@Test func noCurrentGroupStartsCollapsedAndEveryOneStartsExpanded() {
    let all = snapshot(
        [epic("acme/web", 1), epic("acme/api", 2, .needsHuman)], queue: [queued("acme/api", 3)],
        done: [.init(repo: "acme/web", issue: 4, prNumber: nil, finishedAt: nil, executionId: nil)]
    )
    let collapse = SidebarCollapse()
    for by in GroupBy.allCases {
        let groups = sidebarGroups(all, by: by)
        #expect(groups.allSatisfy { $0.startsCollapsed == false && collapse.isCollapsed($0, by: by) == false })
    }
}

@Test func aGroupThatSaysItStartsCollapsedStartsCollapsedAndOpensOnToggle() {
    let group = SidebarGroup(title: "Done", rows: [], startsCollapsed: true)
    var collapse = SidebarCollapse()
    #expect(collapse.isCollapsed(group, by: .status))
    collapse.toggle(group, by: .status)
    #expect(collapse.isCollapsed(group, by: .status) == false)
    collapse.toggle(group, by: .status)
    #expect(collapse.isCollapsed(group, by: .status))
}

@Test func togglingOneGroupLeavesTheOthersAlone() {
    let groups = sidebarGroups(snapshot([epic("acme/web", 1)]), by: .status)
    var collapse = SidebarCollapse()
    collapse.toggle(groups[1], by: .status)
    #expect(groups.map { collapse.isCollapsed($0, by: .status) } == [false, true, false])
}

@Test func theStateOfAGroupSurvivesANewSnapshotAndTheGroupComingBack() {
    var collapse = SidebarCollapse()
    func running(_ epics: [PanelEpic], by: GroupBy = .status) -> SidebarGroup {
        sidebarGroups(snapshot(epics), by: by).first { $0.title == (by == .status ? "Running" : "web") }!
    }
    collapse.toggle(running([epic("acme/web", 1)]), by: .status)
    // rows come and go
    #expect(collapse.isCollapsed(running([epic("acme/web", 1), epic("acme/web", 2)]), by: .status))
    #expect(collapse.isCollapsed(running([]), by: .status))
    // the repository grouping has its own state, and a repository that leaves and returns keeps the one it had
    #expect(collapse.isCollapsed(running([epic("acme/web", 1)], by: .repo), by: .repo) == false)
    collapse.toggle(running([epic("acme/web", 1)], by: .repo), by: .repo)
    _ = sidebarGroups(snapshot(), by: .repo)
    #expect(collapse.isCollapsed(running([epic("acme/web", 5)], by: .repo), by: .repo))
}

// MARK: finished epics

private func ended(
    _ issue: Int, _ status: PanelSnapshot.FinishedEpic.Status, at: Int, repo: String = "acme/web", title: String? = nil, reason: String? = nil
) -> PanelSnapshot.FinishedEpic {
    .init(
        repo: repo, issue: issue, title: title, labels: [], prNumber: nil, finishedAt: at, status: status, cancelReason: reason, executionId: nil
    )
}

private func withFinished(_ finished: [PanelSnapshot.FinishedEpic], done: [PanelSnapshot.DoneEpic] = []) -> PanelSnapshot {
    var all = snapshot(done: done)
    all.finished = finished
    return all
}

@Test func doneAndCancelledComeAfterReadyForTestFilledByStatusAndStartCollapsed() {
    let all = withFinished(
        [ended(7, .merged, at: 100_000), ended(8, .cancelled, at: 90_000, reason: "final PR closed"), ended(9, .merged, at: 80_000)],
        done: [.init(repo: "acme/web", issue: 5, prNumber: 9, finishedAt: 5_000, executionId: nil)]
    )
    let groups = sidebarGroups(all, by: .status)
    #expect(groups.map(\.title) == ["Needs you", "Running", "Up next", "Ready for test", "Done", "Cancelled"])
    #expect(groups.map(\.startsCollapsed) == [false, false, false, false, true, true])
    #expect(groups[4].rows.map(\.issue) == [7, 9] && groups[4].rows.allSatisfy { $0.state == .done })
    #expect(groups[5].rows.map(\.issue) == [8] && groups[5].rows[0].state == .cancelled)
    let collapse = SidebarCollapse()
    #expect(groups.map { collapse.isCollapsed($0, by: .status) } == [false, false, false, false, true, true])
}

@Test func aFinishedGroupWithNoEpicsIsHiddenAndAnEngineWithoutTheFieldChangesNothing() {
    let onlyDone = sidebarGroups(withFinished([ended(7, .merged, at: 1)]), by: .status)
    #expect(onlyDone.map(\.title) == ["Needs you", "Running", "Up next", "Done"])
    let onlyCancelled = sidebarGroups(withFinished([ended(7, .cancelled, at: 1)]), by: .status)
    #expect(onlyCancelled.map(\.title) == ["Needs you", "Running", "Up next", "Cancelled"])
    #expect(sidebarGroups(withFinished([]), by: .status).map(\.title) == ["Needs you", "Running", "Up next"])
}

@Test func everyFinishedEpicIsListedWithNoCapInTheSnapshotsOrder() {
    let many = (1...40).map { ended($0, .merged, at: 1_000_000 - $0) }
    let rows = sidebarGroups(withFinished(many), by: .status)[3].rows
    #expect(rows.map(\.issue) == Array(1...40))
}

@Test func aFinishedRowHasRepoIssueTitleAndHowLongAgoAndACancelledOneItsReason() {
    let all = withFinished([
        ended(7, .merged, at: 5_000, title: "Add login"),
        ended(8, .cancelled, at: 5_000, title: "Add logout", reason: "final PR closed without merge"),
        ended(9, .cancelled, at: 5_000),
    ])
    let groups = sidebarGroups(all, by: .status)
    let done = groups[3].rows[0], cancelled = groups[4].rows
    #expect((done.name, done.issue, done.detail, done.tooltip) == ("web", 7, "2m ago", "Add login"))
    #expect(cancelled[0].detail == "2m ago · final PR closed without merge")
    #expect(cancelled[0].tooltip == "Add logout\nfinal PR closed without merge")
    #expect((cancelled[1].detail, cancelled[1].tooltip) == ("2m ago", "web #9"))
    #expect(cancelled[0].selection == .epic(repo: "acme/web", issue: 8))
}

@Test func theRepositoryGroupingLeavesFinishedEpicsOut() {
    let groups = sidebarGroups(withFinished([ended(7, .merged, at: 1), ended(8, .cancelled, at: 1)]), by: .repo)
    #expect(groups.isEmpty)
}

@Test func theCollapseOfDoneSurvivesANewSnapshot() {
    var collapse = SidebarCollapse()
    func done(_ epics: [PanelSnapshot.FinishedEpic]) -> SidebarGroup { sidebarGroups(withFinished(epics), by: .status)[3] }
    collapse.toggle(done([ended(7, .merged, at: 1)]), by: .status)
    #expect(collapse.isCollapsed(done([ended(7, .merged, at: 1), ended(8, .merged, at: 2)]), by: .status) == false)
}
