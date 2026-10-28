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
        case .tools(_, let group): "tools: \(group.title) | \(group.summary)"
        case .approval(_, let card): "card: \(card.question) | \(card.arg ?? "") | \(card.choices.map(\.label).joined(separator: " / "))"
        case .decided(_, let text, let allow): "\(allow ? "allowed" : "declined"): \(text)"
        case .line(_, let text): "line: \(text)"
        case .error(_, let text): "error: \(text)"
        }
    }
}

/// The one group of a feed.
private func group(_ rows: [FeedRow]) -> ToolGroup {
    rows.compactMap { if case .tools(_, let group) = $0 { group } else { nil } }[0]
}

// MARK: the feed

@Test func aFinishedTurnIsMessagesGroupedCallsAndAClosingLine() throws {
    let rows = chatFeed(try golden("finished").events)
    #expect(texts(rows) == [
        "user: Explore the pricing page layout and tell me what to change.",
        "tools: Explored | 1 file read · 1 search",
        "allowed: Allowed Bash pnpm lint · Allow · by you",
        "tools: Worked | 1 command",
        "agent: The page is two componen",
        "end: claude-sonnet-5-5 · 12s · 1.8k in · 436 out",
        "user: Now run the tests.",
        "error: The turn failed",
        "end: claude-sonnet-5-5 · 1s",
    ])
}

@Test func anApprovalIsOneRowAtItsPlaceCompletedByItsAnswerAndEndsTheRunBeforeIt() {
    let start = ChatEvent(id: 1, at: 0, kind: "tool_start", callId: "c", tool: "Read", arg: "a.ts")
    let ask = ChatEvent(id: 2, at: 0, kind: "approval", tool: "Bash", arg: "ls", approvalId: "p", choices: [.init(id: "y", label: "Yes", allow: true)])
    #expect(texts(chatFeed([start, ask], pending: ["p"])) == ["tools: Working | 1 file read", "card: Allow Bash? | ls | Yes"])
    let end = ChatEvent(id: 3, at: 0, kind: "tool_end", callId: "c", tool: "Read", output: ["", "  one", "two"], status: "ok")
    let answer = ChatEvent(id: 4, at: 0, kind: "approval_answered", approvalId: "p", choiceId: "y")
    let rows = chatFeed([start, ask, end, answer])
    #expect(texts(rows) == ["tools: Explored | 1 file read", "allowed: Allowed Bash ls · Yes · by you"])
    // the rows keep the id of the event that opened them
    #expect(rows.map { $0.id } == ["e1", "e2"])
}

@Test func anAskedApprovalIsACardWithTheProvidersChoicesInItsOrderForClaudeAndForCodex() throws {
    let claude = chatFeed(try golden("finished").events.prefix(6).map { $0 }, pending: ["a1"])
    #expect(texts(claude).last == "card: Allow Bash? | pnpm lint | Allow / Allow for this session / Decline")
    guard case .approval(_, let card)? = claude.last else {
        Issue.record("not a card")
        return
    }
    #expect(card.approvalId == "a1" && card.choices.map(\.allow) == [true, true, false])
    let codex = chatFeed(try golden("approval").events, pending: ["b1"])
    guard case .approval(_, let asked)? = codex.last else {
        Issue.record("not a card")
        return
    }
    #expect(asked.choices.map(\.id) == ["accept", "acceptForSession", "decline", "cancel"] && asked.choices.map(\.allow) == [true, true, false, false])
}

@Test func anAnsweredApprovalIsOneLineWithTheChosenLabelAndWhetherItAllowedAndADeclinedOneSaysSo() {
    let choices: [ChatChoice] = [.init(id: "y", label: "Allow for this session", allow: true), .init(id: "n", label: "Decline", allow: false)]
    let ask = ChatEvent(id: 1, at: 0, kind: "approval", tool: "Bash", arg: "pnpm test webhook", approvalId: "p", choices: choices)
    func line(_ choice: String) -> String { texts(chatFeed([ask, ChatEvent(id: 2, at: 0, kind: "approval_answered", approvalId: "p", choiceId: choice)]))[0] }
    #expect(line("y") == "allowed: Allowed Bash pnpm test webhook · Allow for this session · by you")
    #expect(line("n") == "declined: Declined Bash pnpm test webhook · Decline · by you")
    // an answer naming a choice the question never had still closes the card
    #expect(line("?") == "declined: Answered Bash pnpm test webhook · by you")
}

