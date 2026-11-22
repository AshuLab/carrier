import Foundation
import Testing
@testable import CarrierCore

// The rows of a project's Worktrees and disk group (docs/specs/projects.md, Scope 13): what each says of its branch, session, age and state.

private let format = TimeFormat(style: .relative, hours: .h24, timeZone: TimeZone(identifier: "UTC")!)
private let now = Date(timeIntervalSince1970: 1_800_000_000)
private func ms(daysAgo days: Double) -> Double { (now.timeIntervalSince1970 - days * 86_400) * 1000 }

@Test func theWorktreeRowsListTheMainCloneFirstAndThenEachWorktreeInTheWordsOfItsState() {
    let reply = ProjectWorktrees(main: .init(path: "/p/app", branch: "main"), worktrees: [
        .init(path: "/w/a", branch: "carrier/a", session: .init(id: "1", title: "Add retry"), lastActiveAt: ms(daysAgo: 3), state: .sessionOpen),
        .init(path: "/w/b", branch: "carrier/b", session: .init(id: "2", title: "Fix sync"), lastActiveAt: ms(daysAgo: 1), state: .merged),
        .init(path: "/w/c", branch: "carrier/c", session: .init(id: "3", title: "Spike"), lastActiveAt: ms(daysAgo: 0), state: .uncommitted),
        .init(path: "/w/d", branch: "carrier/d", session: .init(id: "4"), lastActiveAt: ms(daysAgo: 12), state: .notPushed),
        .init(path: "/w/e", branch: "carrier/e", session: .init(id: "5", title: "Done"), lastActiveAt: ms(daysAgo: 2), state: .clean),
    ])
    let rows = worktreeRows(reply, now: now, format: format)
    #expect(rows.map(\.id) == ["/p/app", "/w/a", "/w/b", "/w/c", "/w/d", "/w/e"])
    #expect(rows[0] == WorktreeRow(id: "/p/app", branch: "main", session: nil, age: nil, state: nil, kind: nil))
    #expect(rows.dropFirst().map(\.state) == ["Session open", "Merged", "Uncommitted changes", "Not pushed", "Clean"])
    #expect(rows.dropFirst().map(\.age) == ["3d", "1d", "now", "12d", "2d"])
    // a session that has no title yet is still a session
    #expect(rows[4].session == "Untitled session" && rows[1].session == "Add retry")
    #expect(rows.map(\.detail) == ["Main clone", "Add retry · 3d", "Fix sync · 1d", "Spike · now", "Untitled session · 12d", "Done · 2d"])
}

@Test func aWorktreeWhoseSessionIsGoneSaysNoSessionAndOneWithNoBranchSaysDetached() {
    let reply = ProjectWorktrees(main: .init(path: "/p/app", branch: nil), worktrees: [
        .init(path: "/w/orphan", branch: nil, session: nil, lastActiveAt: ms(daysAgo: 40), state: .clean),
    ])
    let rows = worktreeRows(reply, now: now, format: format)
    #expect(rows[0].branch == "Detached HEAD")
    #expect(rows[1].detail == "No session · 40d")
    #expect(rows[1] == WorktreeRow(id: "/w/orphan", branch: "Detached HEAD", session: "No session", age: "40d", state: "Clean", kind: .clean))
}

@Test func aProjectWithNoWorktreesHasOnlyItsMainClone() {
    #expect(worktreeRows(ProjectWorktrees(main: .init(path: "/p/app", branch: "main"), worktrees: []), now: now, format: format).count == 1)
}
