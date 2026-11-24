import Foundation
import Testing

@testable import CarrierCore

@Test func theMenuListsWhatWaitsForThePersonFirstAndAtMostFourThenTheRestApart() {
    let base = Date(timeIntervalSince1970: 1_000_000)
    func row(_ id: String, _ state: SessionState, at seconds: Double, archived: Bool = false) -> SessionRow {
        var row = SessionRow(id: id, title: id, workspace: "w", agent: "a", state: state, updatedAt: base.addingTimeInterval(seconds))
        row.archived = archived
        return row
    }
    let rows = [
        row("old-wait", .waiting, at: 10), row("new", .idle, at: 500), row("work", .working, at: 400), row("new-wait", .waiting, at: 300),
        row("mid", .idle, at: 200), row("gone", .idle, at: 900, archived: true), row("older", .idle, at: 100),
    ]
    let menu = menuSessions(rows)
    // the two that wait, the newer first, then the newest of the others; the archived one is nowhere
    #expect(menu.shown.map(\.id) == ["new-wait", "old-wait", "new", "work"])
    #expect(menu.more.map(\.id) == ["mid", "older"])
    #expect(menuSessions(rows, limit: 4, moreLimit: 1).more.map(\.id) == ["mid"])
    #expect(menuSessions([]).shown.isEmpty)
}
