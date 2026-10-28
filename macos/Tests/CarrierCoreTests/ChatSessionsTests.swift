import Foundation
import Testing
@testable import CarrierCore

private func session(
    _ id: String, folder: String = "/Users/dev/carrier", base: String? = nil, state: String = "idle", live: Bool = true, archived: Bool = false,
    title: String? = "t", lastActiveAt: Int = 1_792_000_000_000
) throws -> ChatSession {
    let workspace = base.map { ",\"workspace\":{\"kind\":\"worktree\",\"base\":\"\($0)\",\"branch\":\"carrier/fix\"}" } ?? ""
    let name = title.map { "\"\($0)\"" } ?? "null"
    let json = """
        {"id":"\(id)","agent":"codex","harness":"codex","folder":"\(folder)"\(workspace),"title":\(name),"state":"\(state)",
         "createdAt":1,"lastActiveAt":\(lastActiveAt),"archived":\(archived),"live":\(live)}
        """
    return try JSONDecoder().decode(ChatSession.self, from: Data(json.utf8))
}

@Test func aSessionMapsToARowWithItsStateAgentTitleTimeAndArchive() throws {
    let rows = sessionRows([
        try session("w", state: "working"), try session("a", state: "waiting_approval", archived: true), try session("i"),
        try session("n", title: nil, lastActiveAt: 1_792_000_123_456),
    ])
    #expect(rows.map(\.state) == [.working, .waiting, .idle, .idle])
    #expect(rows.map(\.agent) == ["codex", "codex", "codex", "codex"])
    #expect(rows.map(\.archived) == [false, true, false, false])
    #expect(rows[3].title == "Untitled session")
    #expect(rows[3].updatedAt == Date(timeIntervalSince1970: 1_792_000_123.456))
}

@Test func aWorktreeSessionRowCarriesItsBranchAndAFolderSessionHasNone() throws {
    let tree = try JSONDecoder().decode(
        ChatSession.self,
        from: Data(
            """
            {"id":"t","agent":"claude","harness":"claude","folder":"/w/fix","workspace":{"kind":"worktree","base":"/Users/dev/web","branch":"carrier/fix","from":"main","path":"/w/fix"},
             "title":"t","state":"idle","createdAt":1,"lastActiveAt":2,"archived":false,"live":false}
            """.utf8))
    #expect(sessionRows([tree, try session("plain")]).map(\.branch) == ["carrier/fix", nil])
}

@Test func aSessionThatIsNotLiveIsIdle() throws {
    let rows = sessionRows([try session("w", state: "working", live: false), try session("a", state: "waiting_approval", live: false)])
    #expect(rows.map(\.state) == [.idle, .idle])
}

@Test func aWorktreeSessionIsGroupedUnderItsBaseFolderAndAFolderSessionUnderItsFolder() throws {
    let rows = sessionRows([
        try session("tree", folder: "/Users/dev/.carrier/worktrees/web/fix", base: "/Users/dev/web"), try session("plain", folder: "/Users/dev/web"),
    ])
    #expect(rows.map(\.workspace) == ["web", "web"])
    #expect(sessionGroups(rows).map(\.title) == ["web"])
}

@Test func twoGroupsWithTheSameNameShowTheirParentFolderAndOthersDoNot() throws {
    let rows = sessionRows([
        try session("1", folder: "/Users/dev/web"), try session("2", folder: "/Users/dev/work/web"), try session("3", folder: "/Users/dev/carrier"),
        try session("4", folder: "/Users/dev/web"),
    ])
    #expect(rows.map(\.workspace) == ["dev/web", "work/web", "carrier", "dev/web"])
    #expect(sessionGroups(rows).map(\.title) == ["carrier", "dev/web", "work/web"])
}

private let fixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures").path

@Test func theGoldenListGivesTheFixturesGroupsAndTheArchivedCount() async throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.chatSocketPath })
    let rows = sessionRows(try await host.list(archived: false) + (try await host.list(archived: true)))
    #expect(sessionGroups(rows).map(\.title) == ["carrier", "dev/web", "work/web"])
    #expect(archivedCount(rows) == 2)
}

private final class FakeHost: ChatHost, @unchecked Sendable {
    var active: [ChatSession]? = []
    var archived: [ChatSession]? = []
    var calls: [Bool] = []