@Test func anApprovalThatIsNeitherPendingNorAnsweredIsAPlainLineNotACard() {
    let ask = ChatEvent(id: 1, at: 0, kind: "approval", tool: "Bash", arg: "ls", approvalId: "p", choices: [.init(id: "y", label: "Yes", allow: true)])
    #expect(texts(chatFeed([ask, ChatEvent(id: 2, at: 0, kind: "turn_end", outcome: "interrupted")])) == ["line: Bash ls · no longer waiting for an answer"])
}

@Test func theHostsPendingApprovalsAreReadFromTheEventsReply() throws {
    let reply = try JSONDecoder().decode(ChatEvents.self, from: Data(#"{"events":[],"cursor":0,"streaming":"","approvals":[{"approvalId":"p","tool":"Bash","choices":[]}],"options":[]}"#.utf8))
    #expect(reply.pending == ["p"])
}

@Test func anEndWithNoStartAndAnAnswerWithNoQuestionAreHandledWhereACursorCanStartMidTurn() {
    let end = ChatEvent(id: 7, at: 0, kind: "tool_end", callId: "x", tool: "Bash", arg: "ls", status: "err")
    let answer = ChatEvent(id: 8, at: 0, kind: "approval_answered", approvalId: "gone", choiceId: "y")
    #expect(texts(chatFeed([end, answer])) == ["tools: Worked | 1 command"])
    #expect(group(chatFeed([end])).failed == 1)
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

// MARK: tools, grouped

private func call(_ id: Int, _ tool: String, _ arg: String = "", output: [String]? = nil, status: String = "ok", at: Int = 0, took: Int = 100) -> [ChatEvent] {
    [ChatEvent(id: id * 2, at: at, kind: "tool_start", callId: "c\(id)", tool: tool, arg: arg),
     ChatEvent(id: id * 2 + 1, at: at + took, kind: "tool_end", callId: "c\(id)", tool: tool, output: output, status: status)]
}

@Test func theClassificationIsATableByTheProvidersToolName() {
    let kinds = ["Read", "Grep", "Glob", "Edit", "Write", "MultiEdit", "apply_patch", "Bash", "shell", "command", "WebFetch", "read", ""].map { ToolKind(tool: $0) }
    #expect(kinds == [.read, .search, .search, .edit, .edit, .edit, .edit, .shell, .shell, .shell, .other, .other, .other])
}

@Test func aGoldenRunOfCallsIsOneRowWithItsSummaryTitleAndTotals() throws {
    let rows = chatFeed(try golden("tools").events)
    #expect(texts(rows) == [
        "user: The login test is flaky. Find out why and fix it.",
        "tools: Explored | 2 files read · 1 search",
        "agent: The test does not wait f",
        "tools: Changed | 2 files changed · 1 command",
        "agent: One test still fails. Le",
        "tools: Worked | 1 other tool",
        "agent: The server is fine, so t",
        "end: claude-sonnet-5-5 · 16s · 2.1k in · 310 out",
    ])
    let explored = group(rows)
    #expect(explored.calls.map(\.result) == ["3 lines", "3 lines", "2 matches"] && explored.durationMs == 1600 && explored.failed == 0)
    let changed = rows.compactMap { if case .tools(_, let group) = $0 { group } else { nil } }[1]
    // three edits of two paths; only the output shaped like a diff has lines to total
    #expect(changed.calls.count == 4 && changed.added == 3 && changed.removed == 1 && changed.durationMs == 7_000)
    #expect(changed.calls.map(\.result) == ["done", "+2 −1", "+1 −0", "failed"])
    #expect(changed.calls[1].diff.map(\.sign) == [.hunk, .hunk, .hunk, .context, .removed, .added, .added, .context])
    #expect(changed.calls[1].diff[4].text == "  await open()")
    // a call that failed turns the group's count, not its title
    #expect(changed.failed == 1 && changed.title == "Changed")
}

@Test func theSummaryIsTheNonZeroCountsInOrderSingularWhenOneAndFilesChangedCountDistinctPaths() {
    func summary(_ calls: [[ChatEvent]]) -> String { group(chatFeed(calls.flatMap { $0 })).summary }
    #expect(summary([call(1, "Read", "a"), call(2, "Read", "b")]) == "2 files read")
    #expect(summary([call(1, "Read", "a")]) == "1 file read")
    #expect(summary([call(1, "Grep", "x"), call(2, "Glob", "*.ts")]) == "2 searches")
    #expect(summary([call(1, "Grep", "x")]) == "1 search")
    #expect(summary([call(1, "Bash", "a"), call(2, "shell", "b")]) == "2 commands")
    #expect(summary([call(1, "WebFetch", "u")]) == "1 other tool")
    #expect(summary([call(1, "Mystery"), call(2, "Another")]) == "2 other tools")
    // distinct paths: the same file edited, written and patched is one file changed
    #expect(summary([call(1, "Edit", "a.ts"), call(2, "Write", "a.ts"), call(3, "apply_patch", "a.ts")]) == "1 file changed")
    #expect(summary([call(1, "Edit", "a.ts"), call(2, "MultiEdit", "b.ts")]) == "2 files changed")
    // all five, in the order reads, searches, changes, commands, other
    #expect(summary([call(1, "Bash", "x"), call(2, "WebFetch", "u"), call(3, "Edit", "a"), call(4, "Edit", "b"), call(5, "Grep", "q"), call(6, "Read", "a"), call(7, "Read", "b")])
        == "2 files read · 1 search · 2 files changed · 1 command · 1 other tool")
}

