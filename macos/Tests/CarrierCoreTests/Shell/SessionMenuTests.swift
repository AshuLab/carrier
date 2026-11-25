import Foundation
import Testing

@testable import CarrierCore

private func row(_ id: String, state: SessionState = .idle, archived: Bool = false, branch: String? = nil, workspace: String = "web") -> SessionRow {
    var row = SessionRow(id: id, title: "t", workspace: workspace, agent: "claude", state: state, updatedAt: Date(timeIntervalSince1970: 1_000), folder: "/Users/dev/web")
    row.archived = archived
    row.branch = branch
    return row
}

private func titles(_ sections: [[SessionMenuItem]]) -> [[String]] { sections.map { $0.map(\.title) } }

@Test func anIdleSessionMenuHasPinRenameOpenCopyArchiveAndDelete() {
    #expect(titles(sessionMenu(row("a"))) == [["Pin"], ["Rename…"], ["Open in Terminal", "Copy"], ["Archive", "Delete…"]])
}

@Test func theWindowsListsAddMarkAsUnreadNewSessionOnTheBranchAndProjectSettings() {
    let context = SessionMenuContext(marksUnread: true, startsSessions: true, projectKnown: true)
    #expect(titles(sessionMenu(row("a", branch: "fix/x"), context: context)) == [
        ["Pin", "Mark as unread"], ["Rename…"], ["New session on fix/x", "Project settings…", "Open in Terminal", "Copy"], ["Archive", "Delete…"]])
    let items = sessionMenu(row("a", branch: "fix/x"), context: context).flatMap { $0 }
    #expect(items.first { $0.title == "Mark as unread" }?.action == .markUnread)
    #expect(items.first { $0.title == "New session on fix/x" }?.action == .newSession(base: "/Users/dev/web", branch: "fix/x"))
    #expect(items.first { $0.title == "Project settings…" }?.action == .openProject(base: "/Users/dev/web"))
}

@Test func markAsUnreadBecomesMarkAsReadAndIsOffForTheOpenSessionAndAbsentForAnArchivedOne() {
    var unread = row("a")
    unread.unread = true
    let marks = { (row: SessionRow, viewing: Bool) in sessionMenu(row, context: SessionMenuContext(marksUnread: true, viewing: viewing)).flatMap { $0 }.first { $0.title.hasPrefix("Mark as") } }
    #expect(marks(unread, false)?.title == "Mark as read" && marks(unread, false)?.action == .markRead)
    #expect(marks(row("a"), true)?.disabledReason != nil && marks(row("a"), false)?.disabledReason == nil)
    #expect(marks(row("a", archived: true), false) == nil)
}

@Test func newSessionSaysTheBranchShortenedOrTheProjectWhenTheSessionWorksInTheFolder() {
    #expect(newSessionTitle(row("a")) == "New session in this project")
    #expect(newSessionTitle(row("a", branch: "carrier/short")) == "New session on carrier/short")
    let long = newSessionTitle(row("a", branch: "carrier/a-very-long-branch-name-that-does-not-fit-in-a-menu"))
    #expect(long.hasPrefix("New session on carrier/a-very") && long.contains("\u{2026}") && long.hasSuffix("in-a-menu"))
    // an archived session has no worktree to cut from
    #expect(sessionMenu(row("a", archived: true, branch: "x"), context: SessionMenuContext(startsSessions: true)).flatMap { $0 }.contains { $0.title.hasPrefix("New session") } == false)
}

@Test func aSessionThatWorksOrWaitsCannotBeDeletedAndSaysWhy() {
    #expect(deleteBlock(row("a")) == nil)
    #expect(deleteBlock(row("a", state: .working)) == "Stop the session to delete it")
    #expect(deleteBlock(row("a", state: .waiting)) == "Answer or stop the session to delete it")
    let delete = { (row: SessionRow) in sessionMenu(row).flatMap { $0 }.first { $0.title == "Delete…" } }
    #expect(delete(row("a"))?.disabledReason == nil && delete(row("a"))?.destructive == true)
    #expect(delete(row("a", state: .working))?.disabledReason == "Stop the session to delete it")
}

