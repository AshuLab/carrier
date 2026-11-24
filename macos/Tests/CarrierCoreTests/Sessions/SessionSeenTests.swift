import Foundation
import Testing
@testable import CarrierCore

private func row(_ id: String, _ state: SessionState = .idle, at seconds: Double, asleep: Bool = false) -> SessionRow {
    SessionRow(id: id, title: id, workspace: "w", agent: "a", state: state, updatedAt: Date(timeIntervalSince1970: seconds), asleep: asleep)
}

@Test func aSessionMetForTheFirstTimeIsSeenAndOneThatAnsweredSinceIsUnread() {
    var seen = SessionSeen()
    var rows = [row("a", at: 100), row("b", at: 100)]
    #expect(seen.apply(to: &rows, viewing: nil) && rows.allSatisfy { $0.unread == false })
    // b answers later; a does not move
    rows = [row("a", at: 100), row("b", at: 200)]
    #expect(seen.apply(to: &rows, viewing: nil) == false)
    #expect(rows.map(\.unread) == [false, true] && rows.map(\.status) == [.idle, .unread])
}

@Test func theSessionBeingViewedIsSeenAsItMovesAndALeftOneKeepsWhatItSaw() {
    var seen = SessionSeen()
    var rows = [row("a", at: 100)]
    _ = seen.apply(to: &rows, viewing: nil)
    rows = [row("a", at: 150)]
    _ = seen.apply(to: &rows, viewing: "a")
    #expect(rows[0].unread == false)
    // leaving it, a reply that came since is unread; a working or waiting session is never unread
    rows = [row("a", at: 300)]
    _ = seen.apply(to: &rows, viewing: nil)
    #expect(rows[0].unread)
    rows = [row("a", .working, at: 400)]
    _ = seen.apply(to: &rows, viewing: nil)
    #expect(rows[0].unread == false && rows[0].status == .working)
}

@Test func markingASessionSeenClearsItAndTheGoneAreForgotten() {
    var seen = SessionSeen()
    var rows = [row("a", at: 100), row("gone", at: 100)]
    _ = seen.apply(to: &rows, viewing: nil)
    rows = [row("a", at: 200)]
    seen.markSeen("a", in: rows)
    _ = seen.apply(to: &rows, viewing: nil)
    #expect(rows[0].unread == false)
    let defaults = UserDefaults(suiteName: "seen-\(UUID().uuidString)")!
    seen.store(in: defaults)
    #expect(SessionSeen.stored(in: defaults) == seen)
}

@Test func theFiveStatusesFollowTheStateTheAsleepAndTheUnreadFlags() {
    func status(_ state: SessionState, asleep: Bool = false, unread: Bool = false) -> SessionStatus {
        var r = row("x", state, at: 0, asleep: asleep)
        r.unread = unread
        return r.status
    }
    #expect(status(.waiting) == .needsYou && status(.working) == .working && status(.idle) == .idle)
    #expect(status(.idle, asleep: true) == .asleep && status(.idle, asleep: true, unread: true) == .unread)
    let groups = sessionGroups([row("a", .waiting, at: 1), row("b", at: 2, asleep: true), row("c", .working, at: 3), row("d", at: 4)], by: .status)
    #expect(groups.map(\.title) == ["Needs you", "Working", "Idle", "Asleep"])
}