    func agents() async throws -> [ChatAgent] { [] }
    func open(agent: String, folder: String, worktree: WorktreeRequest?) async throws -> String { "" }
    func workspace(_ folder: String) async throws -> WorkspaceInfo { WorkspaceInfo(folder: folder, git: false) }
    func fetch(_ folder: String) async throws -> WorkspaceInfo { WorkspaceInfo(folder: folder, git: false) }
    func suggestName(_ folder: String) async throws -> String { "" }
    func checkName(_ folder: String, _ name: String) async throws -> NameCheck { NameCheck(valid: true, free: true) }
    func list(archived wanted: Bool) async throws -> [ChatSession] {
        calls.append(wanted)
        guard let answer = wanted ? archived : active else { throw ControlError.closed }
        return answer
    }
    func events(_ id: String, after: Int, limit: Int) async throws -> ChatEvents { ChatEvents(events: [], cursor: after) }
    func resume(_ id: String) async throws {}
    func send(_ id: String, _ text: String) async throws {}
    func interrupt(_ id: String) async throws {}
    func answer(_ id: String, approval: String, choice: String) async throws {}
    func setOption(_ id: String, option: String, value: String) async throws {}
    var changes: [String] = []
    var refuse: [String: Error] = [:]
    func archive(_ id: String, _ archived: Bool) async throws {
        changes.append("\(archived ? "archive" : "restore") \(id)")
        if let error = refuse[id] { throw error }
    }
    func delete(_ id: String) async throws {
        changes.append("delete \(id)")
        if let error = refuse[id] { throw error }
    }
}

private final class Clock { var now = Date(timeIntervalSince1970: 1_800_000_000) }

private func rig(_ host: FakeHost) -> (ChatSessionsPoller, Clock, () -> [SessionRow]) {
    let clock = Clock()
    var rows: [SessionRow] = []
    let poller = ChatSessionsPoller(host: host, archivedEvery: 5, now: { clock.now }) { rows = $0 }
    return (poller, clock, { rows })
}

@Test func theActiveListIsReadEveryPollAndTheArchivedOneEveryFiveSeconds() async throws {
    let host = FakeHost()
    let (poller, clock, _) = rig(host)
    for _ in 0..<7 {
        await poller.poll()
        clock.now.addTimeInterval(1)
    }
    // polls at 0...6 s: the archived list at 0 and at 5
    #expect(host.calls == [false, true, false, false, false, false, false, true, false])
}

@Test func theRowsHoldTheActiveAndTheArchivedSessionsAndTheArchivedCountIsFromTheArchivedList() async throws {
    let host = FakeHost()
    host.active = [try session("a"), try session("b")]
    host.archived = [try session("x", archived: true)]
    let (poller, clock, rows) = rig(host)
    await poller.poll()
    #expect(rows().map(\.id) == ["a", "b", "x"] && archivedCount(rows()) == 1)
    // an archive made between two reads of the archived list shows up with the next read of it, not before
    host.archived = [try session("x", archived: true), try session("y", archived: true)]
    clock.now.addTimeInterval(1)
    await poller.poll()
    #expect(archivedCount(rows()) == 1)
    clock.now.addTimeInterval(4)
    await poller.poll()
    #expect(archivedCount(rows()) == 2)
}

@Test func aHostThatDoesNotAnswerGivesNoRowsAndTheArchivedListIsReadAgainWhenItComesBack() async throws {
    let host = FakeHost()
    host.active = [try session("a")]
    host.archived = [try session("x", archived: true)]
    let (poller, clock, rows) = rig(host)
    await poller.poll()
    #expect(rows().count == 2)
    host.active = nil
    clock.now.addTimeInterval(1)
    await poller.poll()
    #expect(rows().isEmpty)
    host.active = [try session("a")]
    clock.now.addTimeInterval(1)
    await poller.poll()
    #expect(rows().map(\.id) == ["a", "x"])
}

@Test func anArchivedListThatFailsKeepsTheLastOneAndTriesAgainNextPoll() async throws {
    let host = FakeHost()
    host.active = [try session("a")]
    host.archived = [try session("x", archived: true)]
    let (poller, clock, rows) = rig(host)
    await poller.poll()
    host.archived = nil
    clock.now.addTimeInterval(5)
    await poller.poll()
    #expect(rows().map(\.id) == ["a", "x"])
    host.archived = []
    clock.now.addTimeInterval(1)
    await poller.poll()
    #expect(rows().map(\.id) == ["a"])
}

