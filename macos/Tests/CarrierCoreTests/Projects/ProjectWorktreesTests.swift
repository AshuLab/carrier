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
    let rows = worktreeRows(reply, now: now, format: format, bundle: english.bundle, locale: english.locale)
    #expect(rows.map(\.id) == ["/p/app", "/w/a", "/w/b", "/w/c", "/w/d", "/w/e"])
    #expect(rows[0] == WorktreeRow(id: "/p/app", branch: "main", session: nil, age: nil, state: nil, kind: nil))
    #expect(rows.dropFirst().map(\.state) == ["Session open", "Merged", "Uncommitted changes", "Not pushed", "Clean"])
    #expect(rows.dropFirst().map(\.age) == ["3d", "1d", "now", "12d", "2d"])
    // a session that has no title yet is still a session
    #expect(rows[4].session == "Untitled session" && rows[1].session == "Add retry")
    #expect(rows.map { $0.detail(bundle: english.bundle, locale: english.locale) } == ["Main clone", "Add retry · 3d", "Fix sync · 1d", "Spike · now", "Untitled session · 12d", "Done · 2d"])
}

@Test func aWorktreeWhoseSessionIsGoneSaysNoSessionAndOneWithNoBranchSaysDetached() {
    let reply = ProjectWorktrees(main: .init(path: "/p/app", branch: nil), worktrees: [
        .init(path: "/w/orphan", branch: nil, session: nil, lastActiveAt: ms(daysAgo: 40), state: .clean),
    ])
    let rows = worktreeRows(reply, now: now, format: format, bundle: english.bundle, locale: english.locale)
    #expect(rows[0].branch == "Detached HEAD")
    #expect(rows[1].detail(bundle: english.bundle, locale: english.locale) == "No session · 40d")
    #expect(rows[1] == WorktreeRow(id: "/w/orphan", branch: "Detached HEAD", session: "No session", age: "40d", state: "Clean", kind: .clean))
}

@Test func aProjectWithNoWorktreesHasOnlyItsMainClone() {
    #expect(worktreeRows(ProjectWorktrees(main: .init(path: "/p/app", branch: "main"), worktrees: []), now: now, format: format, bundle: english.bundle, locale: english.locale).count == 1)
}

@Test func theRemoveButtonIsOnEveryWorktreeAndOffOnlyWhileItsSessionIsOpen() {
    let reply = ProjectWorktrees(main: .init(path: "/p/app", branch: "main"), worktrees: [
        .init(path: "/w/a", branch: "carrier/a", session: .init(id: "1"), lastActiveAt: ms(daysAgo: 1), state: .sessionOpen),
        .init(path: "/w/b", branch: "carrier/b", session: .init(id: "2"), lastActiveAt: ms(daysAgo: 1), state: .uncommitted),
        .init(path: "/w/c", branch: "carrier/c", session: nil, lastActiveAt: ms(daysAgo: 1), state: .clean),
    ])
    let rows = worktreeRows(reply, now: now, format: format, bundle: english.bundle, locale: english.locale)
    #expect(rows.map(\.hasRemove) == [false, true, true, true])
    // an open session turns it off with the reason; uncommitted changes are the host's refusal, said when it is pressed
    #expect(rows.map { $0.removeBlockedBy(bundle: english.bundle, locale: english.locale) } == [nil, "Its session is open", nil, nil])
}

@Test func cleanUpSaysHowManyWorktreesAndHowMuchBeforeAndWhatWentAndWasSkippedAfter() {
    // the size is the system's own words, in the person's locale
    let size = { (bytes: Int64) in ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
    let one = ProjectCleanup(removed: [.init(path: "/w/a", bytes: 1_000_000_000)], skipped: [])
    #expect(cleanUpWords(one, bundle: english.bundle, locale: english.locale) == "1 worktree, \(size(1_000_000_000))")
    let two = ProjectCleanup(removed: [.init(path: "/w/a", bytes: 1_000_000_000), .init(path: "/w/b", bytes: 500_000_000)], skipped: [.init(path: "/h/worktrees/o/r/busy", reason: "Its session is open")])
    #expect(cleanUpWords(two, bundle: english.bundle, locale: english.locale) == "2 worktrees, \(size(1_500_000_000))")
    #expect(cleanUpReport(two, bundle: english.bundle, locale: english.locale) == "Removed 2 worktrees, \(size(1_500_000_000)). Their branches and sessions stay.\nSkipped busy: Its session is open.")
    // nothing to take hides the button; a report of nothing says so
    let none = ProjectCleanup(removed: [], skipped: [])
    #expect(cleanUpWords(none, bundle: english.bundle, locale: english.locale) == nil && cleanUpReport(none, bundle: english.bundle, locale: english.locale) == "Nothing to clean up.")
    #expect(cleanUpReport(.init(removed: [], skipped: [.init(path: "/w/x", reason: "It has uncommitted changes")]), bundle: english.bundle, locale: english.locale) == "Skipped x: It has uncommitted changes.")
}
