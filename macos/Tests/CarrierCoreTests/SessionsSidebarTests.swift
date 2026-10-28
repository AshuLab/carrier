import Foundation
import Testing
@testable import CarrierCore

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func row(
    _ id: String, _ workspace: String, title: String? = nil, agent: String = "Claude", minutesAgo: Int = 0, archived: Bool = false
) -> SessionRow {
    SessionRow(
        id: id, title: title ?? "t\(id)", workspace: workspace, agent: agent, state: .idle,
        updatedAt: now.addingTimeInterval(Double(-60 * minutesAgo)), archived: archived
    )
}

@Test func noRowsGiveNoGroups() { #expect(sessionGroups([]).isEmpty) }

@Test func oneGroupPerWorkspaceOrderedByNameIgnoringCase() {
    let groups = sessionGroups([row("1", "web"), row("2", "Carrier"), row("3", "dotfiles"), row("4", "web")])
    #expect(groups.map(\.title) == ["Carrier", "dotfiles", "web"])
}

@Test func rowsAreNewestFirst() {
    let groups = sessionGroups([row("old", "web", minutesAgo: 90), row("new", "web", minutesAgo: 1), row("mid", "web", minutesAgo: 30)])
    #expect(groups.count == 1)
    #expect(groups[0].rows.map(\.id) == ["new", "mid", "old"])
}

@Test func archivedRowsAreLeftOut() {
    let groups = sessionGroups([row("1", "web"), row("2", "web", archived: true), row("3", "gone", archived: true)])
    #expect(groups.map(\.title) == ["web"])
    #expect(groups[0].rows.map(\.id) == ["1"])
}

// A fixed calendar and clock: midnight is `midnight`, "noon" is 15:00 that day.
private let utc: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
private let midnight = Date(timeIntervalSince1970: 20_000 * 86400)
private let noon = midnight.addingTimeInterval(15 * 3600)

private func at(_ id: String, _ date: Date, state: SessionState = .idle, archived: Bool = false) -> SessionRow {
    SessionRow(id: id, title: "t\(id)", workspace: "w", agent: "Claude", state: state, updatedAt: date, archived: archived)
}

private func byAge(_ rows: [SessionRow]) -> [SessionGroup] { sessionGroups(rows, by: .age, now: noon, calendar: utc) }

@Test func ageBucketsBreakAtMidnight() {
    let groups = byAge([at("after", midnight.addingTimeInterval(1)), at("before", midnight.addingTimeInterval(-1))])
    #expect(groups.map(\.title) == ["Today", "Yesterday"])
    #expect(groups.map { $0.rows.map(\.id) } == [["after"], ["before"]])
}

@Test func ageSevenDaysBackIsTheEdgeOfLast7Days() {
    let edge = midnight.addingTimeInterval(-7 * 86400)
    let groups = byAge([at("edge", edge), at("older", edge.addingTimeInterval(-1)), at("yesterdayStart", midnight.addingTimeInterval(-86400))])
    #expect(groups.map(\.title) == ["Yesterday", "Last 7 days", "Older"])
    #expect(groups[1].rows.map(\.id) == ["edge"])
    #expect(groups[2].rows.map(\.id) == ["older"])
}

@Test func ageGroupsAreNewestFirstWithoutEmptyOnesOrArchivedRows() {
    let groups = byAge([at("a", noon.addingTimeInterval(-60)), at("b", noon.addingTimeInterval(-10)), at("x", noon, archived: true)])
    #expect(groups.map(\.title) == ["Today"])
    #expect(groups[0].rows.map(\.id) == ["b", "a"])
}

@Test func statusGroupsAreInOrderNewestFirstWithoutEmptyOnesOrArchivedRows() {
    let rows = [
        at("done", noon, state: .done), at("idleOld", noon.addingTimeInterval(-90), state: .idle), at("idleNew", noon.addingTimeInterval(-5), state: .idle),
        at("waiting", noon, state: .waiting), at("gone", noon, state: .working, archived: true),
    ]
    let groups = sessionGroups(rows, by: .status, now: noon, calendar: utc)
    #expect(groups.map(\.title) == ["Waiting for you", "Idle", "Done"])
    #expect(groups[1].rows.map(\.id) == ["idleNew", "idleOld"])
    #expect(sessionGroups([], by: .status, now: noon, calendar: utc).isEmpty)
    #expect(sessionGroups([], by: .age, now: noon, calendar: utc).isEmpty)
}

@Test func theAgeIsShort() {
    #expect(sessionAge(now.addingTimeInterval(-5), now: now) == "now")
    #expect(sessionAge(now.addingTimeInterval(-300), now: now) == "5m")
    #expect(sessionAge(now.addingTimeInterval(-3 * 3600), now: now) == "3h")
    #expect(sessionAge(now.addingTimeInterval(-2 * 86400), now: now) == "2d")
    #expect(sessionAge(now.addingTimeInterval(60), now: now) == "now")
}

private func found(_ rows: [SessionRow], _ query: String) -> [String] {
    sessionGroups(rows, query: query).flatMap(\.rows).map(\.id)
}

@Test func aQueryMatchesTheTitleTheWorkspaceAndTheAgent() {
    let rows = [
        row("title", "a", title: "Fix the login"), row("space", "login-app"), row("agent", "b", agent: "Codex"), row("none", "c"),
    ]
    #expect(found(rows, "login") == ["title", "space"])
    #expect(found(rows, "codex") == ["agent"])
}

@Test func aQueryIgnoresCase() {
    let rows = [row("1", "Carrier", title: "Retry the SYNC")]
    #expect(found(rows, "sync") == ["1"])
    #expect(found(rows, "CARRIER") == ["1"])
}

@Test func aQueryNeverListsAnArchivedSession() {
    let rows = [row("arch", "web", minutesAgo: 1, archived: true), row("old", "web", minutesAgo: 50), row("new", "carrier", minutesAgo: 5)]
    #expect(found(rows, "t") == ["new", "old"])
    #expect(found(rows, "tarch").isEmpty)
}

@Test func aQueryKeepsTheGroupsOfEachOrderAndHidesTheOnesWithNoMatch() {
    let rows = [
        at("a", noon, state: .waiting, archived: false), at("b", noon.addingTimeInterval(-60), state: .working),
        at("c", noon.addingTimeInterval(-86400), state: .working), at("x", noon.addingTimeInterval(-2 * 86400), state: .working, archived: true),
    ]
    func titles(_ sort: SessionSort, _ query: String) -> [[String]] {
        sessionGroups(rows, by: sort, query: query, now: noon, calendar: utc).map { $0.rows.map(\.id) }
    }
    #expect(titles(.workspace, "t") == [["a", "b", "c"]])
    #expect(titles(.age, "t") == [["a", "b"], ["c"]])
    #expect(titles(.age, "tc") == [["c"]])
    #expect(sessionGroups(rows, by: .age, query: "tc", now: noon, calendar: utc).map(\.title) == ["Yesterday"])
    #expect(titles(.status, "t") == [["a"], ["b", "c"]])
    #expect(sessionGroups(rows, by: .status, query: "tb", now: noon, calendar: utc).map(\.title) == ["Working"])
    #expect(titles(.status, "tx").isEmpty)
}

@Test func aQueryWithNoMatchGivesNoGroups() { #expect(sessionGroups([row("1", "web")], query: "zzz").isEmpty) }

@Test func anEmptyQueryGivesTheChosenOrder() {
    let rows = [row("1", "web"), row("2", "web", archived: true), row("3", "carrier")]
    #expect(sessionGroups(rows, query: "") == sessionGroups(rows))
    #expect(sessionGroups(rows, query: "  ") == sessionGroups(rows))
    #expect(sessionGroups(rows, query: "").map(\.title) == ["carrier", "web"])
}

@Test func aQueryThatMatchesAWorkspaceNameListsItsSessions() {
    let rows = [row("1", "dotfiles", title: "a"), row("2", "dotfiles", title: "b", minutesAgo: 3), row("3", "web", title: "c")]
    #expect(found(rows, "dotf") == ["1", "2"])
}

@Test func theOpenCountIsTheSessionsThatAreNotArchivedAndItsNameSaysSo() {
    func sessions(_ rows: [SessionRow]) -> Sessions { Sessions(rows: rows) }
    #expect(sessions([]).open == 0)
    #expect(sessions([at("a", noon, archived: true)]).open == 0)
    let one = sessions([at("a", noon, state: .waiting), at("b", noon, archived: true)])
    #expect(one.open == 1 && one.openLabel == "1 open session")
    let five = sessions((1...5).map { at("\($0)", noon, state: .working) } + [at("z", noon, archived: true)])
    #expect(five.open == 5 && five.openLabel == "5 open sessions")
}

@Test func theWaitingCountIsStillTheListedSessionsThatWait() {
    let rows = [at("a", noon, state: .waiting), at("b", noon, state: .waiting, archived: true), at("c", noon, state: .done)]
    #expect(Sessions(rows: rows).waiting == 1)
}

@Test func theArchivedCountIsZeroWithNoRowsOrNoneArchived() {
    #expect(archivedCount([]) == 0)
    #expect(archivedCount([row("1", "web"), row("2", "web")]) == 0)
}

@Test func theArchivedCountIsHowManyRowsAreArchived() {
    #expect(archivedCount([row("1", "web"), row("2", "web", archived: true), row("3", "gone", archived: true)]) == 2)
}

@Test func theArchivedCountIsEveryRowWhenAllAreArchived() {
    #expect(archivedCount([row("1", "web", archived: true), row("2", "web", archived: true)]) == 2)
}

@Test func aListWithRowsIsRowsWhateverTheQuery() {
    #expect(SidebarListState(shown: 3, of: 5, query: "") == .rows)
    #expect(SidebarListState(shown: 1, of: 5, query: "web") == .rows)
}

@Test func aListWithNothingToListIsEmptyEvenWithAQuery() {
    #expect(SidebarListState(shown: 0, of: 0, query: "") == .empty)
    #expect(SidebarListState(shown: 0, of: 0, query: "web") == .empty)
}

@Test func aQueryThatKeepsNoRowOfAListThatHasSomeIsNoMatchWithWhatWasTyped() {
    #expect(SidebarListState(shown: 0, of: 4, query: "  zzz \n") == .noMatch(query: "zzz"))
}

@Test func aBlankQueryNeverMakesNoMatch() {
    #expect(SidebarListState(shown: 0, of: 4, query: "   ") == .empty)
}

@Test func theNoResultsLineSaysWhatWasTyped() {
    #expect(EmptyState.noResultsLine(for: "zzz") == "Nothing matches “zzz”")
}

@Test func sessionsWithNoRowsOrOnlyArchivedOnesIsEmptyAndHasNothingOpen() {
    for rows in [[], [row("1", "web", archived: true)]] {
        let sessions = Sessions(rows: rows)
        #expect(sessions.open == 0)
        #expect(SidebarListState(shown: sessionGroups(sessions.rows).count, of: sessions.open, query: "") == .empty)
    }
}

@Test func sessionsWithAnOpenRowAreNotEmpty() {
    let sessions = Sessions(rows: [row("1", "web")])
    #expect(SidebarListState(shown: sessionGroups(sessions.rows).count, of: sessions.open, query: "") == .rows)
}

private func archivedByAge(_ rows: [SessionRow], _ query: String = "") -> [SessionGroup] {
    archivedGroups(rows, query: query, now: noon, calendar: utc)
}

@Test func archivedGroupsHoldOnlyArchivedRowsInTheAgeBucketsNewestFirst() {
    let day = 86400.0
    let groups = archivedByAge([
        at("open", noon, archived: false), at("old", noon.addingTimeInterval(-20 * day), archived: true),
        at("today", noon.addingTimeInterval(-60), archived: true), at("today2", noon.addingTimeInterval(-10), archived: true),
        at("older2", noon.addingTimeInterval(-30 * day), archived: true),
    ])
    #expect(groups.map(\.title) == ["Today", "Older"])
    #expect(groups.map { $0.rows.map(\.id) } == [["today2", "today"], ["old", "older2"]])
    #expect(groups.map(\.rows.count) == [2, 2])
}

@Test func archivedGroupsWithAQueryKeepTheBucketsWithAMatchOnTitleWorkspaceOrAgent() {
    let day = 86400.0
    let rows = [
        SessionRow(id: "title", title: "Spike OAuth", workspace: "a", agent: "Claude", state: .done, updatedAt: noon, archived: true),
        SessionRow(id: "space", title: "x", workspace: "oauth-app", agent: "Claude", state: .done, updatedAt: noon.addingTimeInterval(-20 * day), archived: true),
        SessionRow(id: "agent", title: "y", workspace: "b", agent: "Codex", state: .done, updatedAt: noon.addingTimeInterval(-3 * day), archived: true),
        SessionRow(id: "none", title: "z", workspace: "c", agent: "Claude", state: .done, updatedAt: noon.addingTimeInterval(-3 * day), archived: true),
        SessionRow(id: "open", title: "oauth", workspace: "oauth", agent: "Codex", state: .idle, updatedAt: noon, archived: false),
    ]
    #expect(archivedByAge(rows, "OAuth").map { $0.rows.map(\.id) } == [["title"], ["space"]])
    #expect(archivedByAge(rows, "OAuth").map(\.title) == ["Today", "Older"])
    #expect(archivedByAge(rows, "codex").map { $0.rows.map(\.id) } == [["agent"]])
    #expect(archivedByAge(rows, "  ").flatMap(\.rows).count == 4)
    #expect(archivedByAge(rows, "nothing like this").isEmpty)
}

@Test func archivedGroupsOfNoArchivedRowsAreEmptyAndTheListSaysNothingArchived() {
    for rows in [[], [at("open", noon)]] {
        #expect(archivedByAge(rows).isEmpty)
        #expect(SidebarListState(shown: archivedByAge(rows).count, of: archivedCount(rows), query: "") == .empty)
    }
    let rows = [at("a", noon, archived: true)]
    #expect(SidebarListState(shown: archivedByAge(rows, "zzz").count, of: archivedCount(rows), query: "zzz") == .noMatch(query: "zzz"))
}
