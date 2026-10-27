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
    #expect(rows[1].rows.map(\.tooltip) == ["web #4\nacme/web", "Add login\nacme/web"])
    #expect(rows[2].rows[0].tooltip == "api #6\nacme/api")
}

@Test func aRowLeadsWithItsTitleAndNamesItsRepositoryOnTheRightOnlyWhenGroupedByStatus() {
    let all = snapshot([epic("acme/web", 4), epic("acme/web", 5, title: "Add login"), epic("acme/web", 6, title: "")])
    let byStatus = sidebarGroups(all, by: .status)[1].rows
    #expect(byStatus.map(\.title) == [nil, "Add login", nil])
    #expect(byStatus.map(\.repoLabel) == [nil, "web", nil])
    let byRepo = sidebarGroups(all, by: .repo)[0].rows
    #expect(byRepo.map(\.title) == [nil, "Add login", nil])
    #expect(byRepo.map(\.repoLabel) == [nil, nil, nil])
    #expect(byStatus.map(\.name) == ["web", "web", "web"])
}

@Test func theTooltipIsTheFullTitleThenOwnerAndName() {
    let long = String(repeating: "a long title ", count: 12)
    let rows = sidebarGroups(snapshot([epic("acme/web", 5, title: long)]), by: .repo)[0].rows
    #expect(rows[0].tooltip == "\(long)\nacme/web")
}

@Test func theGroupsOfAnEmptySnapshotAreEmpty() {
    #expect(sidebarGroups(snapshot(), by: .repo).isEmpty)
    #expect(sidebarGroups(snapshot(), by: .status).allSatisfy { $0.rows.isEmpty })
}

@Test func theCardStateFollowsTheConnection() {
    func card(_ snapshot: PanelSnapshot) -> CarrierCardState { carrierCardState(.running(snapshot)) }
    var paused = snapshot(busy: 1)
    paused.paused = true
    var problem = snapshot(busy: 3)
    problem.problem = "GitHub is not answering"
    var both = problem
    both.paused = true

    #expect(card(snapshot(busy: 2)) == CarrierCardState(kind: .running, slots: (2, 3)))
    #expect(card(paused) == CarrierCardState(kind: .paused, slots: (1, 3)))
    #expect(card(problem) == CarrierCardState(kind: .problem, slots: (3, 3)))
    #expect(card(both).kind == .problem)
    #expect(carrierCardState(.stopped) == CarrierCardState(kind: .stopped, slots: nil))
    #expect(carrierCardState(.incompatible) == CarrierCardState(kind: .problem, slots: nil))
    #expect(carrierCardState(nil) == CarrierCardState(kind: .connecting, slots: nil))
    #expect([card(snapshot()), card(paused), card(problem), carrierCardState(.stopped), carrierCardState(nil)].map(\.title)
        == ["Running", "Paused", "Problem", "Stopped", "Connecting"])
}