@Test func regenerateTitleIsOfferedOnlyToAHostThatListsIt() {
    #expect(titles(sessionMenu(row("a"), canRegenerateTitle: true))[1] == ["Rename…", "Regenerate title"])
    #expect(titles(sessionMenu(row("a"), canRegenerateTitle: false)).flatMap { $0 }.contains("Regenerate title") == false)
}

@Test func aWorkingSessionCanBeStoppedAndAPinnedOneUnpinned() {
    #expect(titles(sessionMenu(row("a", state: .working), pinned: true)).first == ["Stop", "Unpin"])
}

@Test func theCopySubmenuHasTheBranchOnlyForAWorktree() {
    let copy = { (row: SessionRow) in sessionMenu(row)[2][1].children.map(\.title) }
    #expect(copy(row("a")) == ["Path", "Session id"])
    #expect(copy(row("a", branch: "carrier/x")) == ["Path", "Branch name", "Session id"])
    #expect(sessionMenu(row("id-1"))[2][1].children.last?.action == .copy("id-1"))
}

@Test func anArchivedSessionHasRestoreAndDeleteAndNoPin() {
    let menu = sessionMenu(row("a", archived: true))
    #expect(titles(menu) == [["Rename…"], ["Open in Terminal", "Copy"], ["Restore", "Delete…"]])
    #expect(menu.last?.last?.destructive == true)
}

@Test func theHomeAddsFilterByWorkspace() {
    #expect(sessionMenu(row("a"), canFilter: true)[2].last?.action == .filterWorkspace("web"))
    #expect(titles(sessionMenu(row("a"))).flatMap { $0 }.contains { $0.hasPrefix("Filter") } == false)
}

@Test func pinnedSessionsLeadInAPinnedGroupAndPinsRoundTrip() {
    let rows = [row("a"), row("b", workspace: "api")]
    let groups = sessionGroups(rows, pinned: ["a"])
    #expect(groups.map(\.title) == ["Pinned", "api"])
    #expect(pinnedIds(storedPins(["x", "y"])) == ["x", "y"])
    #expect(pinnedIds("").isEmpty)
}

@Test func aWorkspaceFilterKeepsThatWorkspaceAndHasAChip() {
    let filter = SessionFilter(workspaces: ["web"])
    #expect(filter.matches(row("a")) && filter.matches(row("b", workspace: "api")) == false)
    #expect(filter.chips.map { $0.title(bundle: english.bundle, locale: english.locale) } == ["web"] && filter.count == 1)
}

@Test func aSessionThatWorksOrWaitsCannotBeArchivedAndSaysWhy() {
    #expect(archiveBlock(row("a")) == nil && archiveBlock(row("a", state: .done)) == nil)
    #expect(archiveBlock(row("a", state: .working)) == "Stop the session to archive it")
    #expect(archiveBlock(row("a", state: .waiting)) == "Answer or stop the session to archive it")
    let archive = { (row: SessionRow) in sessionMenu(row).flatMap { $0 }.first { $0.title == "Archive" } }
    #expect(archive(row("a"))?.disabledReason == nil)
    #expect(archive(row("a", state: .working))?.disabledReason == "Stop the session to archive it")
    // the others are as they were: Stop is still there to be used
    #expect(sessionMenu(row("a", state: .working)).flatMap { $0 }.first { $0.title == "Stop" }?.disabledReason == nil)
}

@Test func aSessionThatWaitsForBackgroundWorkCannotBeArchivedAndCanBeStopped() {
    var waiting = row("a")
    waiting.background = [BackgroundTask(id: "b", kind: "local_bash", description: "pnpm build")]
    #expect(archiveBlock(waiting) == "Stop the background task to archive it")
    waiting.background.append(BackgroundTask(id: "c", kind: "local_agent", description: "review"))
    #expect(archiveBlock(waiting) == "Stop the background tasks to archive it")
    let items = sessionMenu(waiting).flatMap { $0 }
    #expect(items.first { $0.title == "Stop" }?.action == .stop)
    #expect(items.first { $0.title == "Archive" }?.disabledReason == "Stop the background tasks to archive it")
}
