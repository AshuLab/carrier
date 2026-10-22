import Foundation
import Testing
@testable import CarrierCore

private let fixtureURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/snapshot.json")

private let oldFixtureURL = fixtureURL.deletingLastPathComponent().appendingPathComponent("snapshot-old-engine.json")

private func fixtureData() throws -> Data { try Data(contentsOf: fixtureURL) }

/// The fixture as JSON with `change` applied, re-encoded.
private func edited(_ change: (inout [String: Any]) -> Void) throws -> Data {
    var json = try #require(JSONSerialization.jsonObject(with: fixtureData()) as? [String: Any])
    change(&json)
    return try JSONSerialization.data(withJSONObject: json)
}

private func firstEpic(_ json: inout [String: Any], _ change: (inout [String: Any]) -> Void) {
    var epics = json["epics"] as! [[String: Any]]
    change(&epics[0])
    json["epics"] = epics
}

@Test func decodesEveryFieldOfTheFixture() throws {
    let s = try decodeSnapshot(fixtureData())
    #expect(s.now == 100_000)
    #expect(s.startedAt == 40_000)
    #expect(s.repos == 2)
    #expect(s.nextCheckAt == 160_000)
    #expect(s.problem == "GitHub is not answering")
    #expect(s.paused)
    #expect(s.slots == .init(busy: 2, total: 3))
    #expect(s.queue == [
        .init(repo: "acme/web", issue: 20, title: "Issue 20 of acme/web", queuedAt: 20_000),
        .init(repo: "acme/api", issue: 21, title: "Issue 21 of acme/api", queuedAt: 21_000),
    ])
    #expect(s.done == [
        .init(repo: "acme/web", issue: 30, prNumber: 77, finishedAt: 95_000, executionId: "exec-ship-30"),
        .init(repo: "acme/api", issue: 31, prNumber: nil, finishedAt: 80_000, executionId: nil),
    ])

    #expect(s.epics.count == 9)
    #expect(s.epics[0] == PanelEpic(
        repo: "acme/web", issue: 12, status: .running, stage: .review, round: 2, maxReviews: 5, blockers: 2, stageSince: 40_000,
        lastActivityAt: 90_000, issueUrl: "https://github.com/acme/web/issues/12", prUrl: "https://github.com/acme/web/pull/50",
        lastError: "the agent process ended with an error", needsHumanReason: nil, slices: .init(done: 3, total: 5), executionId: "exec-review-12",
        title: "Issue 12 of acme/web", labels: ["solve:epic", "solve:epic:ready"], queuedAt: 500, startedAt: 1_000, finishedAt: nil,
        branch: "feat/issue-12/epic", workspace: "/work/acme/web-epic", needsHumanKind: nil, blockerTitles: ["a", "b"], agents: agents))
    #expect(s.epics[1] == PanelEpic(
        repo: "acme/web", issue: 13, status: .running, stage: .ship, round: nil, maxReviews: 5, blockers: 0, stageSince: 7_000,
        lastActivityAt: nil, issueUrl: "https://github.com/acme/web/issues/13", prUrl: nil,
        lastError: nil, needsHumanReason: nil, slices: nil, executionId: "exec-ship-13",
        title: "Issue 13 of acme/web", labels: ["solve:epic"], queuedAt: 600, startedAt: 7_000, finishedAt: nil,
        branch: "feat/issue-13/epic", workspace: "/work/acme/web-13", needsHumanKind: nil, blockerTitles: [], agents: agents))
    #expect(s.epics[2].status == .needsHuman)
    #expect(s.epics[2].stage == .fix)
    #expect(s.epics[2].needsHumanReason == "review limit")
    #expect(s.epics[2].prUrl == "https://github.com/acme/api/pull/9")
}

private let agents = PanelSnapshot.Agents(
    author: .init(harness: "claude", model: "claude-sonnet-5-5", provider: nil),
    reviewer: .init(harness: "codex", model: "gpt-5", provider: "ollama"))

@Test func decodesTheEngineWatchedSessionsAndEpicExtras() throws {
    let s = try decodeSnapshot(fixtureData())
    #expect(s.engine == .init(version: "0.1.0", pollIntervalMs: 300_000, maxConcurrentEpics: 3,
                              rateLimit: .init(remaining: 4_812, limit: 5_000, resetAt: 130_000, profile: "orchestrator")))
    #expect(s.watched == [
        .init(repo: "acme/web", lastCheckedAt: 98_000, ok: true, error: nil, agents: agents),
        .init(repo: "acme/api", lastCheckedAt: 98_000, ok: false, error: "GitHub answered 502", agents: .init(
            author: .init(harness: "agy", model: "gemini-3", provider: nil),
            reviewer: .init(harness: "claude", model: "claude-sonnet-5-5", provider: nil))),
    ])
    #expect(s.sessions == [
        .init(executionId: "exec-review-12", repo: "acme/web", issue: 12, stage: .review, round: 2, harness: "codex", model: "gpt-5",
              startedAt: 40_000, last: .init(kind: "tool", text: "Read src/auth/token.ts", at: 99_000)),
        .init(executionId: "exec-ship-13", repo: "acme/web", issue: 13, stage: .ship, round: nil, harness: "claude", model: "claude-sonnet-5-5",
              startedAt: 7_000, last: .init(kind: "say", text: "Writing the migration", at: 99_500)),
    ])
    #expect(s.epics.map(\.needsHumanKind) == [nil, nil, "review_limit", "agent_needs_human", "retries_exhausted", "timeout", "auth", "workspace", "pr_invalid"])
    #expect(s.epics[2].finishedAt == 60_000)
}

@Test func anOldEngineSnapshotDecodesWithEveryNewFieldEmpty() throws {
    let s = try decodeSnapshot(Data(contentsOf: oldFixtureURL))
    #expect(s.epics.count == 3)
    #expect(s.queue == [.init(repo: "acme/web", issue: 20), .init(repo: "acme/api", issue: 21)])
    #expect(s.engine == nil)
    #expect(s.watched == nil)
    #expect(s.sessions == nil)
    for e in s.epics {
        #expect(e.title == nil && e.labels == nil && e.queuedAt == nil && e.startedAt == nil && e.finishedAt == nil)
        #expect(e.branch == nil && e.workspace == nil && e.needsHumanKind == nil && e.blockerTitles == nil && e.agents == nil)
    }
}

@Test func aMissingRequiredFieldNamesTheField() throws {
    #expect(throws: SnapshotError.missingField("paused")) { try decodeSnapshot(edited { $0["paused"] = nil }) }
    #expect(throws: SnapshotError.missingField("epics.0.issueUrl")) { try decodeSnapshot(edited { firstEpic(&$0) { $0["issueUrl"] = nil } }) }
}

@Test func aWrongTypedFieldNamesTheField() throws {
    #expect(throws: SnapshotError.wrongType("repos")) { try decodeSnapshot(edited { $0["repos"] = "two" }) }
    #expect(throws: SnapshotError.wrongType("epics.0.status")) { try decodeSnapshot(edited { firstEpic(&$0) { $0["status"] = "paused" } }) }
    #expect(throws: SnapshotError.wrongType("epics.0.slices.total")) { try decodeSnapshot(edited { firstEpic(&$0) { $0["slices"] = ["done": 3, "total": "5"] } }) }
}

@Test func textThatIsNotJSONIsMalformed() {
    #expect(throws: SnapshotError.malformed) { try decodeSnapshot(Data("nope".utf8)) }
}
