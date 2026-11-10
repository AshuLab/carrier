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

@Test func anIdleSessionMenuHasPinRenameRegenerateOpenCopyAndArchive() {
    #expect(titles(sessionMenu(row("a"))) == [["Pin"], ["Rename…", "Regenerate title"], ["Open in Terminal", "Copy"], ["Archive"]])
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
    #expect(titles(menu) == [["Rename…", "Regenerate title"], ["Open in Terminal", "Copy"], ["Restore", "Delete…"]])
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
    #expect(filter.chips.map(\.title) == ["web"] && filter.count == 1)
}