// The Sessions home: search across active and archived, filters, sorts, counts and the empty states, over rows.

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func row(
    _ id: String, _ title: String = "t", workspace: String = "web", agent: String = "claude", state: SessionState = .idle, ago: TimeInterval = 60,
    archived: Bool = false
) -> SessionRow {
    SessionRow(id: id, title: title, workspace: workspace, agent: agent, state: state, updatedAt: now.addingTimeInterval(-ago), archived: archived)
}

private let sample = [
    row("a", "Rate-limit the webhook", workspace: "api", state: .working, ago: 30),
    row("b", "Billing schema", workspace: "api", agent: "codex", state: .waiting, ago: 240),
    row("c", "Pricing copy", workspace: "web", ago: 7200),
    row("d", "Old spike", workspace: "web", agent: "codex", ago: 86400 * 3),
    row("x", "Rate limit v1", workspace: "api", ago: 86400 * 12, archived: true),
]

@Test func theSubtitleCountsActiveSessionsAndTheOnesThatWaitForThePerson() {
    #expect(sessionsPage(sample, now: now).subtitle == "4 active · 1 waits for you")
    #expect(sessionsPage([sample[0], sample[1], row("w", state: .waiting)], now: now).subtitle == "3 active · 2 wait for you")
    #expect(sessionsPage([sample[0], sample[2]], now: now).subtitle == "2 active")
    #expect(sessionsPage([sample[4]], now: now).subtitle == "")
}

@Test func aFilterKeepsWhatMatchesAndTheSubtitleSaysHowManyOfTheActiveOnes() {
    let page = sessionsPage(sample, filter: SessionFilter(statuses: [.waiting]), now: now)
    #expect(page.groups.flatMap(\.rows).map(\.id) == ["b"])
    #expect(page.subtitle == "1 of 4 · 1 waits for you")
    let codex = sessionsPage(sample, filter: SessionFilter(agents: ["codex"]), now: now)
    #expect(codex.groups.flatMap(\.rows).map(\.id) == ["b", "d"])
    // statuses and agents together both have to hold; within a kind any of the ticked ones does
    let both = SessionFilter(statuses: [.idle, .waiting], agents: ["codex"])
    #expect(sessionsPage(sample, filter: both, now: now).groups.flatMap(\.rows).map(\.id) == ["b", "d"])
}

@Test func theFilterCountsItsTickedValuesAndHasAChipForEachThatRemovesIt() {
    var filter = SessionFilter(statuses: [.working, .waiting], agents: ["codex"])
    #expect(filter.count == 3 && SessionFilter().count == 0)
    #expect(filter.chips == [.status(.waiting), .status(.working), .agent("codex")])
    #expect(filter.chips.map(\.title) == ["Waiting for you", "Working", "codex"])
    filter.remove(.status(.working))
    #expect(filter.chips == [.status(.waiting), .agent("codex")])
    filter.remove(.agent("codex"))
    filter.remove(.status(.waiting))
    #expect(filter == SessionFilter())
}

@Test func searchFindsActiveThenArchivedByTitleWorkspaceOrAgentAndSaysHowManyResults() {
    let page = sessionsPage(sample, query: "rate", now: now)
    #expect(page.groups.flatMap(\.rows).map(\.id) == ["a", "x"])
    #expect(page.subtitle == "2 results")
    #expect(sessionsPage(sample, query: "API", now: now).groups.flatMap(\.rows).map(\.id) == ["a", "b", "x"])
    #expect(sessionsPage(sample, query: "codex", now: now).groups.flatMap(\.rows).map(\.id) == ["b", "d"])
    #expect(sessionsPage(sample, query: "billing", now: now).subtitle == "1 result")
}

@Test func aFilterNarrowsASearchToo() {
    let page = sessionsPage(sample, query: "rate", filter: SessionFilter(statuses: [.working]), now: now)
    #expect(page.groups.flatMap(\.rows).map(\.id) == ["a"])
}

