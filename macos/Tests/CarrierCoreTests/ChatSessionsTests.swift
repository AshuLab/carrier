import Foundation
import Testing
@testable import CarrierCore

private func session(
    _ id: String, folder: String = "/Users/dev/carrier", base: String? = nil, state: String = "idle", live: Bool = true, archived: Bool = false,
    title: String? = "t", lastActiveAt: Int = 1_792_000_000_000
) throws -> ChatSession {
    let workspace = base.map { ",\"workspace\":{\"base\":\"\($0)\"}" } ?? ""
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
            {"id":"t","agent":"claude","harness":"claude","folder":"/w/fix","workspace":{"base":"/Users/dev/web","branch":"carrier/fix"},
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
    func list(archived wanted: Bool) async throws -> [ChatSession] {
        calls.append(wanted)
        guard let answer = wanted ? archived : active else { throw ControlError.closed }
        return answer
    }
    func events(_ id: String, after: Int, limit: Int) async throws -> ChatEvents { ChatEvents(events: [], cursor: after) }
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
            {"id":"t","agent":"claude","harness":"claude","folder":"/w/fix","workspace":{"base":"/Users/dev/web","branch":"carrier/fix"},
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