@Test func theTitleIsExploredForReadsAndSearchesChangedForAChangeAndWorkedOtherwise() {
    func title(_ calls: [[ChatEvent]]) -> String { group(chatFeed(calls.flatMap { $0 })).title }
    #expect(title([call(1, "Read", "a"), call(2, "Grep", "b")]) == "Explored")
    #expect(title([call(1, "Read", "a"), call(2, "Edit", "a")]) == "Changed")
    #expect(title([call(1, "Bash", "ls")]) == "Worked")
    #expect(title([call(1, "Read", "a"), call(2, "Bash", "ls")]) == "Worked")
    #expect(title([call(1, "Mystery")]) == "Worked")
    #expect(title([call(1, "Mystery"), call(2, "Write", "a")]) == "Changed")
}

@Test func theCallsOfAFailedGroupAreMarkedAndTheRowCountsThem() {
    let events = call(1, "Read", "a") + call(2, "Bash", "pnpm test", output: ["boom"], status: "err") + call(3, "Bash", "pnpm lint", status: "err")
    let tools = group(chatFeed(events))
    #expect(tools.failed == 2 && tools.calls.map(\.status) == [.ok, .failed, .failed])
    #expect(tools.calls[1].result == "failed" && tools.calls[1].output == ["boom"])
}

@Test func aRunStillGoingIsWorkingAndSaysWhatTheAgentIsDoingUntilItsCallEnds() {
    let done = call(1, "Read", "src/a.ts", output: ["x"], at: 1000)
    let running = ChatEvent(id: 10, at: 3000, kind: "tool_start", callId: "c9", tool: "Bash", arg: "pnpm test webhook")
    var tools = group(chatFeed(done + [running]))
    #expect(tools.isWorking && tools.title == "Working" && tools.doing == "Running pnpm test webhook" && tools.durationMs == nil)
    #expect(tools.summary == "1 file read · 1 command")
    // the next event that arrives completes it in place
    let end = ChatEvent(id: 11, at: 9000, kind: "tool_end", callId: "c9", tool: "Bash", output: ["ok"], status: "ok")
    tools = group(chatFeed(done + [running, end]))
    #expect(tools.isWorking == false && tools.doing == nil && tools.title == "Worked" && tools.durationMs == 8000)
    // a turn that ends with a call still going (stopped, or failed) does not leave the row working
    let stopped = group(chatFeed(done + [running, ChatEvent(id: 12, at: 4000, kind: "turn_end", outcome: "aborted")]))
    #expect(stopped.isWorking == false && stopped.calls.map(\.status) == [.ok, .stopped])
    #expect(["Reading a", "Searching b", "Editing c", "Using Mystery d"] == [("Read", "a"), ("Grep", "b"), ("Edit", "c"), ("Mystery", "d")].map {
        group(chatFeed([ChatEvent(id: 1, at: 0, kind: "tool_start", callId: "x", tool: $0.0, arg: $0.1)])).doing!
    })
}