@Test func theSortsGroupByWorkspaceByAgeAndByStatus() {
    #expect(sessionsPage(sample, by: .workspace, now: now).groups.map(\.title) == ["api", "web"])
    #expect(sessionsPage(sample, by: .age, now: now).groups.map(\.title) == ["Today", "Last 7 days"])
    #expect(sessionsPage(sample, by: .status, now: now).groups.map(\.title) == ["Waiting for you", "Working", "Idle"])
}

@Test func withNoActiveSessionsThePageIsNoSessionsYetEvenWhenSomethingIsArchived() {
    #expect(sessionsPage([], now: now).emptyState == .noSessions)
    #expect(sessionsPage([sample[4]], now: now).emptyState == .noSessions)
    #expect(sessionsPage(sample, now: now).emptyState == nil)
}

@Test func aSearchOrAFilterThatMatchesNothingIsNoSessionsMatch() {
    #expect(sessionsPage(sample, query: "zzz", now: now).emptyState == .noSessionsMatch)
    #expect(sessionsPage(sample, filter: SessionFilter(statuses: [.working], agents: ["codex"]), now: now).emptyState == .noSessionsMatch)
    #expect(sessionsPage([], query: "x", now: now).emptyState == .noSessionsMatch)
}

private func worktreeSession() throws -> ChatSession {
    try JSONDecoder().decode(
        ChatSession.self,
        from: Data(
            """
            {"id":"t","agent":"claude","harness":"claude","folder":"/w/fix","workspace":{"kind":"worktree","base":"/Users/dev/web","branch":"carrier/fix","from":"main","path":"/w/fix"},
             "title":"Fix login","state":"idle","createdAt":1,"lastActiveAt":2,"archived":false,"live":false}
            """.utf8))
}

@Test func theTitleBarSaysTheTitleAndWhereAFolderSessionWorks() throws {
    let row = sessionRows([try session("plain", folder: "/Users/dev/web", title: "Explore")])[0]
    #expect(conversationTitle(row) == "Explore")
    #expect(conversationSubtitle(row) == "web · base folder")
    #expect(openMenuItems(row) == [
        OpenItem(title: "Reveal in Finder", action: .reveal(path: "/Users/dev/web")), OpenItem(title: "Copy path", action: .copy("/Users/dev/web")),
    ])
}

@Test func theTitleBarSaysTheBranchOfAWorktreeSessionAndItsMenuCopiesIt() throws {
    let row = sessionRows([try worktreeSession()])[0]
    #expect(conversationSubtitle(row) == "web · ⑂ carrier/fix")
    #expect(openMenuItems(row) == [
        OpenItem(title: "Reveal in Finder", action: .reveal(path: "/w/fix")), OpenItem(title: "Copy path", action: .copy("/w/fix")),
        OpenItem(title: "Copy branch name", action: .copy("carrier/fix")),
    ])
}

@Test func aSessionWithoutATitleIsANewSessionInTheTitleBar() throws {
    #expect(conversationTitle(sessionRows([try session("n", title: nil)])[0]) == "New session")
}

// The Archive page: the archived rows, searched and sorted, counted, with its empty states.

private let activeSample = sample.filter { $0.archived == false }

private let archived = [
    row("x", "Rate limit v1", workspace: "api", ago: 86400 * 12, archived: true),
    row("y", "Old spike", workspace: "web", agent: "codex", ago: 86400 * 45, archived: true),
    row("z", "Billing notes", workspace: "api", agent: "codex", ago: 86400 * 2, archived: true),
    row("w", "Pricing copy", workspace: "Web2", ago: 86400 * 40, archived: true),
]

@Test func theArchiveListsOnlyArchivedSessionsByDateArchivedNewestFirst() {
    let page = archivePage(activeSample + archived, now: now)
    #expect(page.groups.map(\.title) == ["Last 30 days", "Older"])
    #expect(page.groups.map { $0.rows.map(\.id) } == [["z", "x"], ["w", "y"]])
    #expect(page.subtitle == "4 sessions" && page.emptyState == nil && page.canClear)
}

@Test func theArchiveSortsByProjectIgnoringCaseAndANonEmptyGroupOnly() {
    let page = archivePage(archived, by: .project, now: now)
    #expect(page.groups.map(\.title) == ["api", "web", "Web2"])
    #expect(page.groups.map { $0.rows.map(\.id) } == [["z", "x"], ["y"], ["w"]])
    #expect(archivePage([archived[0]], now: now).groups.map(\.title) == ["Last 30 days"])
}

