import Foundation
import Testing
@testable import CarrierCore

private let all = ["sessions", "events", "epic", "files"]
private let execution = "a1b2c3d4-0001-4000-8000-000000000001"

private func connect(_ engine: FixtureEngine) throws -> ControlClient {
    let client = try #require(ControlClient.connect(path: engine.path))
    _ = try client.hello()
    return client
}

@Test func theFourRequestsDecodeTheGoldenRepliesAndSendTheirFields() throws {
    let engine = FixtureEngine(capabilities: all)
    defer { engine.stop() }
    let client = try connect(engine)

    #expect(try client.sessions(repo: "acme/web", issue: 12)?.sessions.count == 3)
    #expect(try client.events(executionId: execution, after: 5, limit: 50)?.next == 119)
    #expect(try client.epic(repo: "acme/web", issue: 12)?.branch == "feat/issue-12/epic")
    #expect(try client.files(repo: "acme/web", issue: 12, executionId: execution)?.sections.count == 4)
    #expect(try client.files(repo: "acme/web", issue: 12) != nil)

    let sent = engine.requests
    #expect(sent.map { $0["cmd"] as? String } == ["sessions", "events", "epic", "files", "files"])
    #expect(sent[0]["repo"] as? String == "acme/web" && sent[0]["issue"] as? Int == 12)
    #expect(sent[1]["executionId"] as? String == execution && sent[1]["after"] as? Int == 5 && sent[1]["limit"] as? Int == 50)
    #expect(sent[3]["executionId"] as? String == execution)
    #expect(sent[4]["executionId"] == nil)
}

@Test func anErrorReplyThrowsAndMarksOnlyThatCapabilityUnavailable() throws {
    let engine = FixtureEngine(capabilities: all, fail: ["epic"])
    defer { engine.stop() }
    let client = try connect(engine)

    #expect(throws: ControlError.remote("internal error")) { try client.epic(repo: "acme/web", issue: 12) }
    #expect(client.capabilities == [.sessions, .events, .files])
    // not asked again, and the others still answer
    #expect(try client.epic(repo: "acme/web", issue: 12) == nil)
    #expect(engine.commands == ["epic"])
    #expect(try client.sessions(repo: "acme/web", issue: 12) != nil)

    // the next hello, on a new connection, brings it back
    #expect(try connect(engine).capabilities.contains(.epic))
}

@Test func aReplyThatDoesNotDecodeMarksTheCapabilityUnavailable() throws {
    let engine = FixtureEngine(capabilities: all, garbage: ["files"])
    defer { engine.stop() }
    let client = try connect(engine)

    #expect(throws: ControlError.badLine) { try client.files(repo: "acme/web", issue: 12) }
    #expect(try client.files(repo: "acme/web", issue: 12) == nil)
    #expect(engine.commands == ["files"])
}

@Test func nothingIsSentForACapabilityTheHelloLeftOut() throws {
    let engine = FixtureEngine(capabilities: ["epic"])
    defer { engine.stop() }
    let client = try connect(engine)

    #expect(try client.sessions(repo: "acme/web", issue: 12) == nil)
    #expect(try client.events(executionId: execution) == nil)
    #expect(try client.files(repo: "acme/web", issue: 12) == nil)
    _ = try client.epic(repo: "acme/web", issue: 12)
    #expect(engine.commands == ["epic"])
}

@Test(arguments: ["", "acme", "acme/web/x", "../web", "acme/..", "a\"b/web", "acme/we b", "acme/web\n", "é/web"])
func aRepoThatIsNotOwnerSlashNameIsRefusedBeforeItIsSent(repo: String) throws {
    let engine = FixtureEngine(capabilities: all)
    defer { engine.stop() }
    let client = try connect(engine)

    #expect(throws: ControlError.remote("not a valid epic")) { try client.epic(repo: repo, issue: 1) }
    #expect(throws: ControlError.remote("not a valid epic")) { try client.sessions(repo: repo, issue: 1) }
    #expect(throws: ControlError.remote("not a valid epic")) { try client.files(repo: repo, issue: 1) }
    #expect(engine.commands.isEmpty)
    #expect(client.capabilities.count == 4)
}

@Test func anIssueExecutionIdOrRangeThatIsNotValidIsRefusedBeforeItIsSent() throws {
    let engine = FixtureEngine(capabilities: all)
    defer { engine.stop() }
    let client = try connect(engine)

    #expect(throws: ControlError.self) { try client.epic(repo: "acme/web", issue: 0) }
    #expect(throws: ControlError.self) { try client.events(executionId: "not-a-uuid") }
    #expect(throws: ControlError.self) { try client.events(executionId: execution, limit: 201) }
    #expect(throws: ControlError.self) { try client.events(executionId: execution, after: -1) }
    #expect(throws: ControlError.self) { try client.files(repo: "acme/web", issue: 1, executionId: "x\"y") }
    #expect(engine.commands.isEmpty)
}