@Test func theCountersLeaveOutTheFinishedEpics() {
    let all = snapshot(
        [epic("a/b", 1), epic("a/b", 2), epic("a/b", 3, .needsHuman)], queue: [queued("a/b", 4), queued("a/b", 5), queued("a/b", 6)],
        done: [.init(repo: "a/b", issue: 7, prNumber: 9, finishedAt: 5_000, executionId: nil)]
    )
    #expect(carrierCounters(all) == CarrierCounters(needsYou: 1, running: 2, next: 3, ready: 1))
    #expect(carrierCounters(snapshot()) == CarrierCounters(needsYou: 0, running: 0, next: 0, ready: 0))
    var withFinished = all
    withFinished.finished = [.init(repo: "a/b", issue: 8, title: nil, labels: [], prNumber: nil, finishedAt: 1, status: .merged, cancelReason: nil, executionId: nil), .init(repo: "a/b", issue: 9, title: nil, labels: [], prNumber: nil, finishedAt: 1, status: .cancelled, cancelReason: nil, executionId: nil)]
    #expect(carrierCounters(withFinished) == carrierCounters(all))
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

@Test func theSessionSortSurvivesARelaunch() {
    let name = "carrier-sidebar-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    #expect(SidebarStore(defaults: defaults).sessionSort == .workspace)
    SidebarStore(defaults: defaults).sessionSort = .status
    #expect(SidebarStore(defaults: defaults).sessionSort == .status)
    defaults.set("nonsense", forKey: "sidebar.sessionSort")
    #expect(SidebarStore(defaults: defaults).sessionSort == .workspace)
}

@Test func theOpenSectionSurvivesARelaunchAndANonsenseValueGivesSessions() {
    let name = "carrier-sidebar-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    #expect(SidebarStore(defaults: defaults).open == .sessions)
    SidebarStore(defaults: defaults).open = .carrier
    #expect(SidebarStore(defaults: defaults).open == .carrier)
    SidebarStore(defaults: defaults).open = nil
    #expect(SidebarStore(defaults: defaults).open == nil)
    SidebarStore(defaults: defaults).open = .sessions
    #expect(defaults.string(forKey: "sidebar.open") == "sessions")
    defaults.set("nonsense", forKey: "sidebar.open")
    #expect(SidebarStore(defaults: defaults).open == .sessions)
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
    #expect((done.name, done.issue, done.detail, done.tooltip) == ("web", 7, "2m ago", "Add login\nacme/web"))
    #expect(cancelled[0].detail == "2m ago · final PR closed without merge")
    #expect(cancelled[0].tooltip == "Add logout\nacme/web\nfinal PR closed without merge")
    #expect((cancelled[1].detail, cancelled[1].tooltip) == ("2m ago", "web #9\nacme/web"))
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

@Test func onlyAStuckEpicHasAnAttentionAndItsKindDecidesWhich() {
    func attention(_ kind: String?) -> Attention? {
        sidebarGroups(snapshot([epic("a/b", 1, .needsHuman, kind: kind)]), by: .status)[0].rows[0].attention
    }
    #expect(attention("review_limit") == .input && attention("agent_needs_human") == .input)
    #expect(attention("timeout") == .error)
    #expect(attention("from_the_future") == .input && attention(nil) == .input)
    let others = snapshot([epic("a/b", 1)], queue: [queued("a/b", 2)])
    #expect(sidebarGroups(others, by: .status).flatMap(\.rows).allSatisfy { $0.attention == nil })
}

// MARK: search

private func searchable() -> PanelSnapshot {
    var all = snapshot(
        [epic("acme/web", 12, title: "Add Login page"), epic("acme/api", 7, .needsHuman, title: "Fix timeout")],
        queue: [queued("acme/web", 120)],
        done: [.init(repo: "acme/api", issue: 31, prNumber: 9, finishedAt: 5_000, executionId: nil)]
    )
    all.finished = [
        ended(40, .merged, at: 100_000, title: "Ship the dashboard"), ended(41, .cancelled, at: 90_000, repo: "acme/docs", title: "Rewrite the guide"),
    ]
    return all
}

private func found(_ query: String, by: GroupBy = .status) -> [String] {
    sidebarGroups(searchable(), by: by, query: query).flatMap { group in group.rows.map { "\(group.title):\($0.issue)" } }
}

@Test func aQueryMatchesTheTitleIgnoringCase() {
    #expect(found("login") == ["Running:12"])
    #expect(found("LOGIN") == ["Running:12"])
    #expect(found("  login ") == ["Running:12"])
}

@Test func aQueryMatchesTheIssueNumberWithOrWithoutTheHash() {
    #expect(found("7") == ["Needs you:7"])
    #expect(found("#7") == ["Needs you:7"])
    #expect(found("#31") == ["Ready for test:31"])
    #expect(found("#12") == ["Running:12", "Up next:120"])
    #expect(found("#") == [])
}

@Test func aQueryMatchesTheRepositoryOwnerAndName() {
    #expect(found("acme/api") == ["Needs you:7", "Ready for test:31"])
    #expect(found("ACME/WEB") == ["Running:12", "Up next:120", "Done:40"])
    #expect(found("docs") == ["Cancelled:41"])
}

@Test func aQueryReachesDoneAndCancelled() {
    #expect(found("dashboard") == ["Done:40"])
    #expect(found("guide") == ["Cancelled:41"])
    #expect(found("#41") == ["Cancelled:41"])
}

@Test func aQueryKeepsTheGroupsAndHidesTheEmptyOnes() {
    let groups = sidebarGroups(searchable(), by: .status, query: "acme")
    #expect(groups.map(\.title) == ["Needs you", "Running", "Up next", "Ready for test", "Done", "Cancelled"])
    #expect(groups.map(\.startsCollapsed) == [false, false, false, false, true, true])
    #expect(sidebarGroups(searchable(), by: .status, query: "dashboard").map(\.title) == ["Done"])
    #expect(sidebarGroups(searchable(), by: .status, query: "nothing like this").isEmpty)
}

@Test func theRepositoryGroupingFiltersItsOwnSections() {
    let groups = sidebarGroups(searchable(), by: .repo, query: "#12")
    #expect(groups.map(\.title) == ["web"])
    #expect(groups[0].rows.map(\.issue) == [12, 120])
    #expect(found("acme/api", by: .repo) == ["api:7", "api:31"])
    // finished epics are only in the repository sections while a query is typed
    #expect(found("guide", by: .repo) == ["docs:41"])
    #expect(found("dashboard", by: .repo) == ["web:40"])
    #expect(sidebarGroups(searchable(), by: .repo).flatMap(\.rows).map(\.issue).contains(41) == false)
}

@Test func anEmptyQueryChangesNothing() {
    for by in GroupBy.allCases {
        #expect(sidebarGroups(searchable(), by: by, query: "") == sidebarGroups(searchable(), by: by))
        #expect(sidebarGroups(searchable(), by: by, query: "  ") == sidebarGroups(searchable(), by: by))
    }
}

@Test func aCollapsedGroupShowsOpenWhileThereIsAQueryAndGoesBackWhenItIsCleared() throws {
    let done = try #require(sidebarGroups(searchable(), by: .status, query: "dashboard").first)
    var collapse = SidebarCollapse()
    #expect(collapse.isCollapsed(done, by: .status, query: ""))
    #expect(collapse.isCollapsed(done, by: .status, query: "dashboard") == false)
    // a group the user opened and closed again stays closed once the query goes
    collapse.toggle(done, by: .status)
    collapse.toggle(done, by: .status)
    #expect(collapse.isCollapsed(done, by: .status, query: "dashboard") == false)
    #expect(collapse.isCollapsed(done, by: .status, query: ""))
}

@Test func theGroupingIsRememberedForEachChoiceAndTheQueryIsNot() {
    let suite = "SidebarTests.search.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    for by in GroupBy.allCases {
        SidebarStore(defaults: defaults).groupBy = by
        #expect(SidebarStore(defaults: defaults).groupBy == by)
    }
    #expect(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("sidebar.") } == ["sidebar.groupBy"])
}
