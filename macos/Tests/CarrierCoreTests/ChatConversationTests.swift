import Foundation
import Testing
@testable import CarrierCore

private let fixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures").path

/// A golden conversation as the host's `events` reply carries it.
private func golden(_ name: String) throws -> ChatEvents {
    try JSONDecoder().decode(ChatEvents.self, from: Data(contentsOf: URL(fileURLWithPath: fixtures + "/chat-events-\(name).json")))
}

private func texts(_ rows: [FeedRow]) -> [String] {
    rows.map {
        switch $0 {
        case .user(_, let text): "user: \(text)"
        case .agent(_, let text, let inProgress): "agent\(inProgress ? "…" : ""): \(text.prefix(24))"
        case .turnEnd(_, let text): "end: \(text)"
        case .line(_, let text): "line: \(text)"
        case .error(_, let text): "error: \(text)"
        }
    }
}

// MARK: the feed

@Test func aFinishedTurnIsMessagesPlainLinesAndAClosingLine() throws {
    let rows = chatFeed(try golden("finished").events)
    #expect(texts(rows) == [
        "user: Explore the pricing page layout and tell me what to change.",
        "line: Glob src/pricing/**/*.tsx · src/pricing/Page.tsx",
        "line: Read src/pricing/Plans.tsx · export function Plans() {",
        "line: Approval for Bash pnpm lint: Allow once",
        "line: Bash pnpm lint · failed: src/pricing/Plans.tsx",
        "agent: The page is two componen",
        "end: claude-sonnet-5-5 · 12s · 1.8k in · 436 out",
        "user: Now run the tests.",
        "error: The turn failed",
        "end: claude-sonnet-5-5 · 1s",
    ])
}

@Test func aCallIsOneRowAtItsStartCompletedByItsEndAndAnApprovalByItsAnswer() {
    let start = ChatEvent(id: 1, at: 0, kind: "tool_start", callId: "c", tool: "Read", arg: "a.ts")
    let ask = ChatEvent(id: 2, at: 0, kind: "approval", tool: "Bash", arg: "ls", approvalId: "p", choices: [.init(id: "y", label: "Yes", allow: true)])
    #expect(texts(chatFeed([start, ask])) == ["line: Read a.ts", "line: Approval for Bash ls: waiting for you"])
    let end = ChatEvent(id: 3, at: 0, kind: "tool_end", callId: "c", tool: "Read", output: ["", "  one", "two"], status: "ok")
    let answer = ChatEvent(id: 4, at: 0, kind: "approval_answered", approvalId: "p", choiceId: "y")
    let rows = chatFeed([start, ask, end, answer])
    #expect(texts(rows) == ["line: Read a.ts · one", "line: Approval for Bash ls: Yes"])
    // the rows keep the id of the event that opened them
    #expect(rows.map { $0.id } == ["e1", "e2"])
}

@Test func anEndWithNoStartAndAnAnswerWithNoQuestionAreHandledWhereACursorCanStartMidTurn() {
    let end = ChatEvent(id: 7, at: 0, kind: "tool_end", callId: "x", tool: "Bash", arg: "ls", status: "err")
    let answer = ChatEvent(id: 8, at: 0, kind: "approval_answered", approvalId: "gone", choiceId: "y")
    #expect(texts(chatFeed([end, answer])) == ["line: Bash ls · failed"])
}

@Test func theMessageInProgressIsTheLastRowAndOptionsAreNotDrawn() throws {
    let reply = try golden("streaming")
    let rows = chatFeed(reply.events + [ChatEvent(id: 4, at: 0, kind: "option", text: nil)], streaming: reply.streaming)
    #expect(rows.count == 3)
    guard case .agent("streaming", let text, true) = rows.last else {
        Issue.record("the last row is not the message in progress")
        return
    }
    #expect(text.hasPrefix("The worker calls `push()`"))
    #expect(chatFeed(reply.events, streaming: "").count == 2)
}

