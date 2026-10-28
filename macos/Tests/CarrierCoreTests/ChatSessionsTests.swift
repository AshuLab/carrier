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