@Test func archiveSearchFindsByTitleWorkspaceOrAgentAndNeverListsActiveSessions() {
    #expect(archivePage(activeSample + archived, query: "rate", now: now).groups.flatMap(\.rows).map(\.id) == ["x"])
    #expect(archivePage(activeSample + archived, query: "API", now: now).groups.flatMap(\.rows).map(\.id) == ["z", "x"])
    let codex = archivePage(activeSample + archived, query: "codex", now: now)
    #expect(codex.groups.flatMap(\.rows).map(\.id) == ["z", "y"] && codex.subtitle == "2 results")
    #expect(archivePage(archived, query: "billing", now: now).subtitle == "1 result")
}

@Test func anArchiveWithNothingIsNothingArchivedAndASearchWithNoResultIsNoSessionsMatch() {
    let empty = archivePage(sample.filter { $0.archived == false }, now: now)
    #expect(empty.emptyState == .nothingArchived && empty.subtitle == "" && empty.canClear == false)
    #expect(EmptyState.nothingArchived.title == "Nothing archived" && EmptyState.nothingArchived.line == "Archived sessions are kept here.")
    #expect(archivePage(archived, query: "zzz", now: now).emptyState == .noSessionsMatch)
    #expect(archivePage(archived, query: "zzz", now: now).canClear)
    #expect(archivePage([], query: "zzz", now: now).emptyState == .nothingArchived)
}

@Test func theCountIsOfTheArchivedSessionsAndFollowsAnArchiveOrARestore() {
    var rows = sample
    #expect(archivedCount(rows) == 1)
    rows[0].archived = true
    #expect(archivedCount(rows) == 2 && archivePage(rows, now: now).subtitle == "2 sessions")
    rows[0].archived = false
    rows[4].archived = false
    #expect(archivedCount(rows) == 0)
}

@Test func theArchiveSortIsRememberedAndDefaultsToDateArchived() {
    let defaults = UserDefaults(suiteName: "archive-sort-\(UUID().uuidString)")!
    let store = SidebarStore(defaults: defaults)
    #expect(store.archiveSort == .dateArchived)
    store.archiveSort = .project
    #expect(SidebarStore(defaults: defaults).archiveSort == .project)
}

@Test func clearSessionsNamesTheCountAndDeleteNamesTheSession() {
    #expect(clearSessionsQuestion(count: 5).title == "Delete all 5 archived sessions?")
    #expect(clearSessionsQuestion(count: 5).confirm == "Delete all")
    #expect(clearSessionsQuestion(count: 1).title == "Delete the archived session?")
    #expect(deleteSessionQuestion(row("x", "Old spike")).title == "Delete \u{201C}Old spike\u{201D}?")
}

@Test func aSessionRowMenuHasArchiveRevealAndCopyIdAndRestoreForAnArchivedOne() {
    let live = SessionRow(id: "id-1", title: "t", workspace: "web", agent: "claude", state: .idle, updatedAt: now, folder: "/Users/dev/web")
    #expect(sessionMenu(live) == [
        SessionMenuItem(title: "Archive", action: .archive), SessionMenuItem(title: "Reveal in Finder", action: .reveal(path: "/Users/dev/web")),
        SessionMenuItem(title: "Copy session id", action: .copy("id-1")),
    ])
    var gone = live
    gone.archived = true
    #expect(sessionMenu(gone).map(\.title) == ["Restore", "Reveal in Finder", "Copy session id"])
}

// Archive, restore, delete and clear through a fake host.

@MainActor @Test func archivingRestoringAndDeletingAskTheHostAndSayThatTheListsChanged() async {
    let host = FakeHost()
    let actions = SessionActions(host: host, log: { _ in })
    var changed = 0
    actions.changed = { changed += 1 }
    #expect(await actions.archive("a") == nil)
    #expect(await actions.restore("a") == nil)
    #expect(await actions.delete("b") == nil)
    #expect(host.changes == ["archive a", "restore a", "delete b"] && changed == 3)
}

@MainActor @Test func aRefusalIsReturnedInWordsAndNothingChanges() async {
    let host = FakeHost()
    host.refuse["a"] = ControlError.remote("This session is working; interrupt or close it first, then archive it")
    let actions = SessionActions(host: host, log: { _ in })
    var changed = 0
    actions.changed = { changed += 1 }
    #expect(await actions.archive("a") == "This session is working; interrupt or close it first, then archive it")
    #expect(changed == 0)
}

