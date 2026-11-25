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

/// What the row's clock says after the app saw `row` go by, as `PanelModel` does with every refresh.
private func since(_ keeper: inout WorkingOrder, _ row: SessionRow) -> Date? {
    var rows = [row]
    keeper.apply(to: &rows)
    return rows[0].workingSince
}

@Test func aTurnCountsFromWhenItWasFirstSeenWorkingAndWaitingKeepsTheCount() {
    var keeper = WorkingOrder()
    let start = Date(timeIntervalSince1970: 1000)
    #expect(since(&keeper, row(.working, updatedAt: start)) == start)
    // more events move the last activity, the start stays
    #expect(since(&keeper, row(.working, updatedAt: start.addingTimeInterval(60))) == start)
    #expect(since(&keeper, row(.waiting, updatedAt: start.addingTimeInterval(90))) == nil)
    #expect(since(&keeper, row(.working, updatedAt: start.addingTimeInterval(120))) == start)
    // the turn ends, and the next one starts a new count
    #expect(since(&keeper, row(.idle, updatedAt: start.addingTimeInterval(200))) == nil)
    let next = start.addingTimeInterval(300)
    #expect(since(&keeper, row(.working, updatedAt: next)) == next)
}

@Test func aTurnThatEndedWhileTheAgentWaitsForWhatItStartedKeepsTheCountUntilThatEndsOrANewTurnBegins() {
    var keeper = WorkingOrder()
    let start = Date(timeIntervalSince1970: 1000)
    let task = [BackgroundTask(id: "b", kind: "local_bash", description: "pnpm build")]
    func waiting(_ updatedAt: Date) -> SessionRow {
        var row = SessionRow(id: "s", title: "t", workspace: "w", agent: "a", state: .idle, updatedAt: updatedAt)
        row.background = task
        return row
    }
    #expect(since(&keeper, row(.working, updatedAt: start)) == start)
    // the turn ended and the build runs: the same count goes on, and the row is working
    #expect(waiting(start.addingTimeInterval(30)).isWorking && waiting(start.addingTimeInterval(30)).status == .working)
    #expect(since(&keeper, waiting(start.addingTimeInterval(30))) == start)
    #expect(since(&keeper, waiting(start.addingTimeInterval(200))) == start)
    // the person writes again while the build runs: that turn counts alone
    let next = start.addingTimeInterval(250)
    var turn = row(.working, updatedAt: next)
    turn.background = task
    #expect(since(&keeper, turn) == next)
    // the build ended: idle again, and the count with it
    #expect(since(&keeper, row(.idle, updatedAt: start.addingTimeInterval(300))) == nil)
}
