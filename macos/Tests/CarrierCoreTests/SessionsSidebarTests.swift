import Foundation
import Testing
@testable import CarrierCore

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func row(_ id: String, _ workspace: String, minutesAgo: Int = 0, archived: Bool = false) -> SessionRow {
    SessionRow(
        id: id, title: "t\(id)", workspace: workspace, agent: "Claude", state: .idle,
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

@Test func theSampleHasEachStateSeveralWorkspacesAndArchivedRows() {
    let sample = sampleSessions(now: now)
    let listed = sample.filter { $0.archived == false }
    #expect(Set(listed.map(\.state)).count == 4)
    #expect(Set(listed.map(\.workspace)).count > 1)
    #expect(sample.contains { $0.archived })
    #expect(sessionGroups(sample).flatMap(\.rows).contains { $0.archived } == false)
}
