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