@Test func theClosingLineHasWhatTheHostAndTheProviderGave() {
    func line(_ end: ChatEvent, from start: Int? = 0) -> String? {
        let user = start.map { [ChatEvent(id: 1, at: $0, kind: "user", text: "hi")] } ?? []
        return chatFeed(user + [end]).compactMap { if case .turnEnd(_, let text) = $0 { text } else { nil } }.first
    }
    func end(model: String? = nil, usage: [String: Double]? = nil, at: Int = 65_000) -> ChatEvent { ChatEvent(id: 2, at: at, kind: "turn_end", outcome: "ok", model: model, usage: usage) }
    #expect(line(end(model: "m", usage: ["input_tokens": 12, "output_tokens": 2500, "total_cost_usd": 0.5])) == "m · 1m · 12 in · 2.5k out")
    // Codex reports in camel case; a usage with only some of the counts shows only those
    #expect(line(end(model: "gpt", usage: ["inputTokens": 900], at: 4000)) == "gpt · 4s · 900 in")
    #expect(line(end(model: "m", usage: [:], at: 4000)) == "m · 4s")
    // a page that starts after the turn began has no start to measure from
    #expect(line(end(model: "m", usage: ["input_tokens": 5]), from: nil) == "m · 5 in")
    #expect(line(end(), from: nil) == nil)
}

// MARK: the markdown the agent writes

@Test func theAgentsMessageHasParagraphsListsInlineCodeAndCodeBlocksWithTheirLanguage() throws {
    let message = try #require(try golden("finished").events.first { $0.kind == "assistant" }?.text)
    let blocks = markdownBlocks(message)
    func shape(_ block: MarkdownBlock) -> String {
        switch block {
        case .line: "line"
        case .bullet(let level, _): "bullet\(level)"
        case .code(let language, let code): "code \(language ?? "-") \(code.split(separator: "\n").count)"
        case .gap: "gap"
        }
    }
    #expect(blocks.map(shape) == [
        "line", "gap", "line", "gap", "bullet0", "bullet0", "bullet1", "bullet0", "gap", "line", "gap", "code tsx 7", "gap", "line", "gap", "code - 1",
    ])
    guard case .line(let first) = blocks[0] else { return }
    #expect(first.runs.contains { $0.inlinePresentationIntent == .code && String(first.characters[$0.range]) == "Page.tsx" })
    // the code is kept as written: its indentation and the lines of a block with a blank one
    guard case .code(_, let code) = blocks[11] else { return }
    #expect(code.hasPrefix("export function Plans") && code.contains("\n    <section className="))
}

@Test func aFenceLeftOpenByAMessageStillBeingWrittenIsABlockToTheEnd() throws {
    let blocks = markdownBlocks(try golden("streaming").streaming)
    guard case .code(let language, let code) = blocks.last else {
        Issue.record("the open fence is not a code block")
        return
    }
    #expect(language == "ts" && code.hasSuffix("try { return await push() } catch"))
    #expect(markdownBlocks("```\n\n\nx\n```") == [.code(language: nil, "\n\nx")])
}

// MARK: the fixture host and the client

@Test func theClientAsksEventsByCursorFromTheFixtureHost() async throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.chatSocketPath })
    let finished = "c3d4e5f6-2a1b-4c8d-9e0f-1a2b3c4d5e03"
    let first = try await host.events(finished, after: 0, limit: 5)
    #expect(first.events.map(\.id) == [1, 2, 3, 4, 5] && first.cursor == 5)
    let rest = try await host.events(finished, after: first.cursor, limit: 200)
    #expect(rest.events.count == 9 && rest.cursor == 14)
    // nothing new: the cursor stays where it was
    #expect(try await host.events(finished, after: 14, limit: 200) == ChatEvents(events: [], cursor: 14, state: .idle))
    #expect(try await host.events("5d1f7c3a-0b6e-4a52-9a1d-3c7e8b2f4a01", after: 0, limit: 200).streaming.hasPrefix("The worker calls"))
    // a listed session with no golden file has no events; one that is not listed, or not a UUID, is refused
    #expect(try await host.events("8a2e4b6d-1c3f-4d57-8e9a-0b1c2d3e4f02", after: 0, limit: 200).events.isEmpty)
    await #expect(throws: ControlError.remote("unknown session")) { try await host.events(UUID().uuidString, after: 0, limit: 200) }
    await #expect(throws: ControlError.remote("not a valid session id")) { try await host.events("../x\",\"cmd\":\"stop", after: 0, limit: 200) }
}

