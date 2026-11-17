import Foundation
import Testing
@testable import CarrierCore

private func row(_ state: SessionState, updatedAt: Date) -> SessionRow {
    SessionRow(id: "s", title: "t", workspace: "w", agent: "a", state: state, updatedAt: updatedAt)
}

@Test func theStopwatchSaysItsUnits() {
    #expect(workingElapsed(0) == "0s" && workingElapsed(42) == "42s" && workingElapsed(725) == "12m 05s" && workingElapsed(3730) == "1h 02m")
    #expect(workingElapsed(97_200) == "1d 3h" && workingElapsed(-5) == "0s")
}

@MainActor @Test func aTurnCountsFromWhenItWasFirstSeenWorkingAndWaitingKeepsTheCount() {
    let clock = WorkingClock()
    let start = Date(timeIntervalSince1970: 1000)
    #expect(clock.since(row(.working, updatedAt: start)) == start)
    // more events move the last activity, the start stays
    #expect(clock.since(row(.working, updatedAt: start.addingTimeInterval(60))) == start)
    #expect(clock.since(row(.waiting, updatedAt: start.addingTimeInterval(90))) == nil)
    #expect(clock.since(row(.working, updatedAt: start.addingTimeInterval(120))) == start)
    // the turn ends, and the next one starts a new count
    #expect(clock.since(row(.idle, updatedAt: start.addingTimeInterval(200))) == nil)
    let next = start.addingTimeInterval(300)
    #expect(clock.since(row(.working, updatedAt: next)) == next)
}

@MainActor @Test func aTurnThatEndedWhileTheAgentWaitsForWhatItStartedKeepsTheCountUntilThatEnds() {
    let clock = WorkingClock()
    let start = Date(timeIntervalSince1970: 1000)
    let task = [BackgroundTask(id: "b", kind: "local_bash", description: "pnpm build")]
    func waiting(_ updatedAt: Date) -> SessionRow {
        var row = SessionRow(id: "s", title: "t", workspace: "w", agent: "a", state: .idle, updatedAt: updatedAt)
        row.background = task
        return row
    }
    #expect(clock.since(row(.working, updatedAt: start)) == start)
    // the turn ended and the build runs: the same count goes on, and the row is working
    #expect(waiting(start.addingTimeInterval(30)).isWorking && waiting(start.addingTimeInterval(30)).status == .working)
    #expect(clock.since(waiting(start.addingTimeInterval(30))) == start)
    #expect(clock.since(waiting(start.addingTimeInterval(200))) == start)
    // the build ended: idle again, and the count with it
    #expect(clock.since(row(.idle, updatedAt: start.addingTimeInterval(300))) == nil)
}
