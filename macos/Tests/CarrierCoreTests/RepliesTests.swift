import Foundation
import Testing
@testable import CarrierCore

// The golden files are written by the engine's test (src/control/replies.test.ts).
private func golden<T: Decodable>(_ name: String, as type: T.Type = T.self) throws -> T {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/reply-\(name).json")
    return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
}

private func decode<T: Decodable>(_ json: String, as type: T.Type = T.self) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
}

@Test func decodesTheSessionsReply() throws {
    let reply: SessionsReply = try golden("sessions")
    #expect(reply.sessions.map(\.stage) == ["fix", "review", "ship"])
    #expect(reply.sessions[0].status == "running")
    #expect(reply.sessions[0].resume == nil)
    #expect(reply.sessions[0].finishedAt == nil)
    #expect(reply.sessions[1].agent == .init(harness: "codex", model: "gpt-5", provider: "ollama"))
    #expect(reply.sessions[1].resume == ResumeDescriptor(harness: "codex", sessionId: "a1b2c3d4-0001-4000-8000-000000000002", cwd: "/work/acme/web-epic", configDir: nil))
    #expect(reply.sessions[2].round == nil)
    #expect(reply.sessions[2].resume?.configDir == "/Users/dev/.claude-work")
}

@Test func decodesTheEventsReply() throws {
    let reply: EventsReply = try golden("events")
    #expect(reply.next == 119)
    #expect(reply.running)
    #expect(reply.structured)
    #expect(reply.events.map(\.kind) == ["say", "tool_start", "tool_end", "tool_start", "tool_end", "tool_start", "tool_end", "note", "task", "say", "error",
                                           "tool_start", "tool_end", "task", "tool_start", "tool_end", "task", "tool_start", "tool_end"])
    // a paired tool call shares its call id
    #expect(reply.events[1].callId == reply.events[2].callId)
    #expect(reply.events[2].output == ["export function sign(", "}"])
    #expect(reply.events[4].diff?.map(\.sign) == [" ", "-", "+"])
    #expect(reply.events[6].status == "err")
    #expect(reply.events[8].agentId == "agent-7")
}

@Test func decodesTheEpicReply() throws {
    let reply: EpicReply = try golden("epic")
    #expect(reply.stages.map(\.stage) == ["queued", "ship", "review", "fix"])
    #expect(reply.stages[3].endedAt == nil)
    #expect(reply.rounds.map(\.verdict) == ["changes_requested", "changes_requested", "approved", "limit_reached"])
    #expect(reply.rounds[0].fixedSha == "2222222bbbbbbb")
    #expect(reply.rounds[0].commits.count == 2)
    #expect(reply.rounds[1].blockers.map(\.mark) == ["fixed", "carried", "new"])
    #expect(reply.rounds[1].blockers[1].id == nil)
    #expect(reply.rounds[1].blockers[1].approximate)
    #expect(reply.rounds[2].blockers.isEmpty)
    #expect(reply.slices.map(\.state) == ["closed", "skipped", "in_progress", "waiting", "ready"])
    #expect(reply.slices[3].blockedBy == [121, 123])
    #expect(reply.slicesTruncated == false)
    #expect(reply.slices[0] == EpicReply.Slice(number: 121, title: "Request schemas", state: "closed", blockedBy: [], prNumber: 130, closedAt: 50_000, readAt: 99_000))
    #expect(reply.worktrees == [.init(kind: "epic", lane: nil, path: "/work/acme/web-epic"), .init(kind: "lane", lane: 1, path: "/work/acme/web-epic--lane-1")])
    #expect(reply.branch == "feat/issue-12/epic")
    #expect(reply.pr?.checks == .init(passing: 3, failing: 1, pending: 0))
    #expect(reply.pr?.reviewDecision == nil)
}

@Test func decodesTheFilesReply() throws {
    let reply: FilesReply = try golden("files")
    #expect(reply.sections.map(\.kind) == ["lane", "lane", "merged", "session"])
    #expect(reply.sections[0].files[0] == FilesReply.File(path: "src/auth/token.ts", added: 30, removed: 6, alsoIn: ["lane-2"]))
    // a file in two sections names the other one from both
    #expect(reply.sections[1].files[0].alsoIn == ["lane-1"])
    #expect(reply.sections[3].files.isEmpty)
    #expect(reply.total == FilesReply.Total(files: 3, added: 165, removed: 19))
    #expect(reply.truncated == false)
}

@Test func decodesRepliesWithoutTheirOptionalFields() throws {
    let sessions: SessionsReply = try decode(#"{"sessions":[{"executionId":"e","stage":"ship","role":"author","agent":{"harness":"claude","model":"m"},"status":"running","startedAt":1}]}"#)
    #expect(sessions.sessions[0].round == nil)
    #expect(sessions.sessions[0].agent.provider == nil)
    #expect(sessions.sessions[0].finishedAt == nil)
    #expect(sessions.sessions[0].resume == nil)

    let events: EventsReply = try decode(#"{"events":[{"id":1,"at":2,"kind":"future_kind"}],"next":1,"running":false,"structured":false}"#)
    #expect(events.events[0] == ExecEvent(id: 1, at: 2, kind: "future_kind"))
    #expect(events.structured == false)

    let epic: EpicReply = try decode(#"""
    {"stages":[],"slices":[],"worktrees":[],
     "rounds":[{"round":1,"reviewer":{"harness":"codex","model":"m"},"verdict":"approved","blockers":[{"title":"t","mark":"new","approximate":true}],"commits":[]}]}
    """#)
    #expect(epic.branch == nil)
    #expect(epic.pr == nil)
    #expect(epic.rounds[0].reviewMs == nil)
    #expect(epic.rounds[0].reviewedSha == nil)
    #expect(epic.rounds[0].blockers[0].id == nil)
    #expect(epic.rounds[0].blockers[0].url == nil)

    let pr: EpicReply = try decode(#"{"stages":[],"rounds":[],"slices":[],"worktrees":[],"pr":{"number":1,"url":"u","draft":true,"mergeState":"UNKNOWN"}}"#)
    #expect(pr.pr?.checks == nil)
    #expect(pr.pr?.reviewDecision == nil)
}