@Test func theLongConversationBehindTheFlagIsServedInPagesAndMakesAFeed() async throws {
    let server = try FixtureServer(fixtures: fixtures, longTranscript: true)
    defer { server.stop() }
    let model = await ConversationModel(host: SocketChatHost(socketPath: { server.chatSocketPath }), sessionId: "5d1f7c3a-0b6e-4a52-9a1d-3c7e8b2f4a01")
    await model.poll()
    #expect(await model.cursor == 3500)
    // a message, two calls as one line each, an answer and the turn's end: five rows a round
    #expect(await model.rows.count == 2500)
}

// MARK: the model

private final class ScriptedHost: ChatHost, @unchecked Sendable {
    var events: [ChatEvent] = []
    var streaming = ""
    var failing: Error?
    var asked: [(after: Int, limit: Int)] = []

    func agents() async throws -> [ChatAgent] { [] }
    func list(archived: Bool) async throws -> [ChatSession] { [] }
    func resume(_ id: String) async throws {}
    func send(_ id: String, _ text: String) async throws {}
    func interrupt(_ id: String) async throws {}
    func events(_ id: String, after: Int, limit: Int) async throws -> ChatEvents {
        asked.append((after, limit))
        if let failing { throw failing }
        let page = Array(events.filter { $0.id > after }.prefix(limit))
        return ChatEvents(events: page, cursor: page.last?.id ?? after, streaming: streaming)
    }
}

private func say(_ id: Int) -> ChatEvent { ChatEvent(id: id, at: id, kind: "assistant", text: "m\(id)") }

@MainActor @Test func thePollAsksByCursorInPagesOfAtMost200AndStopsAtANonFullPage() async {
    let host = ScriptedHost()
    host.events = (1...450).map(say)
    let model = ConversationModel(host: host, sessionId: "s", log: { _ in })
    await model.poll()
    #expect(host.asked.map(\.after) == [0, 200, 400] && host.asked.allSatisfy { $0.limit == 200 })
    #expect(model.cursor == 450 && model.rows.count == 450 && model.loaded)
    // the next round asks from the cursor and finds only what is new
    host.events.append(say(451))
    await model.poll()
    #expect(host.asked.last?.after == 450 && model.rows.count == 451)
    // a page that is exactly full is followed by one more, which is empty
    host.events += (452...651).map(say)
    await model.poll()
    #expect(model.cursor == 651 && host.asked.suffix(2).map(\.after) == [451, 651])
}

@MainActor @Test func theStreamingTextIsTheMessageInProgressAndGoesWhenTheMessageIsStored() async {
    let host = ScriptedHost()
    host.events = [ChatEvent(id: 1, at: 1, kind: "user", text: "hi")]
    host.streaming = "Hel"
    let model = ConversationModel(host: host, sessionId: "s", log: { _ in })
    await model.poll()
    #expect(texts(model.rows) == ["user: hi", "agent…: Hel"])
    host.streaming = "Hello there"
    await model.poll()
    #expect(texts(model.rows) == ["user: hi", "agent…: Hello there"])
    host.events.append(ChatEvent(id: 2, at: 2, kind: "assistant", text: "Hello there"))
    host.streaming = ""
    await model.poll()
    #expect(texts(model.rows) == ["user: hi", "agent: Hello there"])
}

@MainActor @Test func aFailedPollIsSaidOnceAndTheNextOneThatWorksClearsIt() async {
    let host = ScriptedHost()
    host.events = [say(1)]
    var logged: [String] = []
    let model = ConversationModel(host: host, sessionId: "s", log: { logged.append($0) })
    await model.poll()
    host.failing = ControlError.closed
    await model.poll()
    await model.poll()
    #expect(model.failure == "The chat host is not answering" && model.rows.count == 1 && logged.count == 1)
    host.failing = nil
    host.events.append(say(2))
    await model.poll()
    #expect(model.failure == nil && model.rows.count == 2)
    host.failing = ControlError.remote("unknown session")
    await model.poll()
    #expect(model.failure == "unknown session" && logged.count == 2)
}

@MainActor @Test func runPollsAboutEvery250msUntilItIsCancelled() async {
    let host = ScriptedHost()
    var waits: [Duration] = []
    let model = ConversationModel(host: host, sessionId: "s", sleep: { waits.append($0); if waits.count == 3 { throw CancellationError() } }, log: { _ in })
    await model.run()
    #expect(host.asked.count == 3 && waits == Array(repeating: .milliseconds(250), count: 3))
}
