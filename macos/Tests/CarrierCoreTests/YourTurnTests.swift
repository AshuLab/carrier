import Foundation
import Testing
@testable import CarrierCore

private let fixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")

private func load(_ change: (inout PanelSnapshot) -> Void = { _ in }) throws -> PanelSnapshot {
    var snapshot = try decodeSnapshot(Data(contentsOf: fixtures.appendingPathComponent("snapshot.json")))
    change(&snapshot)
    return snapshot
}

/// The fixture with only the named api epics (#4 review limit, finished at 60s; #5 agent needs a person, finished at 61s) and the running ones.
private func small(_ issues: Set<Int> = [4, 5], _ change: (inout PanelSnapshot) -> Void = { _ in }) throws -> PanelSnapshot {
    try load { snapshot in
        snapshot.epics = snapshot.epics.filter { $0.status == .running || issues.contains($0.issue) }
        change(&snapshot)
    }
}

@Test func theEngineProblemComesFirstThenEpicsThatNeedAPersonThenFinishedOnes() throws {
    let items = yourTurn(try small())
    #expect(items.map(\.kind) == [.problem, .needsYou, .needsYou, .ready, .ready])
    #expect(items[0].title == "Carrier" && items[0].detail == "GitHub is not answering" && items[0].selection == nil)
}

@Test func needsYouEpicsComeMostRecentFirstWithTheirKindAndAnIssueLink() throws {
    let items = yourTurn(try small()).filter { $0.kind == .needsYou }
    #expect(items.map(\.title) == ["api #5", "api #4"])
    #expect(items[1].detail == "Review limit reached (5/5) · review limit · 40s ago")
    #expect(items[1].selection == .epic(repo: "acme/api", issue: 4))
    #expect(items[1].issueLink == URL(string: "https://github.com/acme/api/issues/4"))
    #expect(items[1].prLink == nil)
    #expect(items[0].detail.hasPrefix("The agent needs you"))
}

@Test func blockersAreCountedOnlyWhenThereAreSome() throws {
    let some = yourTurn(try small([4]) { $0.epics[2].blockers = 2 })
    #expect(some.first { $0.title == "api #4" }?.detail.contains("2 blockers open") == true)
    let none = yourTurn(try small([4])).first { $0.title == "api #4" }
    #expect(none?.detail.contains("blocker") == false)
}

@Test func finishedEpicsShowTheirPRAndOpenIt() throws {
    let items = yourTurn(try small()).filter { $0.kind == .ready }
    #expect(items.map(\.title) == ["web #30", "api #31"])
    #expect(items[0].detail == "Ready for test · PR #77 · 5s ago")
    #expect(items[0].prLink == URL(string: "https://github.com/acme/web/pull/77"))
    #expect(items[0].issueLink == nil)
    #expect(items[0].selection == .epic(repo: "acme/web", issue: 30))
    #expect(items[1].detail == "Ready for test · 20s ago" && items[1].prLink == nil)
}

@Test func linksThatAreNotWebLinksAreDropped() throws {
    let items = yourTurn(try small([4]) { $0.epics[2].issueUrl = "file:///etc/passwd" })
    #expect(items.first { $0.title == "api #4" }?.issueLink == nil)
}

@Test func withNothingToDoThereAreNoItems() throws {
    #expect(yourTurn(try small([]) { $0.problem = nil; $0.done = [] }).isEmpty)
}

@Test func anEngineProblemAloneIsOneItemAndWithEpicsItStaysFirst() throws {
    #expect(yourTurn(try small([]) { $0.done = [] }).map(\.kind) == [.problem])
    let together = yourTurn(try small([4]) { $0.done = [] })
    #expect(together.map(\.kind) == [.problem, .needsYou])
}

@Test func anEpicWithoutAKindFallsBackToItsReason() throws {
    let items = yourTurn(try small([4]) { $0.epics[2].needsHumanKind = nil; $0.epics[2].needsHumanReason = "stuck on CI" })
    #expect(items.first { $0.title == "api #4" }?.detail.hasPrefix("Stuck on CI") == true)
}