@Test func textBetweenCallsOpensANewRowAndTheCallsOfOneRunStayTogetherWhateverOrderTheyEnd() {
    let a = call(1, "Read", "a"), b = call(2, "Read", "b")
    // the second call starts before the first ends: still one run, the results land on their own call
    let events = [a[0], b[0], b[1], a[1], ChatEvent(id: 20, at: 0, kind: "assistant", text: "ok")] + call(3, "Read", "c")
    let rows = chatFeed(events)
    #expect(texts(rows) == ["tools: Explored | 2 files read", "agent: ok", "tools: Explored | 1 file read"])
    #expect(group(rows).calls.map(\.arg) == ["a", "b"] && group(rows).calls.allSatisfy { $0.status == .ok })
}

@Test func theTimeOfAGroupIsFromItsFirstStartToItsLastEnd() {
    let rows = chatFeed(call(1, "Read", "a", at: 1000, took: 500) + call(2, "Bash", "b", at: 2000, took: 4000))
    #expect(group(rows).durationMs == 5000)
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
    #expect(try await host.events("e5f6a7b8-4c3d-4e0f-9a2b-3c4d5e6f7a05", after: 0, limit: 200).events.isEmpty)
    // the Codex session is waiting: its approval is pending
    #expect(try await host.events("8a2e4b6d-1c3f-4d57-8e9a-0b1c2d3e4f02", after: 0, limit: 200).pending == ["b1"])
    await #expect(throws: ControlError.remote("unknown session")) { try await host.events(UUID().uuidString, after: 0, limit: 200) }
    await #expect(throws: ControlError.remote("not a valid session id")) { try await host.events("../x\",\"cmd\":\"stop", after: 0, limit: 200) }
}

@Test func theFixtureHostRecordsAnAnswerAndRefusesOneThatIsNotPendingOrNotAChoice() async throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.chatSocketPath })
    let waiting = "8a2e4b6d-1c3f-4d57-8e9a-0b1c2d3e4f02"
    await #expect(throws: ControlError.remote("That is not one of the choices")) { try await host.answer(waiting, approval: "b1", choice: "maybe") }
    await #expect(throws: ControlError.remote("That approval is not pending: it is unknown or was already answered")) { try await host.answer(waiting, approval: "zz", choice: "accept") }
    try await host.answer(waiting, approval: "b1", choice: "decline")
    let after = try await host.events(waiting, after: 4, limit: 200)
    #expect(after.pending.isEmpty && after.events.map(\.kind) == ["approval_answered"] && after.events[0].choiceId == "decline")
}

@Test func theLongConversationBehindTheFlagIsServedInPagesAndMakesAFeed() async throws {
    let server = try FixtureServer(fixtures: fixtures, longTranscript: true)
    defer { server.stop() }
    let model = await ConversationModel(host: SocketChatHost(socketPath: { server.chatSocketPath }), sessionId: "5d1f7c3a-0b6e-4a52-9a1d-3c7e8b2f4a01")
    await model.poll()
    #expect(await model.cursor == 3500)
    // a message, the two calls as one row, an answer and the turn's end: four rows a round
    #expect(await model.rows.count == 2000)
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
    func answer(_ id: String, approval: String, choice: String) async throws {}
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