@MainActor @Test func aHostThatDoesNotAnswerIsLoggedAndSaidAndARefusalIsNotLogged() async {
    let host = FakeHost()
    host.refuse["a"] = ControlError.closed
    host.refuse["b"] = ControlError.remote("unknown session")
    var logged: [String] = []
    let actions = SessionActions(host: host, log: { logged.append($0) })
    #expect(await actions.delete("a") == "The chat host is not answering")
    #expect(await actions.delete("b") == "unknown session")
    #expect(logged.count == 1 && logged[0].contains("could not delete"))
}

@MainActor @Test func clearDeletesEverySessionAndAnswersNothingWhenAllWentThrough() async {
    let host = FakeHost()
    let actions = SessionActions(host: host, log: { _ in })
    #expect(await actions.clear(["a", "b", "c"]) == nil)
    #expect(host.changes == ["delete a", "delete b", "delete c"])
}

@MainActor @Test func clearKeepsGoingPastARefusalAndSaysHowManyWentAndWhy() async {
    let host = FakeHost()
    host.refuse["b"] = ControlError.remote("This session was resumed meanwhile; close it first")
    let actions = SessionActions(host: host, log: { _ in })
    let said = await actions.clear(["a", "b", "c"])
    #expect(host.changes == ["delete a", "delete b", "delete c"])
    #expect(said == "Deleted 2 of 3 archived sessions. This session was resumed meanwhile; close it first")
}

@MainActor @Test func clearStopsWhenTheHostStopsAnswering() async {
    let host = FakeHost()
    host.refuse["a"] = ControlError.closed
    let actions = SessionActions(host: host, log: { _ in })
    #expect(await actions.clear(["a", "b"]) == "Deleted 0 of 2 archived sessions. The chat host is not answering")
    #expect(host.changes == ["delete a"])
}

@Test func anInvalidatedArchivedListIsReadAtTheNextPollWhateverItsAge() async throws {
    let host = FakeHost()
    host.active = [try session("a")]
    host.archived = [try session("x", archived: true)]
    let (poller, _, rows) = rig(host)
    await poller.poll()
    host.archived = []
    await poller.poll()
    #expect(archivedCount(rows()) == 1)
    poller.invalidateArchived()
    await poller.poll()
    #expect(archivedCount(rows()) == 0)
    #expect(host.calls == [false, true, false, false, true])
}

// The real client against the fixture host.

@Test func theClientArchivesRestoresAndDeletesOnTheFixtureHostAndItRefusesAWorkingSession() async throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.chatSocketPath })
    let idle = "c3d4e5f6-2a1b-4c8d-9e0f-1a2b3c4d5e03"
    let working = "5d1f7c3a-0b6e-4a52-9a1d-3c7e8b2f4a01"
    try await host.archive(idle, true)
    #expect(try await host.list(archived: true).count == 3)
    #expect(try await host.list(archived: false).count == 3)
    try await host.archive(idle, false)
    #expect(try await host.list(archived: true).count == 2)
    await #expect(throws: ControlError.remote("This session is working; interrupt or close it first, then archive it")) { try await host.archive(working, true) }
    let old = "d4e5f6a7-3b2c-4d9e-8f1a-2b3c4d5e6f04"
    try await host.delete(old)
    #expect(try await host.list(archived: true).map(\.id) == ["e5f6a7b8-4c3d-4e0f-9a2b-3c4d5e6f7a05"])
    await #expect(throws: ControlError.remote("unknown session")) { try await host.delete(old) }
    await #expect(throws: ControlError.remote("not a valid session id")) { try await host.delete("../x") }
}

@MainActor @Test func aConversationOfAnArchivedSessionIsReadOnlyAndGetsItsBoxBackWhenRestored() async throws {
    let host = FakeHost()
    host.archived = [try session("a", live: false, archived: true)]
    let model = ConversationModel(host: host, sessionId: "a", log: { _ in })
    #expect(model.archived == false)
    await model.poll()
    #expect(model.archived && model.live == false && model.agent == "codex" && model.loaded)
    host.archived = []
    host.active = [try session("a")]
    await model.poll()
    #expect(model.archived == false)
}
