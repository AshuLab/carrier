import Foundation
import Testing
@testable import CarrierCore

private let fixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")

/// The fixture: web #12 in review (round 2/5, 3 of 5 slices) and web #13 in ship, 2 of 3 slots busy, two epics queued.
private func load(_ change: (inout PanelSnapshot) -> Void = { _ in }) throws -> PanelSnapshot {
    var snapshot = try decodeSnapshot(Data(contentsOf: fixtures.appendingPathComponent("snapshot.json")))
    change(&snapshot)
    return snapshot
}

private let utc = TimeZone(identifier: "UTC")!

@Test func nothingRunningHasNoCardsAndNamesTheRoom() throws {
    let section = runningSection(try load { $0.epics = []; $0.slots.busy = 0 }, timeZone: utc)
    #expect(section.cards.isEmpty)
    #expect(section.room == FreeRoom(title: "3 free", line: "web #20 starts on the next check"))
}

@Test func partlyFullShowsACardPerRunningEpicAndHowMuchIsFree() throws {
    let section = runningSection(try load(), timeZone: utc)
    #expect(section.cards.map(\.title) == ["Issue 12 of acme/web", "Issue 13 of acme/web"])
    #expect(section.cards[0].subtitle == "acme/web · #12")
    #expect(section.cards[0].selection == .epic(repo: "acme/web", issue: 12))
    #expect(section.room == FreeRoom(title: "1 free", line: "web #20 starts on the next check"))
}

@Test func fullWithAQueueSaysTheNextOneStartsWhenOneFinishes() throws {
    let room = runningSection(try load { $0.slots.busy = 3 }, timeZone: utc).room
    #expect(room == FreeRoom(title: "All 3 in use", line: "web #20 starts when one finishes"))
}

@Test func fullWithNoQueueSaysNothingIsWaiting() throws {
    let room = runningSection(try load { $0.slots.busy = 3; $0.queue = [] }, timeZone: utc).room
    #expect(room == FreeRoom(title: "All 3 in use", line: "Nothing waiting"))
}

@Test func progressIsSlicesMergedInShipAndRoundOverMaximumOtherwise() throws {
    let snapshot = try load { $0.epics[1].slices = .init(done: 1, total: 4) }
    let cards = runningSection(snapshot, timeZone: utc).cards
    #expect(cards[0].progressLine == "round 2/5" && cards[0].progress == 0.4)
    #expect(cards[1].progressLine == "1/4 slices" && cards[1].progress == 0.25)
}

@Test func anEpicWithNothingToCountYetHasNoBar() throws {
    let cards = runningSection(try load(), timeZone: utc).cards
    #expect(cards[1].progressLine == "ship" && cards[1].progress == nil)
    let starting = runningSection(try load { $0.epics[1].stage = nil }, timeZone: utc).cards[1]
    #expect(starting.progressLine == "starting" && starting.progress == nil)
}

@Test func anAgentRowHasTheAgentRoleRoundActionAndStart() throws {
    let rows = runningSection(try load { $0.sessions![0].startedAt = 1_700_000_000_000 }, timeZone: utc).cards[0].agents
    #expect(rows == [
        AgentRow(
            agent: "Codex", initial: "X", role: "Reviewer", round: "round 2/5", action: "Read src/auth/token.ts",
            since: "since 22:13", running: true
        )
    ])
}

@Test func aShipRowHasNoRoundAndABuilderRole() throws {
    let row = try #require(runningSection(try load(), timeZone: utc).cards[1].agents.first)
    #expect(row.agent == "Claude" && row.initial == "C" && row.role == "Builder" && row.round == nil)
    #expect(row.action == "Writing the migration")
}

@Test func aSessionWithoutAnEventSaysWorking() throws {
    let row = try #require(runningSection(try load { $0.sessions![1].last = nil }, timeZone: utc).cards[1].agents.first)
    #expect(row.action == "working")
}

@Test func aRunningEpicWithNoSessionsYetHasACardWithoutRows() throws {
    #expect(runningSection(try load { $0.sessions = [] }, timeZone: utc).cards.allSatisfy { $0.agents.isEmpty })
    #expect(runningSection(try load { $0.sessions = nil }, timeZone: utc).cards.count == 2)
}

@Test func theRowSaysItIsNotRunningWhenItsEpicIsNotRunning() throws {
    let snapshot = try load()
    var epic = snapshot.epics[0]
    #expect(agentRow(snapshot.sessions![0], epic: epic, timeZone: utc).running)
    epic.status = .needsHuman
    #expect(agentRow(snapshot.sessions![0], epic: epic, timeZone: utc).running == false)
}
