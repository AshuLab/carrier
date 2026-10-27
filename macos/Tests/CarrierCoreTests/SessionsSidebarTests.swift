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

@Test func aQueryGivesOneFlatGroupWithTheActiveFirstAndTheArchivedAfterNewestFirst() {
    let rows = [
        row("arch-new", "web", minutesAgo: 1, archived: true), row("old", "web", minutesAgo: 50), row("new", "carrier", minutesAgo: 5),
        row("arch-old", "web", minutesAgo: 900, archived: true),
    ]
    let groups = sessionGroups(rows, query: "t")
    #expect(groups.count == 1)
    #expect(groups[0].rows.map(\.id) == ["new", "old", "arch-new", "arch-old"])
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
