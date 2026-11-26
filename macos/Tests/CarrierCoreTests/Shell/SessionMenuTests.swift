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
    #expect(titles(sessionMenu(row("a"), bundle: english.bundle, locale: english.locale)) == [["Pin"], ["Rename…"], ["Open in Terminal", "Copy"], ["Archive", "Delete…"]])
}

@Test func theWindowsListsAddMarkAsUnreadNewSessionOnTheBranchAndProjectSettings() {
    let context = SessionMenuContext(marksUnread: true, startsSessions: true, projectKnown: true)
    #expect(titles(sessionMenu(row("a", branch: "fix/x"), context: context, bundle: english.bundle, locale: english.locale)) == [
        ["Pin", "Mark as unread"], ["Rename…"], ["New session on fix/x", "Project settings…", "Open in Terminal", "Copy"], ["Archive", "Delete…"]])
    let items = sessionMenu(row("a", branch: "fix/x"), context: context, bundle: english.bundle, locale: english.locale).flatMap { $0 }
    #expect(items.first { $0.title == "Mark as unread" }?.action == .markUnread)
    #expect(items.first { $0.title == "New session on fix/x" }?.action == .newSession(base: "/Users/dev/web", branch: "fix/x"))
    #expect(items.first { $0.title == "Project settings…" }?.action == .openProject(base: "/Users/dev/web"))
}

@Test func markAsUnreadBecomesMarkAsReadAndIsOffForTheOpenSessionAndAbsentForAnArchivedOne() {
    var unread = row("a")
    unread.unread = true
    let marks = { (row: SessionRow, viewing: Bool) in sessionMenu(row, context: SessionMenuContext(marksUnread: true, viewing: viewing), bundle: english.bundle, locale: english.locale).flatMap { $0 }.first { $0.title.hasPrefix("Mark as") } }
    #expect(marks(unread, false)?.title == "Mark as read" && marks(unread, false)?.action == .markRead)
    #expect(marks(row("a"), true)?.disabledReason != nil && marks(row("a"), false)?.disabledReason == nil)
    #expect(marks(row("a", archived: true), false) == nil)
}

@Test func newSessionSaysTheBranchShortenedOrTheProjectWhenTheSessionWorksInTheFolder() {
    #expect(newSessionTitle(row("a"), bundle: english.bundle, locale: english.locale) == "New session in this project")
    #expect(newSessionTitle(row("a", branch: "carrier/short"), bundle: english.bundle, locale: english.locale) == "New session on carrier/short")
    let long = newSessionTitle(row("a", branch: "carrier/a-very-long-branch-name-that-does-not-fit-in-a-menu"), bundle: english.bundle, locale: english.locale)
    #expect(long.hasPrefix("New session on carrier/a-very") && long.contains("\u{2026}") && long.hasSuffix("in-a-menu"))
    // an archived session has no worktree to cut from
    #expect(sessionMenu(row("a", archived: true, branch: "x"), context: SessionMenuContext(startsSessions: true), bundle: english.bundle, locale: english.locale).flatMap { $0 }.contains { $0.title.hasPrefix("New session") } == false)
}

@Test func aSessionThatWorksOrWaitsCannotBeDeletedAndSaysWhy() {
    #expect(deleteBlock(row("a"), bundle: english.bundle, locale: english.locale) == nil)
    #expect(deleteBlock(row("a", state: .working), bundle: english.bundle, locale: english.locale) == "Stop the session to delete it")
    #expect(deleteBlock(row("a", state: .waiting), bundle: english.bundle, locale: english.locale) == "Answer or stop the session to delete it")
    let delete = { (row: SessionRow) in sessionMenu(row, bundle: english.bundle, locale: english.locale).flatMap { $0 }.first { $0.title == "Delete…" } }
    #expect(delete(row("a"))?.disabledReason == nil && delete(row("a"))?.destructive == true)
    #expect(delete(row("a", state: .working))?.disabledReason == "Stop the session to delete it")
}

@Test func regenerateTitleIsOfferedOnlyToAHostThatListsIt() {
    #expect(titles(sessionMenu(row("a"), canRegenerateTitle: true, bundle: english.bundle, locale: english.locale))[1] == ["Rename…", "Regenerate title"])
    #expect(titles(sessionMenu(row("a"), canRegenerateTitle: false, bundle: english.bundle, locale: english.locale)).flatMap { $0 }.contains("Regenerate title") == false)
}

@Test func aWorkingSessionCanBeStoppedAndAPinnedOneUnpinned() {
    #expect(titles(sessionMenu(row("a", state: .working), pinned: true, bundle: english.bundle, locale: english.locale)).first == ["Stop", "Unpin"])
}

@Test func theCopySubmenuHasTheBranchOnlyForAWorktree() {
    let copy = { (row: SessionRow) in sessionMenu(row, bundle: english.bundle, locale: english.locale)[2][1].children.map(\.title) }
    #expect(copy(row("a")) == ["Path", "Session id"])
    #expect(copy(row("a", branch: "carrier/x")) == ["Path", "Branch name", "Session id"])
    #expect(sessionMenu(row("id-1"), bundle: english.bundle, locale: english.locale)[2][1].children.last?.action == .copy("id-1"))
}

@Test func anArchivedSessionHasRestoreAndDeleteAndNoPin() {
    let menu = sessionMenu(row("a", archived: true), bundle: english.bundle, locale: english.locale)
    #expect(titles(menu) == [["Rename…"], ["Open in Terminal", "Copy"], ["Restore", "Delete…"]])
    #expect(menu.last?.last?.destructive == true)
}

@Test func theHomeAddsFilterByWorkspace() {
    #expect(sessionMenu(row("a"), canFilter: true, bundle: english.bundle, locale: english.locale)[2].last?.action == .filterWorkspace("web"))
    #expect(titles(sessionMenu(row("a"), bundle: english.bundle, locale: english.locale)).flatMap { $0 }.contains { $0.hasPrefix("Filter") } == false)
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
    #expect(archiveBlock(row("a"), bundle: english.bundle, locale: english.locale) == nil && archiveBlock(row("a", state: .done), bundle: english.bundle, locale: english.locale) == nil)
    #expect(archiveBlock(row("a", state: .working), bundle: english.bundle, locale: english.locale) == "Stop the session to archive it")
    #expect(archiveBlock(row("a", state: .waiting), bundle: english.bundle, locale: english.locale) == "Answer or stop the session to archive it")
    let archive = { (row: SessionRow) in sessionMenu(row, bundle: english.bundle, locale: english.locale).flatMap { $0 }.first { $0.title == "Archive" } }
    #expect(archive(row("a"))?.disabledReason == nil)
    #expect(archive(row("a", state: .working))?.disabledReason == "Stop the session to archive it")
    // the others are as they were: Stop is still there to be used
    #expect(sessionMenu(row("a", state: .working), bundle: english.bundle, locale: english.locale).flatMap { $0 }.first { $0.title == "Stop" }?.disabledReason == nil)
}

private func process(_ id: String, _ description: String) -> BackgroundTask { BackgroundTask(id: id, kind: "local_bash", description: description, agentWork: false) }

@Test func aSessionThatWaitsForAgentWorkCannotBeArchivedOrDeletedAndCanBeStopped() {
    var waiting = row("a")
    waiting.background = [BackgroundTask(id: "b", kind: "local_agent", description: "review")]
    #expect(archiveBlock(waiting, bundle: english.bundle, locale: english.locale) == "Stop the background task to archive it")
    #expect(deleteBlock(waiting, bundle: english.bundle, locale: english.locale) == "Stop the background task to delete it")
    waiting.background.append(BackgroundTask(id: "c", kind: "local_workflow", description: "build"))
    #expect(archiveBlock(waiting, bundle: english.bundle, locale: english.locale) == "Stop the background tasks to archive it")
    // a process beside the agent work is not counted: the words are the ones of the agent work alone
    waiting.background = [BackgroundTask(id: "b", kind: "local_agent", description: "review"), process("p", "pnpm dev"), process("q", "tsc")]
    #expect(archiveBlock(waiting, bundle: english.bundle, locale: english.locale) == "Stop the background task to archive it")
    #expect(processesStopped(waiting).isEmpty)
    let items = sessionMenu(waiting, bundle: english.bundle, locale: english.locale).flatMap { $0 }
    #expect(items.first { $0.title == "Stop" }?.action == .stop)
    #expect(items.first { $0.title == "Archive" }?.disabledReason == "Stop the background task to archive it")
}

@Test func aSessionWithOnlyProcessesCanBeArchivedAndDeletedAndNamesWhatThatStops() {
    var running = row("a")
    #expect(processesStopped(running).isEmpty && archiveStopsQuestion(running, bundle: english.bundle, locale: english.locale) == nil)
    running.background = [process("p", "pnpm dev")]
    #expect(archiveBlock(running, bundle: english.bundle, locale: english.locale) == nil && deleteBlock(running, bundle: english.bundle, locale: english.locale) == nil)
    #expect(processesStopped(running).map(\.id) == ["p"])
    let question = archiveStopsQuestion(running, bundle: english.bundle, locale: english.locale)
    #expect(question == Question(title: "Archive \u{201C}t\u{201D}?", message: "This stops pnpm dev", confirm: "Archive"))
    #expect(deleteSessionQuestion(running, bundle: english.bundle, locale: english.locale).message == "This stops pnpm dev\nIts transcript is removed and cannot be brought back.")
    running.background = [process("p", "pnpm dev"), process("q", "tsc"), process("r", "vitest")]
    #expect(processesStopped(running).map(\.id) == ["p", "q", "r"])
    #expect(archiveStopsQuestion(running, bundle: english.bundle, locale: english.locale)?.message == "This stops pnpm dev, tsc, vitest")
    running.background.append(process("s", "build"))
    running.background.append(process("u", "watch"))
    #expect(archiveStopsQuestion(running, bundle: english.bundle, locale: english.locale)?.message == "This stops pnpm dev, tsc, vitest +2 more")
    // a session the host refuses anyway stops nothing
    running.state = .working
    #expect(processesStopped(running).isEmpty)
    running.state = .waiting
    #expect(processesStopped(running).isEmpty)
    #expect(sessionMenu(row("a"), bundle: english.bundle, locale: english.locale).flatMap { $0 }.first { $0.title == "Archive" }?.disabledReason == nil)
}
