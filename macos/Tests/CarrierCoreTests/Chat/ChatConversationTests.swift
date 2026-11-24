import Foundation
import Observation
import Testing
@testable import CarrierCore

private let fixtures = testPaths().fixtures.path

/// A golden conversation as the host's `events` reply carries it.
private func golden(_ name: String) throws -> ChatEvents {
    try JSONDecoder().decode(ChatEvents.self, from: Data(contentsOf: URL(fileURLWithPath: fixtures + "/chat-events-\(name).json")))
}

private func texts(_ rows: [FeedRow]) -> [String] {
    rows.map {
        switch $0 {
        case .user(_, let text): "user: \(text)"
        case .agent(_, let text, let inProgress): "agent\(inProgress ? "…" : ""): \(text.prefix(24))"
        case .turnEnd(_, let summary): "end: \(summary.text)"
        case .tools(_, let group): "tools: \(group.title) | \(group.summary)"
        case .approval(_, let card): "card: \(card.question) | \(card.arg ?? "") | \(card.choices.map(\.label).joined(separator: " / "))"
        case .decided(_, let text, let allow): "\(allow ? "allowed" : "declined"): \(text)"
        case .line(_, let text): "line: \(text)"
        case .switched(_, let switched): "switched: \(switched.from) -> \(switched.to)"
        case .error(_, let text): "error: \(text)"
        case .stopped: "stopped"
        case .cleared(_, let freed): "cleared: \(clearedFreedText(freed) ?? "")"
        case .compacted(_, let cut): "compacted: \([cut.title, cut.sizes, cut.saved].compactMap { $0 }.joined(separator: " | "))"
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
        "end: sonnet 5.5 · 12s · 46.8k context · 436 out",
        "user: Now run the tests.",
        "error: The turn failed",
        "end: sonnet 5.5 · 1s",
    ])
}

@Test func aStoppedTurnLeavesTheMarkAfterItsClosingLineAndOnlyTheLastOneOffersAWayOut() throws {
    let rows = chatFeed(try golden("stopped").events)
    #expect(texts(rows) == ["user: Rename the config keys to snake_case.", "agent: I will start with the ke", "end: sonnet 5.5 · 4s", "stopped"])
    #expect(openOutcome(rows) == rows.last?.id)
    // the person wrote again: the mark is a record
    #expect(openOutcome(rows + [.user(id: "u", text: "go on")]) == nil)
    // the failed turn of the finished golden is the last thing there, so its banner is the one that offers Try again
    let failed = chatFeed(try golden("finished").events)
    #expect(openOutcome(failed) == failed.first { if case .error = $0 { true } else { false } }?.id)
    #expect(openOutcome(Array(failed.prefix(6))) == nil)
}

@Test func theBannersSayWhoCouldNotContinueAndWhatTheHostSaid() {
    #expect(failedTurnBanner(agent: "claude", error: "Usage limit reached") == FailureBanner(title: "Claude couldn't continue", detail: "Usage limit reached", hint: nil))
    #expect(failedTurnBanner(agent: "", error: "x").title == "The agent couldn't continue")
    // a label or display name the person wrote keeps its capitals
    #expect(failedTurnBanner(agent: "iOS", error: "x").title == "iOS couldn't continue" && failedTurnBanner(agent: "Claude Pro", error: "x").title == "Claude Pro couldn't continue")
    let refused = refusalBanner(agent: "codex", reason: .words("The agent is still answering"))
    #expect(refused == FailureBanner(title: "Codex couldn't continue", detail: "The agent is still answering", hint: nil))
    let signedOut = refusalBanner(agent: "claude", reason: Refusal(code: "agent.notLoggedIn", params: ["agent": "claude"], text: "Claude is not logged in; run \"claude\" once to log in"))
    #expect(signedOut.title == "Claude isn't signed in" && signedOut.detail == "Claude is not logged in; run \"claude\" once to log in")
    #expect(signedOut.hint == "Sign in from a terminal; Carrier never asks for your password")
}

@Test func theSignInLineFollowsTheCodeAndNotTheWords() {
    let signIn = "Sign in from a terminal; Carrier never asks for your password"
    // the words differ from today's: only the code says the provider is signed out
    #expect(signInLine(refusal: Refusal(code: "agent.notLoggedIn", params: ["agent": "claude"], text: "Please sign in")) == signIn)
    // a code that is not that one is not a sign-in, whatever the words say
    #expect(signInLine(refusal: Refusal(code: "agent.notInstalled", params: ["agent": "claude"], text: "Claude is not logged in")) == nil)
    // a reply without a code carries words only, and the words are not read
    #expect(signInLine(refusal: .words("Claude is not logged in; run \"claude\" once to log in")) == nil)
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
    #expect(texts(chatFeed([ask, ChatEvent(id: 2, at: 0, kind: "turn_end", outcome: "interrupted")])) == ["line: Bash ls · no longer waiting for an answer", "stopped"])
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
        return chatFeed(user + [end]).compactMap { if case .turnEnd(_, let summary) = $0 { summary.text } else { nil } }.first
    }
    func end(model: String? = nil, usage: [String: Double]? = nil, at: Int = 65_000) -> ChatEvent { ChatEvent(id: 2, at: at, kind: "turn_end", outcome: "ok", model: model, usage: usage) }
    #expect(line(end(model: "m", usage: ["input_tokens": 12, "output_tokens": 2500, "total_cost_usd": 0.5])) == "m · 1m · 12 in · 2.5k out")
    // what the calls of the turn read added up is not the context, so it is not called that: only a host that says the last call's size does
    #expect(line(end(model: "m", usage: ["input_tokens": 12, "cache_read_input_tokens": 500_000, "context_tokens": 181_200, "output_tokens": 130])) == "m · 1m · 181.2k context · 130 out")
    #expect(line(end(model: "gpt", usage: ["inputTokens": 900_000, "contextTokens": 95_000], at: 4000)) == "gpt · 4s · 95.0k context")
    // the cache counts toward what the model read
    #expect(line(end(model: "m", usage: ["input_tokens": 2, "cache_read_input_tokens": 22_000, "cache_creation_input_tokens": 100, "output_tokens": 130])) == "m · 1m · 22.1k in · 130 out")
    // Codex reports in camel case; a usage with only some of the counts shows only those
    #expect(line(end(model: "gpt", usage: ["inputTokens": 900], at: 4000)) == "gpt · 4s · 900 in")
    #expect(line(end(model: "m", usage: [:], at: 4000)) == "m · 4s")
    // a page that starts after the turn began has no start to measure from
    #expect(line(end(model: "m", usage: ["input_tokens": 5]), from: nil) == "m · 5 in")
    #expect(line(end(), from: nil) == nil)
}

@Test func aModelIsNamedAsAPersonSaysIt() {
    func short(_ model: String?) -> String? { TurnSummary(model: model).shortModel }
    #expect(short("claude-haiku-5-5") == "haiku 5.5")
    #expect(short("claude-opus-4-1-20250805") == "opus 4.1")
    #expect(short("claude-sonnet-5") == "sonnet 5")
    #expect(short("gpt-5-codex") == "gpt-5-codex")
    #expect(short("claude-future") == "claude-future")
    #expect(short(nil) == nil)
}

@Test func aClosingLineAfterAnAgentMessageMovesIntoIt() {
    let rows: [FeedRow] = [.user(id: "u", text: "hi"), .agent(id: "a", text: "yes", inProgress: false), .turnEnd(id: "t1", TurnSummary(model: "m", duration: "2s")),
                           .tools(id: "g", ToolGroup(calls: [])), .turnEnd(id: "t2", TurnSummary(model: "m", duration: "9s"))]
    let folded = foldingClosingLines(rows)
    #expect(folded.lines == ["a": TurnSummary(model: "m", duration: "2s")])
    #expect(folded.rows.map(\.id) == ["u", "a", "g", "t2"])
}

// MARK: tools, grouped

private func call(_ id: Int, _ tool: String, _ arg: String = "", output: [String]? = nil, status: String = "ok", at: Int = 0, took: Int = 100) -> [ChatEvent] {
    [ChatEvent(id: id * 2, at: at, kind: "tool_start", callId: "c\(id)", tool: tool, arg: arg),
     ChatEvent(id: id * 2 + 1, at: at + took, kind: "tool_end", callId: "c\(id)", tool: tool, output: output, status: status)]
}

@Test func theClassificationIsATableByTheProvidersToolName() {
    let kinds = ["Read", "Grep", "Glob", "Edit", "Write", "MultiEdit", "apply_patch", "Bash", "shell", "command", "WebFetch", "read", ""].map { ToolKind(tool: $0) }
    #expect(kinds == [.read, .search, .search, .edit, .edit, .edit, .edit, .shell, .shell, .shell, .other, .other, .other])
    #expect(ToolKind(tool: "mcp__linear__create_issue") == .mcp(server: "linear", tool: "create_issue"))
    #expect(ToolKind(tool: "mcp__claude_ai_Notion__notion-fetch") == .mcp(server: "claude_ai_Notion", tool: "notion-fetch"))
    #expect(["mcp__only", "mcp____x", "mcp__a__"].map { ToolKind(tool: $0) } == [.other, .other, .other])
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
        "end: sonnet 5.5 · 16s · 2.1k in · 310 out",
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
    // all six, in the order reads, searches, changes, commands, MCP calls, other
    #expect(summary([call(1, "Bash", "x"), call(2, "WebFetch", "u"), call(3, "Edit", "a"), call(4, "Edit", "b"), call(5, "Grep", "q"), call(6, "Read", "a"), call(7, "Read", "b"), call(8, "mcp__linear__create_issue")])
        == "2 files read · 1 search · 2 files changed · 1 command · 1 MCP call · 1 other tool")
    #expect(summary([call(1, "mcp__linear__create_issue"), call(2, "mcp__notion__fetch")]) == "2 MCP calls")
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

@Test func aNoticeFromTheHostIsAPlainLineAndNeverTheBannerThatOffersTryAgain() {
    let rows = chatFeed([
        ChatEvent(id: 1, at: 0, kind: "user", text: "go"),
        ChatEvent(id: 2, at: 1, kind: "notice", text: "The agent could not find this conversation"),
    ])
    #expect(rows.last == .line(id: "e2", text: "The agent could not find this conversation"))
    #expect(openOutcome(rows) == nil)
}

@Test func aChangeOfAgentIsItsOwnRowWithBothAgentsAndWordsOfWhatCarriedOver() {
    let rows = chatFeed([
        ChatEvent(id: 1, at: 0, kind: "user", text: "Hola"),
        ChatEvent(id: 2, at: 1, kind: "notice", text: "The agent changed from claude-teams-lu to codex. ...", switched: .init(from: "claude-teams-lu", to: "codex", fromModel: "claude-sonnet-5-5", toModel: "gpt-5")),
    ])
    #expect(rows.last == .switched(id: "e2", .init(from: "claude-teams-lu", to: "codex", fromModel: "claude-sonnet-5-5", toModel: "gpt-5")) && rows.last?.id == "e2")
    #expect(handoffDetail(to: "codex") == "codex goes on from a selection of the messages above and can read the rest. Reasoning and tool results did not carry over.")
    #expect(openOutcome(rows) == nil)
}

@Test func aTurnThatEndsInAnErrorMarksItsLastRunFailedAndAnAnswerAfterTheRunKeepsItClean() {
    let ended = chatFeed([
        ChatEvent(id: 1, at: 0, kind: "user", text: "go"),
        ChatEvent(id: 2, at: 1, kind: "tool_start", callId: "a", tool: "Bash", arg: "pnpm test"),
        ChatEvent(id: 3, at: 2, kind: "error", text: "boom"),
        ChatEvent(id: 4, at: 3, kind: "turn_end", outcome: "error"),
    ])
    #expect(group(ended).erred && group(ended).title == "Failed" && group(ended).isWorking == false)
    let answered = chatFeed([
        ChatEvent(id: 1, at: 0, kind: "user", text: "go"),
        ChatEvent(id: 2, at: 1, kind: "tool_start", callId: "a", tool: "Bash", arg: "ls"),
        ChatEvent(id: 3, at: 2, kind: "tool_end", callId: "a", tool: "Bash", status: "ok"),
        ChatEvent(id: 4, at: 3, kind: "assistant", text: "done"),
        ChatEvent(id: 5, at: 4, kind: "turn_end", outcome: "error"),
    ])
    #expect(group(answered).erred == false)
}

@Test func aTurnStoppedToSendAMessageReadsAsStoppedAndThenTheNewMessageAndItsCallsAreNotEnded() {
    let events = [
        ChatEvent(id: 1, at: 0, kind: "user", text: "first"),
        ChatEvent(id: 2, at: 1, kind: "tool_start", callId: "a", tool: "Bash", arg: "sleep 60"),
        ChatEvent(id: 3, at: 2, kind: "turn_end", outcome: "interrupted"),
        ChatEvent(id: 4, at: 3, kind: "user", text: "instead"),
        ChatEvent(id: 5, at: 4, kind: "tool_start", callId: "b", tool: "Bash", arg: "pnpm test"),
    ]
    let rows = chatFeed(events)
    #expect(texts(rows).filter { $0.hasPrefix("tools") == false } == ["user: first", "end: 0s", "stopped", "user: instead"])
    let calls = rows.compactMap { if case .tools(_, let group) = $0 { group } else { nil } }
    #expect(calls.count == 2 && calls[0].isWorking == false && calls[0].calls.map(\.status) == [.stopped])
    #expect(calls[1].isWorking && openOutcome(rows) == nil)
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
        case .code(let language, _, let code): "code \(language ?? "-") \(code.split(separator: "\n").count)"
        case .gap: "gap"
        case .table: "table"
        case .numbered: "numbered"
        case .quote: "quote"
        case .rule: "rule"
        }
    }
    #expect(blocks.map(shape) == [
        "line", "gap", "line", "gap", "bullet0", "bullet0", "bullet1", "bullet0", "gap", "line", "gap", "code tsx 7", "gap", "line", "gap", "code - 1",
    ])
    guard case .line(let first) = blocks[0] else { return }
    #expect(first.runs.contains { $0.inlinePresentationIntent == .code && String(first.characters[$0.range]) == "Page.tsx" })
    // the code is kept as written: its indentation and the lines of a block with a blank one
    guard case .code(_, _, let code) = blocks[11] else { return }
    #expect(code.hasPrefix("export function Plans") && code.contains("\n    <section className="))
}

@Test func aFenceLeftOpenByAMessageStillBeingWrittenIsABlockToTheEnd() throws {
    let blocks = markdownBlocks(try golden("streaming").streaming)
    guard case .code(let language, _, let code) = blocks.last else {
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
    let nothing = try await host.events(finished, after: 14, limit: 200)
    #expect(nothing.events.isEmpty && nothing.cursor == 14 && nothing.state == .idle)
    // the golden conversation lists what the provider offers, and the fixture host changes one and refuses a value it does not list
    #expect(optionsPill(nothing.options) == "Sonnet · High · Ask first")
    try await host.setOption(finished, option: "effort", value: "medium")
    #expect(optionsPill(try await host.events(finished, after: 14, limit: 200).options) == "Sonnet · Medium · Ask first")
    await #expect(throws: ControlError.self) { try await host.setOption(finished, option: "effort", value: "max") }
    #expect(try await host.events("5d1f7c3a-0b6e-4a52-9a1d-3c7e8b2f4a01", after: 0, limit: 200).streaming.hasPrefix("The worker calls"))
    // a listed session with no golden file has no events; one that is not listed, or not a UUID, is refused
    #expect(try await host.events("d4e5f6a7-3b2c-4d9e-8f1a-2b3c4d5e6f04", after: 0, limit: 200).events.isEmpty)
    // the Codex session is waiting: its approval is pending
    #expect(try await host.events("8a2e4b6d-1c3f-4d57-8e9a-0b1c2d3e4f02", after: 0, limit: 200).pending == ["b1"])
    await #expect(throws: ControlError.remote(Refusal(code: "session.unknown", text: "unknown session"))) { try await host.events(UUID().uuidString, after: 0, limit: 200) }
    await #expect(throws: ControlError.remote(.sessionIdInvalid)) { try await host.events("../x\",\"cmd\":\"stop", after: 0, limit: 200) }
}

@Test func theFixtureHostRecordsAnAnswerAndRefusesOneThatIsNotPendingOrNotAChoice() async throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.chatSocketPath })
    let waiting = "8a2e4b6d-1c3f-4d57-8e9a-0b1c2d3e4f02"
    await #expect(throws: ControlError.remote(Refusal(code: "session.approval.choiceUnknown", text: "That is not one of the choices"))) { try await host.answer(waiting, approval: "b1", choice: "maybe") }
    await #expect(throws: ControlError.remote(Refusal(code: "session.approval.notPending", text: "That approval is not pending: it is unknown or was already answered"))) { try await host.answer(waiting, approval: "zz", choice: "accept") }
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

@Test func theConversationModelKnowsWhatTheAgentWaitsForFromTheHostsList() async throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.chatSocketPath })
    // the fixture's session whose turn ended while a build runs, and one that waits for nothing
    let building = await ConversationModel(host: host, sessionId: "9b8c7d6e-5f4a-4b3c-8d2e-1f0a9b8c7d07")
    await building.poll()
    #expect(await building.background.map(\.name) == ["pnpm build", "pnpm test", "Review the diff"])
    let idle = await ConversationModel(host: host, sessionId: "5d1f7c3a-0b6e-4a52-9a1d-3c7e8b2f4a01")
    await idle.poll()
    #expect(await idle.background.isEmpty)
}

@Test func aPollOverTheSocketAsksTheHostForEventsAndForNoList() async throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.chatSocketPath })
    // the fixture's session that waits for a build, and an archived one
    for id in ["9b8c7d6e-5f4a-4b3c-8d2e-1f0a9b8c7d07", "d4e5f6a7-3b2c-4d9e-8f1a-2b3c4d5e6f04"] {
        let model = await ConversationModel(host: host, sessionId: id)
        await model.poll()
        await model.poll()
    }
    #expect(server.chatRequests["list"] == nil && server.chatRequests["events"] == 4)
    let archived = await ConversationModel(host: host, sessionId: "d4e5f6a7-3b2c-4d9e-8f1a-2b3c4d5e6f04")
    await archived.poll()
    #expect(await archived.archived)
    #expect(await archived.live == false)
    #expect(await archived.agent == "codex")
}

@Test func theSummaryOfEventsGivesFactsOnlyWhenTheHostSaysWhetherTheSessionRuns() throws {
    func decode(_ session: String) throws -> ChatEvents {
        try JSONDecoder().decode(ChatEvents.self, from: Data(#"{"events":[],"cursor":0,"streaming":"","session":\#(session)}"#.utf8))
    }
    let new = try decode(#"{"state":"idle","agent":"claude","archived":false,"live":true,"background":[{"id":"b","kind":"local_bash","description":"pnpm build","startedAt":5}]}"#)
    #expect(new.facts?.live == true && new.facts?.agent == "claude" && new.facts?.background.map(\.id) == ["b"])
    // a host that predates the fields says what it always did: the model reads the lists
    #expect(try decode(#"{"state":"idle","agent":"claude","archived":false}"#).facts == nil)
    #expect(try decode(#"{"state":"working"}"#).facts == nil && (try decode(#"{"state":"working"}"#)).state == .working)
}

@Test func aBackgroundTaskKnowsWhenItBeganAndTheCardsLineTakesTheTasksInTurn() throws {
    let task = try JSONDecoder().decode(BackgroundTask.self, from: Data(#"{"id":"b","kind":"local_bash","description":"pnpm build","startedAt":1792000000000}"#.utf8))
    #expect(task.startedAt == Date(timeIntervalSince1970: 1_792_000_000) && task.name == "pnpm build")
    // a host that does not say when, and a task the agent did not describe
    let bare = try JSONDecoder().decode(BackgroundTask.self, from: Data(#"{"id":"c","kind":"monitor","description":""}"#.utf8))
    #expect(bare.startedAt == nil && bare.name == "monitor")

    let tasks = [BackgroundTask(id: "a", kind: "local_bash", description: "pnpm build"), BackgroundTask(id: "b", kind: "local_bash", description: "pnpm test"), BackgroundTask(id: "c", kind: "local_agent", description: "review the diff")]
    #expect(backgroundWords([], tick: 0) == nil && backgroundCount([]) == nil && backgroundCount([tasks[0]]) == nil)
    #expect(backgroundWords([tasks[0]], tick: 7) == "Waiting on pnpm build")
    // they take their turn each tick, round and round, whatever the tick is
    #expect((0..<4).map { backgroundWords(tasks, tick: $0) } == ["Waiting on pnpm build", "Waiting on pnpm test", "Waiting on review the diff", "Waiting on pnpm build"])
    #expect(backgroundWords(tasks, tick: -1) == "Waiting on pnpm test")
    #expect(backgroundCount(tasks) == "· 3 tasks")
}

@MainActor @Test func aTaskCanBeStoppedByItselfAndAnInterruptWithNoTurnStopsThemAll() async throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.chatSocketPath })
    let session = "9b8c7d6e-5f4a-4b3c-8d2e-1f0a9b8c7d07"
    #expect(try await host.capabilities().contains(.stopTask))
    let model = ConversationModel(host: host, sessionId: session)
    await model.poll()
    #expect(model.canStopTask && model.background.count == 3)
    await model.stopTask("b2")
    await model.poll()
    #expect(model.background.map(\.id) == ["b1", "b3"] && model.refusal == nil)
    // one that has already ended is refused in the host's words
    await model.stopTask("b2")
    #expect(model.refusal != nil)
    // the line's Stop stops what is left: the host's interrupt, which with no turn running does that
    await model.stop()
    await model.poll()
    #expect(model.background.isEmpty)
}

// MARK: the model

private final class ScriptedHost: ChatHost, @unchecked Sendable {
    var events: [ChatEvent] = []
    var streaming = ""
    var failing: Error?
    var asked: [(after: Int, limit: Int)] = []
    var live = true
    /// Whether the session is in the archive, for `list(archived:)` and the summary of `events`.
    var archivedSession = false
    /// The `list` requests made, by whether they asked for the archive.
    var listed: [Bool] = []
    /// A host that predates `live` in the summary of `events` leaves it out, and the model reads the lists.
    var summaryHasLive = true
    var background: [BackgroundTask] = []
    var refusing: ControlError?
    var sent: [String] = []
    var resumed = 0
    var preparation: ChatSession.Preparation?
    var progress: String?
    var retried = 0
    var cancelled = 0
    var refusePreparation: ControlError?
    var cancelPlan: SessionPlan? = SessionPlan(agent: "claude", folder: "/x", text: "hello")
    /// What the hello of the host lists; a host that predates `stopTask` leaves it out.
    var capabilities: Set<ControlClient.Capability> = [.stopTask]
    var stopped: [String] = []
    var refusingStopTask: ControlError?
    /// The state the host reports with its events; nil leaves the model's as it was (idle).
    var state: ChatSession.State?
    /// The folder the summary of `events` says the session works from.
    var baseFolder: String?
    var interrupts = 0
    /// Set, the next `events` waits on it before it reads the page: a test holds a round in flight while another starts.
    var hold: (@Sendable () async -> Void)?
    /// Set, the next `events` answers the whole list from the start with a cursor of 0, as a reader that was behind would.
    var rewind = false
    /// Set, every `events` answers the first page from the start with a cursor of 0, whatever was asked; it gives up after 20 asks, so a
    /// reader that never stops fails a test instead of hanging it.
    var stale = false

    func agents() async throws -> [ChatAgent] { [] }
    func open(plan: SessionPlan) async throws -> String { "" }
    func retryPreparation(_ id: String) async throws {
        retried += 1
        if let refusePreparation { throw refusePreparation }
        preparation = .running
    }
    func cancelPreparation(_ id: String) async throws -> SessionPlan? {
        cancelled += 1
        if let refusePreparation { throw refusePreparation }
        return cancelPlan
    }
    func workspace(_ folder: String) async throws -> WorkspaceInfo { WorkspaceInfo(folder: folder, git: false) }
    func fetch(_ folder: String, ifStale: Bool) async throws -> WorkspaceInfo { WorkspaceInfo(folder: folder, git: false) }
    func suggestName(_ folder: String) async throws -> String { "" }
    func checkName(_ folder: String, _ name: String) async throws -> NameCheck { NameCheck(valid: true, free: true) }
    func list(archived: Bool) async throws -> [ChatSession] {
        listed.append(archived)
        guard archived == archivedSession else { return [] }
        let json = #"{"id":"s","agent":"claude","harness":"claude","folder":"/x","state":"idle","createdAt":1,"lastActiveAt":1,"archived":\#(archived),"live":\#(live && archived == false)}"#
        return [try JSONDecoder().decode(ChatSession.self, from: Data(json.utf8))]
    }
    /// What the summary of an `events` reply says of the session, when the host does: as it is, an archived session that was resumed says `live`.
    private var facts: SessionFacts? {
        summaryHasLive ? SessionFacts(agent: "claude", archived: archivedSession, live: live, background: background, baseFolder: baseFolder) : nil
    }
    func resume(_ id: String) async throws {
        resumed += 1
        if let refusing { throw refusing }
    }
    func send(_ id: String, _ text: String) async throws { sent.append(text) }
    func interrupt(_ id: String) async throws { interrupts += 1 }
    func answer(_ id: String, approval: String, choice: String, answers: [String: String]?) async throws {}
    func setOption(_ id: String, option: String, value: String) async throws {}
    func archive(_ id: String, _ archived: Bool) async throws {}
    func delete(_ id: String) async throws {}
    func capabilities() async throws -> Set<ControlClient.Capability> { capabilities }
    func stopTask(_ id: String, task: String) async throws {
        stopped.append("\(id) \(task)")
        if let refusingStopTask { throw refusingStopTask }
    }
    func githubRepos(page: Int) async throws -> GithubReposPage { throw ControlError.closed }
    func deletePreview(_ ids: [String]) async throws -> [SessionDeletePreview] { [] }
    func events(_ id: String, after: Int, limit: Int) async throws -> ChatEvents {
        asked.append((after, limit))
        if let failing { throw failing }
        if let wait = hold {
            hold = nil
            await wait()
        }
        if stale {
            if asked.count > 20 { throw ControlError.closed }
            return ChatEvents(events: Array(events.prefix(limit)), cursor: 0, streaming: streaming, state: state, preparation: preparation, facts: facts, progress: progress)
        }
        if rewind {
            rewind = false
            return ChatEvents(events: Array(events.prefix(limit)), cursor: 0, streaming: streaming, state: state, preparation: preparation, facts: facts, progress: progress)
        }
        let page = Array(events.filter { $0.id > after }.prefix(limit))
        return ChatEvents(events: page, cursor: page.last?.id ?? after, streaming: streaming, state: state, preparation: preparation, facts: facts, progress: progress)
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

// A project deleted from disk leaves its idle sessions as history: a notice says their folder is gone and a send is refused (docs/adr/0040).

@MainActor @Test func anIdleSessionWhoseFolderWasDeletedSaysSoAndRefusesASendWithoutAskingTheHost() async {
    let host = ScriptedHost()
    host.state = .idle
    host.live = false
    host.baseFolder = "/projects/gone"
    let model = ConversationModel(host: host, sessionId: "s", log: { _ in }, folderExists: { $0 != "/projects/gone" })
    await model.poll()
    #expect(model.folderGone)
    model.draft = "hello"
    await model.submit()
    #expect(model.refusal == .folderGone && model.draft == "hello")
    // nothing reached the host: not a resume, not a send
    #expect(host.sent.isEmpty && host.resumed == 0)
    #expect(folderGoneNotice.title.contains("folder was deleted"))
}

@MainActor @Test func theFolderNoticeIsOnlyForAnIdleSessionWhoseFolderIsReallyGone() async {
    func read(_ prepare: (ScriptedHost) -> Void, exists: Bool = false) async -> Bool {
        let host = ScriptedHost()
        host.baseFolder = "/projects/gone"
        prepare(host)
        let model = ConversationModel(host: host, sessionId: "s", log: { _ in }, folderExists: { _ in exists })
        await model.poll()
        return model.folderGone
    }
    #expect(await read { $0.state = .idle })
    // the folder is there, or the session works, or waits, or is being prepared (a clone has not made its folder yet), or failed preparing, or is archived, or the host does not say
    #expect(await read({ $0.state = .idle }, exists: true) == false)
    #expect(await read { $0.state = .working } == false)
    #expect(await read { $0.state = .waitingApproval } == false)
    #expect(await read { $0.state = .preparing } == false)
    #expect(await read { $0.state = .idle; $0.preparation = .failed } == false)
    #expect(await read { $0.state = .idle; $0.archivedSession = true } == false)
    #expect(await read { $0.state = .idle; $0.baseFolder = nil } == false)
    // an idle session in a folder that is there is sent to as ever
}

@MainActor @Test func aSessionWhoseFolderIsThereIsSentToAsEver() async {
    let host = ScriptedHost()
    host.state = .idle
    host.baseFolder = "/projects/app"
    let model = ConversationModel(host: host, sessionId: "s", log: { _ in }, folderExists: { _ in true })
    await model.poll()
    model.draft = "hello"
    await model.submit()
    #expect(model.folderGone == false && model.refusal == nil && host.sent == ["hello"])
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
    host.failing = ControlError.remote(.words("unknown session"))
    await model.poll()
    #expect(model.failure == "unknown session" && logged.count == 2)
}

@MainActor @Test func runWaitsAsLongAsWhoIsLookingAndWhatTheAgentDoesCallFor() async {
    func record(viewing: Viewing, host: ScriptedHost, rounds: Int, between: @MainActor @escaping (Int) -> Void = { _ in }) async -> [Double] {
        var seconds: [Double] = []
        let model = ConversationModel(
            host: host, sessionId: "s", sleep: { duration in
                seconds.append(Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18)
                if seconds.count == rounds { throw CancellationError() }
                between(seconds.count)
            }, log: { _ in }, viewing: viewing
        )
        await model.run()
        return seconds
    }
    let pace = PollPace()
    func viewing(_ appActive: Bool, _ windowShown: Bool, asleep: Bool = false) -> Viewing {
        let viewing = Viewing()
        viewing.update(appActive: appActive, windowShown: windowShown, asleep: asleep, lowPower: false, pace: pace)
        return viewing
    }

    // idle: every 2 s in front, every 5 s with the window on screen behind another app
    #expect(await record(viewing: viewing(true, true), host: ScriptedHost(), rounds: 2) == [2, 2])
    #expect(await record(viewing: viewing(false, true), host: ScriptedHost(), rounds: 2) == [5, 5])
    // hidden or asleep: not asking, which is a wait of the ceiling and no more
    #expect(await record(viewing: viewing(true, false), host: ScriptedHost(), rounds: 2) == [conversationPause, conversationPause])
    #expect(await record(viewing: viewing(true, true, asleep: true), host: ScriptedHost(), rounds: 1) == [conversationPause])
    // a turn that runs: every 250 ms
    let working = ScriptedHost()
    working.state = .working
    #expect(await record(viewing: viewing(true, true), host: working, rounds: 3) == [0.25, 0.25, 0.25])
    #expect(await record(viewing: viewing(false, true), host: working, rounds: 1) == [0.25])
    // the message in progress is a turn that runs too, and so is a preparation under way
    let streaming = ScriptedHost()
    streaming.streaming = "writing"
    #expect(await record(viewing: viewing(true, true), host: streaming, rounds: 1) == [0.25])
    let preparing = ScriptedHost()
    preparing.preparation = .running
    #expect(await record(viewing: viewing(true, true), host: preparing, rounds: 1) == [0.25])
}

@MainActor @Test func aHostThatDoesNotAnswerIsAskedLessAndLessOftenAndTheNormalPaceComesBackWithTheFirstAnswer() async {
    let host = ScriptedHost()
    host.failing = ControlError.closed
    let viewing = Viewing()
    viewing.update(appActive: true, windowShown: true, asleep: false, lowPower: false, pace: PollPace())
    var seconds: [Double] = []
    let model = ConversationModel(
        host: host, sessionId: "s", sleep: { duration in
            seconds.append(Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18)
            if seconds.count == 3 { host.failing = nil }
            if seconds.count == 5 { throw CancellationError() }
        }, log: { _ in }, viewing: viewing
    )
    await model.run()
    #expect(seconds == [0.5, 1, 2, 2, 2])
}

@MainActor @Test func theLongestWaitIsUnderAMinuteSoTheHostKeepsHearingFromTheApp() {
    #expect(conversationPause < 60)
    for failures in 1...40 {
        for state in [ViewingState.focused, .visible] {
            #expect((conversationWait(state: state, turnRunning: true, failures: failures) ?? 0) <= 30)
        }
    }
    for state in [ViewingState.hidden, .asleep] { #expect(conversationWait(state: state, turnRunning: true, failures: 0) == nil) }
    // a person who looks does not wait long for a host that came back: 0.5, 1, 2, 4 and then 5
    #expect((1...7).map { conversationWait(state: .focused, turnRunning: false, failures: $0) } == [0.5, 1, 2, 4, 5, 5, 5])
}

@MainActor @Test func cancellingRunEndsItAtOnceEvenInTheLongWaitOfAHiddenWindow() async {
    let host = ScriptedHost()
    // not told it is on screen, it is hidden: the wait is the pause of 30 seconds, in the model's own nap
    let model = ConversationModel(host: host, sessionId: "s", log: { _ in }, viewing: Viewing())
    let running = Task { await model.run() }
    while host.asked.isEmpty { await Task.yield() }
    try? await Task.sleep(for: .milliseconds(50))
    let started = ContinuousClock.now
    running.cancel()
    await running.value
    // the pause it would otherwise sit through is 30 seconds; a suite that starts thousands of tests at once can stall the pool for a good part of that
    #expect(ContinuousClock.now - started < .seconds(25))
}

@MainActor @Test func aSendCutsTheWaitOfAnIdleSessionShortSoTheTurnIsReadAtOnce() async {
    let host = ScriptedHost()
    let model = ConversationModel(host: host, sessionId: "s", log: { _ in }, viewing: Viewing())
    #expect(model.nap.wakes == 0)
    model.draft = "hello"
    await model.submit()
    #expect(model.nap.wakes == 1 && host.sent == ["hello"])
}

@MainActor @Test func aChangeOfWhoIsLookingCutsTheWaitShortOnlyWhileTheModelRuns() async {
    let host = ScriptedHost()
    let viewing = Viewing()
    let pace = PollPace()
    let model = ConversationModel(host: host, sessionId: "s", sleep: { _ in try await Task.sleep(for: .seconds(3600)) }, log: { _ in }, viewing: viewing)
    // not running: nobody watches, so nobody wakes it
    viewing.update(appActive: true, windowShown: true, asleep: false, lowPower: false, pace: pace)
    #expect(model.nap.wakes == 0)
    let running = Task { await model.run() }
    while host.asked.isEmpty { await Task.yield() }
    viewing.update(appActive: true, windowShown: false, asleep: false, lowPower: false, pace: pace)
    // the wake comes from a task of the main actor that the change started
    for _ in 0..<1000 where model.nap.wakes == 0 { try? await Task.sleep(for: .milliseconds(10)) }
    #expect(model.nap.wakes == 1)
    // and it is armed again for the next change
    viewing.update(appActive: false, windowShown: true, asleep: false, lowPower: false, pace: pace)
    for _ in 0..<1000 where model.nap.wakes == 1 { try? await Task.sleep(for: .milliseconds(10)) }
    #expect(model.nap.wakes == 2)
    running.cancel()
    await running.value
    // and it stops watching with the task: a change after that wakes no one
    let after = model.nap.wakes
    viewing.update(appActive: true, windowShown: true, asleep: false, lowPower: false, pace: pace)
    try? await Task.sleep(for: .milliseconds(100))
    #expect(model.nap.wakes == after)
}

@MainActor @Test func aHostThatSaysWhetherTheSessionRunsInItsEventsIsAskedForNoList() async {
    let host = ScriptedHost()
    host.background = [BackgroundTask(id: "b", kind: "local_bash", description: "pnpm build")]
    host.events = [ChatEvent(id: 1, at: 1, kind: "user", text: "hi")]
    let model = ConversationModel(host: host, sessionId: "s", log: { _ in })
    await model.poll()
    await model.poll()
    #expect(host.listed.isEmpty)
    #expect(model.live && model.archived == false && model.agent == "claude" && model.background.map(\.id) == ["b"])
    // what the summary says now is what the model shows now
    host.live = false
    host.background = []
    await model.poll()
    #expect(host.listed.isEmpty && model.live == false && model.background.isEmpty)
}

@MainActor @Test func anArchivedSessionIsKnownFromItsEventsAndAsksForNoList() async {
    let host = ScriptedHost()
    host.archivedSession = true
    host.events = [ChatEvent(id: 1, at: 1, kind: "user", text: "hi")]
    let model = ConversationModel(host: host, sessionId: "s", log: { _ in })
    await model.poll()
    #expect(host.listed.isEmpty && model.archived && model.live == false && model.agent == "claude" && model.background.isEmpty)
}

@MainActor @Test func anArchivedSessionTheHostSaysIsLiveStaysArchivedWithNoBackgroundAndNotAsleep() async {
    // close, archive, then resume: the host's summary says archived and live, with what the agent waits for
    let host = ScriptedHost()
    host.archivedSession = true
    host.live = true
    host.background = [BackgroundTask(id: "b", kind: "local_bash", description: "pnpm build")]
    host.events = [ChatEvent(id: 1, at: 1, kind: "user", text: "hi")]
    let model = ConversationModel(host: host, sessionId: "s", log: { _ in })
    await model.poll()
    #expect(host.listed.isEmpty && model.archived && model.live == false && model.background.isEmpty && model.asleep == false)
}

@MainActor @Test func aSessionBeingPreparedIsNotShownAsClosedWhenTheSummaryOfItsEventsSaysSo() async {
    let host = ScriptedHost()
    host.live = false
    host.events = [ChatEvent(id: 1, at: 1, kind: "user", text: "hi")]
    let closed = ConversationModel(host: host, sessionId: "s", log: { _ in })
    await closed.poll()
    #expect(closed.asleep)
    host.state = .preparing
    let preparing = ConversationModel(host: host, sessionId: "s", log: { _ in })
    await preparing.poll()
    #expect(preparing.asleep == false && host.listed.isEmpty)
}

@MainActor @Test func aHostWhoseEventsLeaveOutLiveIsStillReadFromItsLists() async {
    let host = ScriptedHost()
    host.summaryHasLive = false
    host.events = [ChatEvent(id: 1, at: 1, kind: "user", text: "hi")]
    let model = ConversationModel(host: host, sessionId: "s", log: { _ in })
    await model.poll()
    #expect(host.listed == [false] && model.live && model.agent == "claude")
    host.archivedSession = true
    await model.poll()
    #expect(host.listed == [false, false, true] && model.archived && model.live == false)
}

@MainActor @Test func aSessionThatIsNotLiveIsClosedAndASendResumesItAndContinueSendsContinue() async throws {
    let host = ScriptedHost()
    host.live = false
    host.events = try golden("stopped").events
    let model = ConversationModel(host: host, sessionId: "s", log: { _ in })
    await model.poll()
    #expect(model.live == false && model.agent == "claude")
    await model.continueTurn()
    #expect(host.resumed == 1 && host.sent == ["Continue"] && model.refusal == nil)
    host.live = true
    await model.poll()
    #expect(model.live)
}

@MainActor @Test func aRefusedSendKeepsTheMessageForTryAgainAndTryAgainSendsTheLastMessageWhenTheTurnFailed() async throws {
    let host = ScriptedHost()
    host.live = false
    host.refusing = .remote(.words("Claude is not logged in; run \"claude\" once to log in"))
    host.events = [ChatEvent(id: 1, at: 1, kind: "user", text: "hello")]
    let model = ConversationModel(host: host, sessionId: "s", log: { _ in })
    await model.poll()
    model.draft = "hello again"
    await model.submit()
    #expect(model.refusal?.text == "Claude is not logged in; run \"claude\" once to log in" && model.refusedText == "hello again" && model.draft == "hello again")
    // signed in now: Try again sends the refused message, not the box's
    host.refusing = nil
    await model.retry()
    #expect(host.sent == ["hello again"] && model.refusal == nil && model.refusedText == nil)
    // a failed turn has no refused message: Try again sends the person's last one
    host.events += [ChatEvent(id: 2, at: 2, kind: "error", text: "boom"), ChatEvent(id: 3, at: 3, kind: "turn_end", outcome: "error")]
    await model.poll()
    await model.retry()
    #expect(host.sent == ["hello again", "hello"])
}

// MARK: the steps of a preparation

private func step(_ id: Int, _ step: String, _ status: String, _ detail: String? = nil) -> ChatEvent {
    ChatEvent(id: id, at: id, kind: "step", status: status, step: step, detail: detail)
}

@Test func theStepsMakeOneRowEachInTheOrderTheyStartedWithTheLastStatusAndALineInWords() {
    let rows = preparationSteps(
        [step(1, "clone", "running"), step(2, "clone", "done"), step(3, "agent", "running"), say(4), step(5, "agent", "done"), step(6, "message", "running")],
        preparation: .running
    )
    #expect(rows.map(\.step) == ["clone", "agent", "message"] && rows.map(\.status) == [.done, .done, .running])
    #expect(rows.map(\.line) == ["Cloned the repository", "Started the agent", "Waiting for the agent to answer…"])
    #expect(rows.allSatisfy { $0.reason == nil && $0.progress == nil })
}

@Test func aFailedStepShowsItsReasonAndOnlyTheRunningOneTakesTheProgress() {
    let failed = preparationSteps([step(1, "clone", "done"), step(2, "worktree", "failed", "A branch called carrier/x already exists")], preparation: .failed, progress: "Receiving objects: 45%")
    #expect(failed.map(\.status) == [.done, .failed] && failed[1].reason == "A branch called carrier/x already exists" && failed[1].line == "Could not make the worktree")
    #expect(failed.allSatisfy { $0.progress == nil })
    let cloning = preparationSteps([step(1, "clone", "running")], preparation: .running, progress: "Receiving objects: 45%")
    #expect(cloning.first?.progress == "Receiving objects: 45%" && cloning.first?.line == "Cloning the repository…")
}

@Test func aStepThatRunsAgainAfterFailingTakesItsPlaceInTheSameRowWithoutTheOldReason() {
    let rows = preparationSteps([step(1, "agent", "failed", "claude is not logged in"), step(2, "agent", "running")], preparation: .running)
    #expect(rows.count == 1 && rows[0].status == .running && rows[0].reason == nil)
}

private func actionStep(_ id: Int, _ name: String, _ when: String, _ status: String, _ detail: String? = nil) -> ChatEvent {
    ChatEvent(id: id, at: id, kind: "step", status: status, step: "action", detail: detail, action: name, when: when)
}

@Test func eachActionIsARowOfItsOwnNamedByItsTitleWithTheTerminalIconAndTheOtherStepsHaveNone() {
    let rows = preparationSteps(
        [step(1, "clone", "done"), actionStep(2, "Install", "afterClone", "running"), actionStep(3, "Install", "afterClone", "done"), step(4, "worktree", "done"),
         actionStep(5, "Install", "newWorktree", "running"), actionStep(6, "Copy env", "newWorktree", "failed", "Copy env failed with exit code 1: no such file")],
        preparation: .failed, progress: "resolving"
    )
    #expect(rows.map(\.line) == ["Cloned the repository", "Ran Install", "Made the worktree", "Running Install…", "Copy env failed"])
    #expect(rows.map(\.icon) == [nil, .terminal, nil, .terminal, .terminal])
    #expect(Set(rows.map(\.id)).count == 5)
    #expect(rows[3].progress == "resolving" && rows[4].reason == "Copy env failed with exit code 1: no such file")
    // the outline keeps each row's icon and its own id
    #expect(preparationOutline(rows).prefix(5).map(\.icon) == [nil, .terminal, nil, .terminal, .terminal])
    #expect(Set(preparationOutline(rows).map(\.id)).count == preparationOutline(rows).count)
}

@Test func aRestoreListsOnlyTheStepsFromItsWorktreeMarkerThatEndTheLogAndNotTheStepsOfEarlierTurns() {
    let log = [
        step(1, "worktree", "running"), step(2, "worktree", "done"), actionStep(3, "Install", "newWorktree", "done"), step(4, "agent", "done"), step(5, "message", "done"), say(6),
        step(7, "worktree", "running"), step(8, "worktree", "done"), actionStep(9, "Install", "newWorktree", "done"), ChatEvent(id: 10, at: 10, kind: "notice", text: "x"),
        actionStep(11, "Copy env", "newWorktree", "running"),
    ]
    let restore = preparationSteps(log, preparation: .running, progress: "copying", restoring: true)
    #expect(restore.map(\.line) == ["Made the worktree", "Ran Install", "Running Copy env…"] && restore.map(\.progress) == [nil, nil, "copying"])
    // the same log read as a preparation lists every step, as before
    #expect(preparationSteps(log, preparation: .running).map(\.step) == ["worktree", "action", "agent", "message", "action"])
    // a restore whose first action has not started lists the worktree row, and the steps of the turns before it are not its own
    #expect(preparationSteps(Array(log.prefix(7)), preparation: .running, restoring: true).map(\.line) == ["Making the worktree…"])
    #expect(preparationSteps(Array(log.prefix(8)), preparation: .running, restoring: true).map(\.line) == ["Made the worktree"])
    // a restore whose worktree could not come back says why
    let failed = preparationSteps(Array(log.prefix(6)) + [step(7, "worktree", "running"), step(8, "worktree", "failed", "gone")], preparation: .running, restoring: true)
    #expect(failed.map(\.status) == [.failed] && failed.first?.reason == "gone")
}

@Test func restoresOneAfterTheOtherListOnlyTheLastAndOneThatGoesOnKeepsTheFirstTrysFinishedActions() {
    // two restores with no other step between them: only the last one's rows
    let back = [
        step(1, "worktree", "running"), step(2, "worktree", "done"), actionStep(3, "Install", "newWorktree", "done"), actionStep(4, "Old only", "newWorktree", "done"),
        step(5, "worktree", "running"), step(6, "worktree", "done"), actionStep(7, "Install", "newWorktree", "running"),
    ]
    #expect(preparationSteps(back, preparation: .running, restoring: true).map(\.line) == ["Made the worktree", "Running Install…"])
    // a restore that stopped and goes on has the one marker of its first try, and the actions it finished still show
    let resumed = [step(1, "message", "done"), step(2, "worktree", "running"), step(3, "worktree", "done"), actionStep(4, "Install", "newWorktree", "done"), actionStep(5, "Copy env", "newWorktree", "failed"), actionStep(6, "Copy env", "newWorktree", "running")]
    #expect(preparationSteps(resumed, preparation: .running, restoring: true).map(\.line) == ["Made the worktree", "Ran Install", "Running Copy env…"])
    // a log from before the marker: the trailing actions, as they were
    let old = [step(1, "message", "done"), actionStep(2, "Install", "newWorktree", "done"), actionStep(3, "Copy env", "newWorktree", "running")]
    #expect(preparationSteps(old, preparation: .running, restoring: true).map(\.line) == ["Ran Install", "Running Copy env…"])
}

@MainActor @Test func theModelScopesTheStepsToTheRestoreWhenTheSessionIsNotPreparingButItsPreparationRuns() async {
    let host = ScriptedHost()
    host.preparation = .running
    host.events = [step(1, "agent", "done"), step(2, "message", "done"), say(3), step(4, "worktree", "running")]
    let model = ConversationModel(host: host, sessionId: "s", log: { _ in })
    await model.poll()
    #expect(model.steps.map(\.line) == ["Making the worktree…"])
    host.events += [step(5, "worktree", "done"), actionStep(6, "Install", "newWorktree", "running")]
    await model.poll()
    #expect(model.steps.map(\.line) == ["Made the worktree", "Running Install…"])
}

@Test func theListEndsWhenTheSessionIsNotBeingPreparedAnyMoreOrTheHostSaysNothing() {
    let events = [step(1, "agent", "done"), step(2, "message", "done")]
    #expect(preparationSteps(events, preparation: nil).isEmpty)
    #expect(preparationSteps([], preparation: .running).isEmpty)
    // a step or a status this app does not know does not break the list
    #expect(preparationSteps([step(1, "later", "running"), step(2, "agent", "paused")], preparation: .running).map(\.line) == ["Working on later…"])
}

@MainActor @Test func theModelKeepsTheStepsWhileTheHostPreparesAndDropsThemWhenTheAgentAnswers() async {
    let host = ScriptedHost()
    let model = ConversationModel(host: host, sessionId: "s", log: { _ in })
    host.preparation = .running
    host.state = .preparing
    host.progress = "Receiving objects: 10%"
    host.events = [step(1, "clone", "running")]
    await model.poll()
    #expect(model.steps.map(\.status) == [.running] && model.steps.first?.progress == "Receiving objects: 10%")
    host.progress = "Receiving objects: 80%"
    await model.poll()
    #expect(model.steps.first?.progress == "Receiving objects: 80%")
    // the agent answered: the host ends the preparation and the list goes
    host.preparation = nil
    host.progress = nil
    host.events += [step(2, "clone", "done"), step(3, "message", "done"), say(4)]
    await model.poll()
    #expect(model.steps.isEmpty && model.rows.count == 1)
}

@MainActor @Test func theFirstMessageShowsUntilTheHostRecordsItSoAFailedStepKeepsTheText() async {
    let host = ScriptedHost()
    let model = ConversationModel(host: host, sessionId: "s", log: { _ in })
    model.show(firstMessage: "hello")
    #expect(model.rows == [.user(id: "first-message", text: "hello")])
    host.preparation = .failed
    host.events = [step(1, "agent", "failed", "claude is not logged in")]
    await model.poll()
    #expect(model.rows == [.user(id: "first-message", text: "hello")] && model.steps.map(\.reason) == ["claude is not logged in"])
    host.events.append(ChatEvent(id: 2, at: 2, kind: "user", text: "hello"))
    await model.poll()
    #expect(model.rows == [.user(id: "e2", text: "hello")])
}

@MainActor @Test func tryAgainAsksTheHostAndTheNextPollShowsThePreparationRunningAgain() async {
    let host = ScriptedHost()
    host.preparation = .failed
    host.events = [step(1, "agent", "failed", "claude is not logged in")]
    let model = ConversationModel(host: host, sessionId: "s", log: { _ in })
    await model.poll()
    #expect(model.preparation == .failed && model.steps.map(\.status) == [.failed])
    host.events.append(step(2, "agent", "running"))
    host.state = .preparing // as the host sets it when it retries
    await model.retryPreparation()
    #expect(host.retried == 1 && model.preparation == .running && model.steps.map(\.status) == [.running] && model.preparationRefusal == nil)
}

@MainActor @Test func aRefusedTryAgainOrCancelIsSaidInWordsAndChangesNothing() async {
    let host = ScriptedHost()
    host.preparation = .running
    host.refusePreparation = .remote(.words("This session is not in a failed preparation, so there is nothing to try again"))
    let model = ConversationModel(host: host, sessionId: "s", log: { _ in })
    await model.poll()
    await model.retryPreparation()
    #expect(model.preparationRefusal == "This session is not in a failed preparation, so there is nothing to try again" && model.preparation == .running)
    host.refusePreparation = .remote(.words("This session is not being prepared, so there is nothing to cancel"))
    #expect(await model.cancelPreparation() == nil)
    #expect(model.preparationRefusal == "This session is not being prepared, so there is nothing to cancel")
}

@MainActor @Test func cancelOfARestoreHasNoPlanAndIsNotARefusal() async {
    let host = ScriptedHost()
    host.preparation = .running
    host.cancelPlan = nil
    let model = ConversationModel(host: host, sessionId: "s", log: { _ in })
    #expect(await model.cancelPreparation() == nil)
    #expect(host.cancelled == 1 && model.preparationRefusal == nil)
}

@MainActor @Test func cancelGivesBackThePlanTheHostStoredWithTheText() async {
    let host = ScriptedHost()
    host.preparation = .running
    host.cancelPlan = SessionPlan(agent: "claude", folder: "/w/api", branch: "feat/x", text: "build it")
    let model = ConversationModel(host: host, sessionId: "s", log: { _ in })
    let plan = await model.cancelPreparation()
    #expect(host.cancelled == 1 && plan == host.cancelPlan && model.preparationRefusal == nil)
}

// MARK: following new output

/// A model that has read what the host has and is told whether it follows and whether the view is at the end, then reads one more message.
@MainActor private func scrolls(follows: Bool, atEnd: Bool) async -> Int {
    let host = ScriptedHost()
    host.events = [say(1)]
    let model = ConversationModel(host: host, sessionId: "s", log: { _ in })
    await model.poll()
    (model.followsOutput, model.atEnd) = (follows, atEnd)
    let before = model.scrolls
    host.events.append(say(2))
    await model.poll()
    return model.scrolls - before
}

@MainActor @Test func withFollowOnNewOutputScrollsToTheEndWhileThePersonIsAtTheEnd() async {
    #expect(await scrolls(follows: true, atEnd: true) == 1)
}

@MainActor @Test func withFollowOnNewOutputLeavesAPersonWhoScrolledUpWhereTheyAre() async {
    #expect(await scrolls(follows: true, atEnd: false) == 0)
}

@MainActor @Test func withFollowOffTheViewNeverScrollsByItself() async {
    #expect(await scrolls(follows: false, atEnd: true) == 0)
    #expect(await scrolls(follows: false, atEnd: false) == 0)
}

@MainActor @Test func aPollThatBringsNothingNewDoesNotScroll() async {
    let host = ScriptedHost()
    host.events = [say(1)]
    let model = ConversationModel(host: host, sessionId: "s", log: { _ in })
    await model.poll()
    let before = model.scrolls
    await model.poll()
    #expect(model.scrolls == before)
}

@MainActor @Test func theTextBeingWrittenCountsAsNewOutput() async {
    let host = ScriptedHost()
    host.events = [say(1)]
    let model = ConversationModel(host: host, sessionId: "s", log: { _ in })
    await model.poll()
    let before = model.scrolls
    host.streaming = "Hel"
    await model.poll()
    #expect(model.scrolls == before + 1)
}

@MainActor @Test func aMessageKnowsWhenItWasWrittenAndTheOneInProgressDoesNot() async {
    let host = ScriptedHost()
    host.events = [ChatEvent(id: 1, at: 1_000, kind: "user", text: "hi"), ChatEvent(id: 2, at: 2_000, kind: "assistant", text: "hello"), ChatEvent(id: 3, at: 3_000, kind: "turn_end")]
    host.streaming = "more"
    let model = ConversationModel(host: host, sessionId: "s", log: { _ in })
    await model.poll()
    #expect(model.times == ["e1": 1_000, "e2": 2_000])
    #expect(model.times["streaming"] == nil)
}

// MARK: what the tools show

private func toolsFeed() -> [FeedRow] {
    func event(_ id: Int, _ kind: String, _ call: String, _ tool: String, status: String? = nil) -> ChatEvent {
        ChatEvent(id: id, at: id, kind: kind, callId: call, tool: tool, arg: "x", output: status == nil ? nil : ["out"], status: status)
    }
    return chatFeed([
        ChatEvent(id: 1, at: 1, kind: "user", text: "go"),
        event(2, "tool_start", "a", "Read"), event(3, "tool_end", "a", "Read", status: "ok"),
        event(4, "tool_start", "b", "Bash"), event(5, "tool_end", "b", "Bash", status: "err"),
        ChatEvent(id: 6, at: 6, kind: "assistant", text: "done"),
        event(7, "tool_start", "c", "Read"), event(8, "tool_end", "c", "Read", status: "ok"),
    ])
}

private func runs(_ rows: [FeedRow]) -> [ToolGroup] { rows.compactMap { if case .tools(_, let group) = $0 { group } else { nil } } }

// MARK: the agent's reasoning

@Test func aReasoningEventIsAThoughtOfItsRunInOrderAndAnUnknownKindFromANewerHostIsNotDrawn() throws {
    let json = """
    {"events":[
      {"id":1,"at":1,"kind":"user","text":"go"},
      {"id":2,"at":2,"kind":"reasoning","text":"Look at the file first."},
      {"id":3,"at":3,"kind":"tool_start","callId":"a","tool":"Read","arg":"x"},
      {"id":4,"at":4,"kind":"tool_end","callId":"a","tool":"Read","status":"ok","output":["out"]},
      {"id":5,"at":5,"kind":"hologram","text":"from a newer host"},
      {"id":6,"at":6,"kind":"reasoning","text":"Now answer."},
      {"id":7,"at":7,"kind":"assistant","text":"done"},
      {"id":8,"at":8,"kind":"turn_end","outcome":"ok"}
    ],"cursor":8,"streaming":""}
    """
    let reply = try JSONDecoder().decode(ChatEvents.self, from: Data(json.utf8))
    #expect(reply.events[1].kind == "reasoning" && reply.events[1].text == "Look at the file first.")
    let rows = chatFeed(reply.events)
    #expect(texts(rows) == ["user: go", "tools: Explored | 2 thoughts · 1 file read", "agent: done", "end: 0s"])
    // the steps are in the order the agent took them, and the group is named by the first thought that started it
    let group = try #require(runs(rows).first)
    #expect(group.steps.map { if case .thought(let t) = $0 { "thought: \(t.text)" } else { "call: \($0.id)" } } == ["thought: Look at the file first.", "call: a", "thought: Now answer."])
    #expect(rows[1].id == "e2")
}

@Test func thoughtsWithNoCallAfterThemAreARunOfTheirOwnAboveTheMessageOrTheEndOfTheTurn() {
    let think = ChatEvent(id: 2, at: 2, kind: "reasoning", text: "Hm.")
    let user = ChatEvent(id: 1, at: 1, kind: "user", text: "go")
    // the message is still streaming: the thought sits above it
    #expect(texts(chatFeed([user, think], streaming: "Hel")) == ["user: go", "tools: Thought | 1 thought", "agent…: Hel"])
    // nothing written yet: it is the last thing
    #expect(texts(chatFeed([user, think])) == ["user: go", "tools: Thought | 1 thought"])
    // the message came: the thought is above it, not under it
    #expect(texts(chatFeed([user, think, ChatEvent(id: 3, at: 3, kind: "assistant", text: "done")])) == ["user: go", "tools: Thought | 1 thought", "agent: done"])
    // the turn failed with no message: it stays inside its turn
    let failed = [user, think, ChatEvent(id: 3, at: 3, kind: "error", text: "boom"), ChatEvent(id: 4, at: 4, kind: "user", text: "again")]
    #expect(texts(chatFeed(failed)) == ["user: go", "tools: Thought | 1 thought", "error: boom", "user: again"])
    // an empty thinking block draws nothing
    #expect(texts(chatFeed([user, ChatEvent(id: 2, at: 2, kind: "reasoning", text: "")])) == ["user: go"])
    // so does one of only blank lines, and a block with blank lines around it is shown without them
    #expect(texts(chatFeed([user, ChatEvent(id: 2, at: 2, kind: "reasoning", text: " \n\n ")])) == ["user: go"])
    let padded = chatFeed([user, ChatEvent(id: 2, at: 2, kind: "reasoning", text: "\n\n  Hm.\n ")])
    let step = runs(padded).first?.steps.first
    #expect(step.map { if case .thought(let t) = $0 { t.text } else { "" } } == "Hm.")
}

@Test func aThoughtThatCameFirstGivesItsRunItsIdAndASoloThoughtCountsItsTimeFromTheStartOfTheTurn() throws {
    let user = ChatEvent(id: 1, at: 1000, kind: "user", text: "go")
    let think = ChatEvent(id: 2, at: 4000, kind: "reasoning", text: "Hm.")
    let alone = try #require(runs(chatFeed([user, think])).first)
    #expect(alone.durationMs == 3000 && alone.startedAt == 1000 && alone.isWorking == false)
    // with a call the run counts from its first step
    let withCall = chatFeed([user, think] + call(2, "Bash", "ls", at: 4100, took: 400))
    let group = try #require(runs(withCall).first)
    #expect(group.startedAt == 4000 && group.durationMs == 500)
    #expect(withCall[1].id == "e2" && group.title == "Worked")
}

@Test func theShowReasoningSwitchTakesTheThoughtsOutAndTheHiddenToolsTakeTheCallsOutAndARunWithNothingLeftGoes() {
    let rows = chatFeed([
        ChatEvent(id: 1, at: 1, kind: "user", text: "go"), ChatEvent(id: 2, at: 2, kind: "reasoning", text: "Hm."),
        ChatEvent(id: 3, at: 3, kind: "tool_start", callId: "a", tool: "Bash", arg: "ls"), ChatEvent(id: 4, at: 4, kind: "tool_end", callId: "a", tool: "Bash", status: "ok"),
        ChatEvent(id: 5, at: 5, kind: "assistant", text: "done"),
    ])
    #expect(texts(visibleFeed(rows, mode: .collapsed)) == ["user: go", "tools: Worked | 1 thought · 1 command", "agent: done"])
    #expect(texts(visibleFeed(rows, mode: .collapsed, showsReasoning: false)) == ["user: go", "tools: Worked | 1 command", "agent: done"])
    #expect(texts(visibleFeed(rows, mode: .hidden)) == ["user: go", "tools: Thought | 1 thought", "agent: done"])
    #expect(texts(visibleFeed(rows, mode: .hidden, showsReasoning: false)) == ["user: go", "agent: done"])
}

@Test func theClosingLineOfATurnWithReasoningFoldsIntoItsMessage() {
    let rows = chatFeed([
        ChatEvent(id: 1, at: 0, kind: "user", text: "go"), ChatEvent(id: 2, at: 1, kind: "reasoning", text: "Hm."),
        ChatEvent(id: 3, at: 2, kind: "assistant", text: "done"), ChatEvent(id: 4, at: 9000, kind: "turn_end", outcome: "ok", model: "claude-sonnet-5-5"),
    ])
    let folded = foldingClosingLines(rows)
    #expect(folded.rows.map(\.id) == ["e1", "e2", "e3"])
    #expect(folded.lines["e3"]?.text == "sonnet 5.5 · 9s")
}

@Test func theRunTheAgentWorksInIsTheLastOneUntilAMessageComesAfterIt() {
    let user = ChatEvent(id: 1, at: 1, kind: "user", text: "go")
    let think = ChatEvent(id: 2, at: 2, kind: "reasoning", text: "Hm.")
    #expect(workInProgress(in: chatFeed([user])) == nil)
    #expect(workInProgress(in: chatFeed([user, think])) == "e2")
    #expect(workInProgress(in: chatFeed([user, think] + call(2, "Bash", "ls"))) == "e2")
    // the answer began, or the turn ended: the work is over
    #expect(workInProgress(in: chatFeed([user, think], streaming: "Hel")) == nil)
    #expect(workInProgress(in: chatFeed([user, think, ChatEvent(id: 9, at: 9, kind: "turn_end", outcome: "ok")])) == nil)
    // an answered approval is a line between, and the run is still the one
    let ask = ChatEvent(id: 3, at: 3, kind: "approval", tool: "Bash", arg: "ls", approvalId: "p", choices: [])
    let answered = chatFeed([user, think, ask, ChatEvent(id: 4, at: 4, kind: "approval_answered", approvalId: "p", choiceId: "y")])
    #expect(workInProgress(in: answered) == "e2")
}

// MARK: /clear

private func person(_ id: Int, _ text: String) -> ChatEvent { ChatEvent(id: id, at: id * 1000, kind: "user", text: text) }
private func turnEnd(_ id: Int, _ usage: [String: Double]?, outcome: String = "ok") -> ChatEvent { ChatEvent(id: id, at: id * 1000, kind: "turn_end", outcome: outcome, model: "claude-sonnet-5-5", usage: usage) }

@Test func aClearTheAgentAnsweredWithNothingIsADividerThatSaysWhatItFreedInPlaceOfTheEmptyTurnLine() {
    let events = [
        person(1, "hi"), say(2), turnEnd(3, ["context_tokens": 38_800, "output_tokens": 27]),
        person(4, "/clear"), turnEnd(5, ["input_tokens": 0, "output_tokens": 0]),
        person(6, "and now?"), say(7), turnEnd(8, ["context_tokens": 1_900, "output_tokens": 22]),
    ]
    let rows = texts(chatFeed(events))
    #expect(rows == ["user: hi", "agent: m2", "end: sonnet 5.5 · 2s · 38.8k context · 27 out", "user: /clear", "cleared: 38.8k tokens freed", "user: and now?", "agent: m7", "end: sonnet 5.5 · 2s · 1.9k context · 22 out"])
}

@Test func theContextAfterAClearIsNoneUntilAnotherTurnTellsIt() {
    let after = chatFeed([person(1, "hi"), turnEnd(2, ["context_tokens": 38_800]), person(3, "/clear"), turnEnd(4, nil)])
    #expect(contextUse(after) == nil)
    #expect(contextUse(chatFeed([person(1, "hi"), turnEnd(2, ["context_tokens": 38_800])]))?.tokens == 38_800)
    // a second clear frees nothing and says so by saying nothing of it
    let twice = texts(chatFeed([person(1, "a"), turnEnd(2, ["context_tokens": 5_000]), person(3, "/clear"), turnEnd(4, nil), person(5, "/clear"), turnEnd(6, nil)]))
    #expect(twice.filter { $0.hasPrefix("cleared") } == ["cleared: 5.0k tokens freed", "cleared: "])
}

@Test func onlyTheWholeClearCommandAnsweredWithNothingMakesTheDivider() {
    #expect(isClearCommand(" /clear\n") && isClearCommand("/clear now") == false && isClearCommand("please /clear") == false)
    // an answer, a failed turn or a stopped one keep their lines
    #expect(texts(chatFeed([person(1, "/clear"), say(2), turnEnd(3, ["output_tokens": 4])])).contains { $0.hasPrefix("cleared") } == false)
    #expect(texts(chatFeed([person(1, "/clear"), turnEnd(2, nil, outcome: "error")])).contains { $0.hasPrefix("cleared") } == false)
    #expect(texts(chatFeed([person(1, "/clear"), turnEnd(2, nil, outcome: "interrupted")])).contains { $0.hasPrefix("cleared") } == false)
    #expect(clearedFreedText(nil) == nil && clearedFreedText(0) == nil)
    #expect(clearedDetail(agent: "Lu").hasPrefix("The messages above stay here to read, but Lu no longer sees them"))
}

// MARK: /compact

private func compact(_ id: Int, trigger: String? = "manual", before: Double? = nil, after: Double? = nil, ms: Int? = nil, error: String? = nil) -> ChatEvent {
    ChatEvent(id: id, at: id * 1000, kind: "compact", ms: ms, trigger: trigger, before: before, after: after, error: error)
}

@Test func aCompactIsACutThatSaysTheSizesBeforeAndAfterInPlaceOfTheEmptyTurnLine() {
    let events = [
        person(1, "hi"), say(2), turnEnd(3, ["context_tokens": 142_300, "context_window": 200_000]),
        person(4, "/compact"), compact(5, before: 142_300, after: 18_400, ms: 14_000), turnEnd(6, ["input_tokens": 0, "output_tokens": 0]),
        person(7, "and now?"),
    ]
    #expect(texts(chatFeed(events)) == ["user: hi", "agent: m2", "end: sonnet 5.5 · 2s · 142.3k context", "user: /compact", "compacted: Context compacted | 142.3k → 18.4k tokens | −87%", "user: and now?"])
}

@Test func anAutoCompactInTheMiddleOfATurnCutsWithoutTheCommandAndTheTurnKeepsItsOwnLine() {
    let events = [person(1, "go"), say(2), compact(3, trigger: "auto", before: 181_000, after: 22_000), say(4), turnEnd(5, ["context_tokens": 25_000])]
    #expect(texts(chatFeed(events)) == ["user: go", "agent: m2", "compacted: Context compacted | auto · 181.0k → 22.0k tokens | −88%", "agent: m4", "end: sonnet 5.5 · 4s · 25.0k context"])
}

@Test func whatACompactDoesNotSayIsLeftOutAndAFailureSaysWhyAndChangesNothing() {
    #expect(Compaction(auto: false).sizes == nil && Compaction(auto: false).saved == nil)
    #expect(Compaction(auto: true).sizes == "auto")
    #expect(Compaction(after: 18_400).sizes == "18.4k tokens left" && Compaction(before: 142_300).sizes == nil)
    // nothing was freed: no percentage
    #expect(Compaction(before: 10_000, after: 10_000).saved == nil)
    let failed = Compaction(error: "Not enough room")
    #expect(failed.title == "Compaction failed" && failed.sizes == nil && failed.detail(agent: "Lu") == "The context is unchanged. Not enough room")
    #expect(Compaction(ms: 14_000).detail(agent: "Lu").hasSuffix("Took \(formatDuration(14_000))."))
    #expect(Compaction(auto: true).detail(agent: "Lu").hasPrefix("The context filled up, so Lu summarized"))
}

@Test func theContextAfterACompactIsWhatItLeftInTheWindowOfTheTurnsBeforeAndAFailedOneChangesNothing() {
    let before = [person(1, "hi"), turnEnd(2, ["context_tokens": 142_300, "context_window": 200_000]), person(3, "/compact")]
    #expect(contextUse(chatFeed(before + [compact(4, before: 142_300, after: 18_400), turnEnd(5, nil)])) == ContextUse(tokens: 18_400, window: 200_000))
    #expect(contextUse(chatFeed(before + [compact(4, error: "no room"), turnEnd(5, nil)]))?.tokens == 142_300)
    // a summary that did not say what it left leaves nothing known, as a clear does
    #expect(contextUse(chatFeed(before + [compact(4), turnEnd(5, nil)])) == nil)
    // a later turn tells the context again
    #expect(contextUse(chatFeed(before + [compact(4, after: 18_400), turnEnd(5, nil), person(6, "go"), turnEnd(7, ["context_tokens": 20_000])]))?.tokens == 20_000)
}

@Test func theContextInUseIsTheLastTurnThatToldItWithTheWindowItCameWith() {
    func end(_ usage: [String: Double]?, id: Int) -> ChatEvent { ChatEvent(id: id, at: id * 1000, kind: "turn_end", outcome: "ok", model: "m", usage: usage) }
    // Claude says it in snake case and Codex in camel case; the share is of the window the same turn reported
    let claude = chatFeed([end(["context_tokens": 50_000, "context_window": 200_000], id: 1)])
    #expect(contextUse(claude) == ContextUse(tokens: 50_000, window: 200_000))
    #expect(contextUse(claude)?.share == 0.25)
    #expect(contextUse(chatFeed([end(["contextTokens": 95_000, "contextWindow": 190_000], id: 1)]))?.share == 0.5)
    // a later turn that did not tell it (cut short) leaves the one before, and the newest that did wins
    #expect(contextUse(chatFeed([end(["context_tokens": 10_000, "context_window": 100_000], id: 1), end(["output_tokens": 5], id: 2)]))?.tokens == 10_000)
    #expect(contextUse(chatFeed([end(["context_tokens": 10_000, "context_window": 100_000], id: 1), end(["context_tokens": 40_000, "context_window": 100_000], id: 2)]))?.tokens == 40_000)
    // without the window there is a count and no share; past it the share stops at all of it; before any turn there is nothing
    #expect(contextUse(chatFeed([end(["context_tokens": 10_000], id: 1)])) == ContextUse(tokens: 10_000, window: nil))
    #expect(ContextUse(tokens: 10_000).share == nil)
    #expect(ContextUse(tokens: 300_000, window: 200_000).share == 1)
    #expect(ContextUse(tokens: 1, window: 0).share == nil)
    #expect(contextUse([]) == nil)
    // the words: a window of a million is `1M`, not `1000.0k`
    #expect(ContextUse(tokens: 45_700, window: 1_000_000).text == "45.7k of 1M")
    #expect(ContextUse(tokens: 45_700, window: 200_000).text == "45.7k of 200.0k")
    #expect(ContextUse(tokens: 1_250_000, window: 1_500_000).text == "1.3M of 1.5M")
    #expect(ContextUse(tokens: 900).text == "900")
}

@Test func aClosingLineThatStaysARowSaysTheModelAsAPersonDoes() {
    #expect(TurnSummary(model: "claude-sonnet-5-5", duration: "9s").text == "sonnet 5.5 · 9s")
    #expect(TurnSummary(model: "gpt-5-codex", duration: "9s").text == "gpt-5-codex · 9s")
}

@MainActor @Test func aHostThatSendsNoReasoningLeavesTheConversationAsItWas() async {
    let host = ScriptedHost()
    host.events = [ChatEvent(id: 1, at: 1, kind: "user", text: "go"), ChatEvent(id: 2, at: 2, kind: "assistant", text: "done")]
    let model = ConversationModel(host: host, sessionId: "s", log: { _ in })
    await model.poll()
    #expect(texts(model.rows) == ["user: go", "agent: done"] && model.failure == nil)
}

private final class Asked: @unchecked Sendable {
    private let lock = NSLock()
    private var line = ""
    var value: String {
        get { lock.withLock { line } }
        set { lock.withLock { line = newValue } }
    }
}

/// The `events` request a host that lists `capabilities` got.
private func eventsRequest(capabilities: [String]) async throws -> String {
    let asked = Asked()
    let listed = capabilities.map { "\"\($0)\"" }.joined(separator: ",")
    let server = TestServer { connection in
        connection.send("{\"event\":\"hello\",\"protocol\":1,\"pid\":0,\"startedAt\":0,\"capabilities\":[\(listed)]}\n")
        guard let line = connection.readLine() else { return }
        asked.value = line
        connection.send("{\"id\":1,\"ok\":true,\"data\":{\"events\":[],\"cursor\":0,\"streaming\":\"\"}}\n")
    }
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.path })
    _ = try await host.events(UUID().uuidString, after: 0, limit: 50)
    return asked.value
}

@Test func theAppAsksForReasoningOnlyOfAHostThatListsIt() async throws {
    #expect(try await eventsRequest(capabilities: ["events", "reasoning"]).contains("\"reasoning\":true"))
    #expect(try await eventsRequest(capabilities: ["events"]).contains("reasoning") == false)
}

@Test func hiddenShowsNoToolRowsAndTheOthersStay() {
    let rows = toolsFeed()
    #expect(texts(visibleFeed(rows, mode: .hidden)) == ["user: go", "agent: done"])
    #expect(visibleFeed(rows, mode: .collapsed) == rows && visibleFeed(rows, mode: .expanded) == rows)
}

@Test func expandedOpensEveryCallAndCollapsedFoldsThem() {
    let calls = runs(toolsFeed()).flatMap(\.calls)
    #expect(calls.map { $0.opensByDefault(.expanded, opensFailed: false) } == [true, true, true])
    #expect(calls.map { $0.opensByDefault(.collapsed, opensFailed: false) } == [false, false, false])
}

@Test func aFailedCallOpensByItselfWhileTheSwitchIsOn() {
    let calls = runs(toolsFeed()).flatMap(\.calls)
    #expect(calls.map { $0.opensByDefault(.collapsed, opensFailed: true) } == [false, true, false])
    // expanded opens everything with the switch either way, and hidden opens nothing
    #expect(calls.map { $0.opensByDefault(.expanded, opensFailed: true) } == [true, true, true])
    #expect(calls.map { $0.opensByDefault(.hidden, opensFailed: true) } == [false, false, false])
}

@Test func aCallsOutputIsCutAtTheChosenLengthAndSaysHowManyAreLeft() {
    var call = ToolCall(start: ChatEvent(id: 1, at: 1, kind: "tool_start", callId: "a", tool: "Bash", arg: "ls"))
    call.finish(ChatEvent(id: 2, at: 2, kind: "tool_end", callId: "a", tool: "Bash", output: (1...60).map { "line \($0)" }, status: "ok"))
    #expect(OutputLength.short.visible(call.output, expanded: false).hidden == 40)
    #expect(OutputLength.medium.visible(call.output, expanded: false).lines.count == 50 && OutputLength.medium.visible(call.output, expanded: false).hidden == 10)
    #expect(OutputLength.long.visible(call.output, expanded: false).hidden == 0 && OutputLength.long.visible(call.output, expanded: false).lines.count == 60)
    #expect(OutputLength.medium.visible(call.output, expanded: true).hidden == 0)
}

@Test func aPendingApprovalIsOverTheBoxAndNotInTheFeed() {
    let choices: [ChatChoice] = [.init(id: "y", label: "Allow", allow: true), .init(id: "n", label: "Deny", allow: false)]
    let ask = ChatEvent(id: 2, at: 0, kind: "approval", tool: "Bash", arg: "ls", approvalId: "p", choices: choices)
    let rows = chatFeed([ChatEvent(id: 1, at: 0, kind: "user", text: "go"), ask], pending: ["p"])
    #expect(pendingApprovals(rows).map(\.approvalId) == ["p"])
    #expect(texts(visibleFeed(rows, mode: .expanded)) == ["user: go"])
    // answered, it is a line in the feed and nothing waits
    let answered = chatFeed([ask, ChatEvent(id: 3, at: 0, kind: "approval_answered", approvalId: "p", choiceId: "y")])
    #expect(pendingApprovals(answered).isEmpty && visibleFeed(answered, mode: .expanded).count == 1)
}

@Test func theOutlineAddsTheStepsThatEveryPreparationEndsWithUntilTheyStart() {
    func row(_ step: String, _ status: StepRow.Status) -> StepRow { StepRow(step: step, status: status, line: step, reason: nil, progress: nil) }
    let cloning = preparationOutline([row("clone", .running)])
    #expect(cloning.map(\.step) == ["clone", "agent", "message"] && cloning.map(\.status) == [.running, nil, nil])
    let waiting = preparationOutline([row("worktree", .done), row("agent", .done), row("message", .running)])
    #expect(waiting.map(\.step) == ["worktree", "agent", "message"] && waiting.allSatisfy { $0.status != nil })
    #expect(preparationOutline([row("worktree", .done), row("message", .running)]).map(\.step) == ["worktree", "message"])
    #expect(preparationOutline([]).map(\.line) == ["Start the agent", "Send your message"])
}

@Test func theFractionOfAClonesProgressComesFromGitsPercentage() {
    #expect(progressFraction("Receiving objects:  63% (1234/1960)") == 0.63)
    #expect(progressFraction("Resolving deltas: 100% (10/10), done.") == 1)
    #expect(progressFraction("Counting objects") == nil && progressFraction(nil) == nil && progressFraction("999%") == nil)
}

// MARK: AskUserQuestion

private let askedQuestions = """
{ "id": 1, "at": 0, "kind": "approval", "approvalId": "q1", "tool": "AskUserQuestion",
  "questions": [
    { "question": "Which auth approach?", "header": "Auth", "multiSelect": false, "options": [{ "label": "JWT", "description": "Stateless", "preview": "Bearer x" }, { "label": "Cookies", "description": "Sessions" }] },
    { "question": "Which providers?", "header": "Providers", "multiSelect": true, "options": [{ "label": "GitHub", "description": "" }, { "label": "Google", "description": "" }] }
  ],
  "choices": [{ "id": "allow", "label": "Send answers", "allow": true }, { "id": "deny", "label": "Skip", "allow": false }] }
"""

private func answered(_ json: String) throws -> ChatEvent { try JSONDecoder().decode(ChatEvent.self, from: Data(json.utf8)) }

@Test func anApprovalWithQuestionsIsACardThatCarriesThemAndAnyOtherCardHasNone() throws {
    let ask = try answered(askedQuestions)
    guard case .approval(_, let card)? = chatFeed([ask], pending: ["q1"]).first else {
        Issue.record("not a card")
        return
    }
    #expect(card.questions.map(\.header) == ["Auth", "Providers"] && card.questions.map(\.multiSelect) == [false, true])
    #expect(card.questions[0].options.map(\.label) == ["JWT", "Cookies"] && card.questions[0].options[0].preview == "Bearer x")
    #expect(card.questions[0].options[1].preview == nil && card.choices.map(\.id) == ["allow", "deny"])
    let plain = ChatEvent(id: 2, at: 0, kind: "approval", tool: "Bash", arg: "ls", approvalId: "p", choices: [.init(id: "y", label: "Yes", allow: true)])
    guard case .approval(_, let generic)? = chatFeed([plain], pending: ["p"]).first else {
        Issue.record("not a card")
        return
    }
    #expect(generic.questions.isEmpty)
}

@Test func anAnsweredQuestionIsOneLineWithEachAnswerAndASkippedOneSaysSo() throws {
    let ask = try answered(askedQuestions)
    func line(_ choice: String, _ answers: [String: String]?) -> String {
        texts(chatFeed([ask, ChatEvent(id: 2, at: 0, kind: "approval_answered", approvalId: "q1", choiceId: choice, answers: answers)]))[0]
    }
    #expect(line("allow", ["Which auth approach?": "JWT", "Which providers?": "GitHub, Google"]) == "allowed: Answered · by you\nAuth: JWT\nProviders: GitHub, Google")
    #expect(line("deny", nil) == "declined: Skipped the questions · by you")
    // answers that did not come with an allowing choice are not shown as given
    #expect(line("deny", ["Which auth approach?": "JWT"]) == "declined: Skipped the questions · by you")
}

@Test func aRequestThatTimedOutIsNotSaidToBeSomethingTheHostSentThatWasNotUnderstood() {
    #expect(ConversationModel.words(ControlError.timeout) == "The chat host took too long to answer")
    #expect(ConversationModel.words(ControlError.badLine) == "The chat host sent something that was not understood")
    #expect(ConversationModel.words(ControlError.closed) == "The chat host is not answering")
}

@Test func aTableOfPipesIsOneBlockWithItsAlignmentsAndItsRowsCompleted() {
    let blocks = markdownBlocks("Intro\n\n| Team | People |\n|:---|---:|\n| **Dollar** | Alex, Pipe |\n| Markets |\n\nAfter")
    guard blocks.count == 5, case .table(let table) = blocks[2] else { Issue.record("expected one table, got \(blocks)"); return }
    #expect(table.header.map { String($0.characters) } == ["Team", "People"] && table.aligns == [.leading, .trailing])
    #expect(table.rows.map { $0.map { String($0.characters) } } == [["Dollar", "Alex, Pipe"], ["Markets", ""]])
    #expect(blocks.map { if case .table = $0 { "table" } else { "other" } } == ["other", "other", "table", "other", "other"])
    // a table still being written: the header with no separator yet is a line, and one with no rows is a table without rows
    if case .line = markdownBlocks("| a | b |")[0] {} else { Issue.record("a lone header is a line") }
    guard case .table(let early) = markdownBlocks("| a | b |\n|---|---|")[0] else { Issue.record("expected a table"); return }
    #expect(early.rows.isEmpty && early.header.count == 2)
    // a pipe inside a cell, escaped, and a line that only looks like a table
    guard case .table(let escaped) = markdownBlocks("| a |\n|---|\n| x \\| y |")[0] else { Issue.record("expected a table"); return }
    #expect(String(escaped.rows[0][0].characters) == "x | y")
    if case .line = markdownBlocks("| not | a table |\nnext line")[0] {} else { Issue.record("no separator, no table") }
}

@Test func numberedItemsQuotesAndRulesAreBlocksOfTheirOwn() {
    let blocks = markdownBlocks("1. first\n  2) second\n> quoted\n> and more\n---\n***bold*** is not a rule\n10 apples")
    func shape(_ block: MarkdownBlock) -> String {
        switch block {
        case .numbered(let level, let number, _): "numbered \(level) \(number)"
        case .quote(let text): "quote \(String(text.characters).replacingOccurrences(of: "\n", with: "/"))"
        case .rule: "rule"
        case .line: "line"
        default: "other"
        }
    }
    #expect(blocks.map(shape) == ["numbered 0 1", "numbered 1 2", "quote quoted/and more", "rule", "line", "line"])
}

@Test func aTableCopiesAsTabsForASpreadsheetAndAsMarkdownWithItsAlignments() {
    guard case .table(let table) = markdownBlocks("| Plan | Price |\n|:--|--:|\n| **Free** | $0 |\n| Team | a \\| b |")[0] else { Issue.record("expected a table"); return }
    #expect(table.tsv == "Plan\tPrice\nFree\t$0\nTeam\ta | b")
    #expect(table.markdown == "| Plan | Price |\n| --- | ---: |\n| Free | $0 |\n| Team | a \\| b |")
}

// MARK: live line kind chips and MCP calls

@Test func theLiveLinesChipFollowsWhatTheAgentWaitsOn() {
    func runningChip(_ tool: String, arg: String = "x", waiting: Bool = false) -> KindChip? {
        group(chatFeed([ChatEvent(id: 1, at: 0, kind: "tool_start", callId: "c", tool: tool, arg: arg)])).chip(waiting: waiting)
    }
    let thinking = group(chatFeed([ChatEvent(id: 1, at: 0, kind: "user", text: "go"), ChatEvent(id: 2, at: 1, kind: "reasoning", text: "Hm.")]))
    #expect(thinking.chip(waiting: false) == .thinking)
    #expect(thinking.chip(waiting: true) == .needsYou)
    #expect(runningChip("Read", arg: "a.ts") == .read)
    #expect(runningChip("Grep", arg: "q") == .search)
    #expect(runningChip("Glob", arg: "*.swift") == .search)
    #expect(runningChip("Edit", arg: "a.ts") == .edit)
    #expect(runningChip("Bash", arg: "pnpm test") == .shell)
    #expect(runningChip("mcp__linear__create_issue", arg: #"{"title":"x"}"#) == .mcp(server: "linear"))
    #expect(runningChip("Bash", arg: "git push", waiting: true) == .needsYou)
    #expect(runningChip("WebFetch", arg: "https://example.test") == nil)
}

@Test func anMcpCallReadsAsItsServerAndToolWithoutTheInternalNameOrArgumentsJson() {
    let args = #"{"title":"Subagent UI in chat","team":"ENG"}"#
    let start = ChatEvent(id: 1, at: 0, kind: "tool_start", callId: "m1", tool: "mcp__linear__create_issue", arg: args)
    let live = group(chatFeed([start]))
    #expect(live.chip(waiting: false) == .mcp(server: "linear"))
    #expect(live.doing == "create_issue")
    #expect(live.doing?.contains("mcp__") == false && live.doing?.contains("{") == false)
    let step = live.calls[0]
    #expect(step.label == "create_issue" && step.subject == "linear" && step.arg == args)
}

@Test func everyKindChipHasItsLabelTintAndIcon() {
    let cases: [(KindChip, String, ChipTint, AppIcon?)] = [
        (.thinking, "Thinking", .thought, nil),
        (.read, "Read", .files, .fileText),
        (.search, "Search", .files, .search),
        (.edit, "Edit", .files, .pencil),
        (.shell, "Shell", .shell, .terminal),
        (.mcp(server: "linear"), "linear", .mcp, .plug),
        (.subagents(1), "1 subagent", .subagents, .users),
        (.subagents(3), "3 subagents", .subagents, .users),
        (.subagent(type: "Explore"), "Explore", .subagents, .users),
        (.needsYou, "Needs you", .attention, nil),
    ]
    for (chip, label, tint, icon) in cases {
        #expect(chip.label == label && chip.tint == tint && chip.icon == icon)
    }
}

// MARK: the live line's timers and the slow call

@Test func theLiveTimerIsTheRunningCallsOwnAndAShellOrMcpCallPastThirtySecondsIsSlow() {
    func timer(_ tool: String, ageMs: Int, turnMs: Int = 0) -> LiveTimer {
        // the turn began `turnMs` ago, the call `ageMs` ago, both read at 1_000_000
        let started = ChatEvent(id: 2, at: 1_000_000 - ageMs, kind: "tool_start", callId: "c", tool: tool, arg: "x")
        return group(chatFeed([ChatEvent(id: 1, at: 1_000_000 - max(turnMs, ageMs), kind: "user", text: "go"), started]))
            .liveTimer(now: 1_000_000, turnStart: 1_000_000 - max(turnMs, ageMs))
    }
    #expect(timer("Bash", ageMs: 31_000).slow)
    #expect(timer("Bash", ageMs: 30_000).slow == false)
    #expect(timer("Bash", ageMs: 30_001).slow)
    #expect(timer("mcp__linear__create_issue", ageMs: 31_000).slow)
    #expect(timer("mcp__linear__create_issue", ageMs: 30_000).slow == false)
    #expect(timer("Read", ageMs: 300_000).slow == false)
    #expect(timer("Grep", ageMs: 300_000).slow == false)
    #expect(timer("Edit", ageMs: 300_000).slow == false)
    // the call's own time is the first, the turn's is beside it only while longer
    let both = timer("Bash", ageMs: 5_000, turnMs: 65_000)
    #expect(both.primaryMs == 5_000 && both.turnMs == 65_000 && both.slow == false)
    let same = timer("Bash", ageMs: 5_000)
    #expect(same.primaryMs == 5_000 && same.turnMs == nil)
}

@Test func aSlowCallEndsItsAmberAndAThinkingRunUsesTheTurnsTime() {
    var ended = ChatEvent(id: 3, at: 1_060_000, kind: "tool_end", callId: "c", tool: "Bash")
    ended.status = "ok"
    let done = group(chatFeed([ChatEvent(id: 1, at: 1_000_000, kind: "tool_start", callId: "c", tool: "Bash", arg: "pnpm test"), ended]))
    #expect(done.liveTimer(now: 1_090_000).slow == false)
    // no call goes: the timer is the turn's, as before
    let thinking = group(chatFeed([ChatEvent(id: 1, at: 1_000_000, kind: "user", text: "go"), ChatEvent(id: 2, at: 1_001_000, kind: "reasoning", text: "Hm.")]))
    let timer = thinking.liveTimer(now: 1_045_000, turnStart: 1_000_000)
    #expect(timer == LiveTimer(primaryMs: 45_000, turnMs: nil, slow: false))
}

// MARK: subagents

/// A turn in which the main agent launches a subagent (its `Agent` call c1) that thinks, calls, answers and launches another (c3),
/// while the main agent has a call of its own after it.
private let subagentTurn: [ChatEvent] = [
    ChatEvent(id: 1, at: 0, kind: "user", text: "Look into it"),
    ChatEvent(id: 2, at: 100, kind: "tool_start", callId: "c1", tool: "Agent", arg: "{\"description\":\"Explore\"}"),
    ChatEvent(id: 3, at: 110, kind: "task", text: "Explore", callId: "c1", taskId: "t1", state: "started", agentType: "Explore", background: false),
    ChatEvent(id: 4, at: 200, kind: "reasoning", text: "Where is it?", parentCallId: "c1"),
    ChatEvent(id: 5, at: 300, kind: "tool_start", callId: "s1", tool: "Read", arg: "a.ts", parentCallId: "c1"),
    ChatEvent(id: 6, at: 400, kind: "tool_end", callId: "s1", tool: "Read", output: ["x"], status: "ok", parentCallId: "c1"),
    ChatEvent(id: 7, at: 450, kind: "task", text: "Look inside", callId: "c3", parentCallId: "c1", taskId: "t2", state: "started", agentType: "general-purpose"),
    ChatEvent(id: 8, at: 500, kind: "task", text: "Reading", callId: "c1", taskId: "t1", state: "progress", lastTool: "Read", tools: 1, tokens: 900, ms: 390),
    ChatEvent(id: 9, at: 600, kind: "assistant", text: "Found it in a.ts", parentCallId: "c1"),
    ChatEvent(id: 10, at: 700, kind: "task", callId: "c1", taskId: "t1", state: "completed", tools: 1, tokens: 1200, ms: 600),
    ChatEvent(id: 11, at: 710, kind: "tool_end", callId: "c1", tool: "Agent", output: ["Found it"], status: "ok"),
    ChatEvent(id: 12, at: 800, kind: "tool_start", callId: "m1", tool: "Bash", arg: "pnpm test"),
    ChatEvent(id: 13, at: 900, kind: "tool_end", callId: "m1", tool: "Bash", output: ["ok"], status: "ok"),
    ChatEvent(id: 14, at: 1000, kind: "assistant", text: "Done"),
    ChatEvent(id: 15, at: 1100, kind: "turn_end", outcome: "ok", model: "claude-sonnet-5-5"),
]

@Test func theNewFieldsAreDecodedFromTheHostsEvents() throws {
    let json = #"""
    {"id":3,"at":1,"kind":"task","callId":"c1","taskId":"t1","state":"progress","agentType":"Explore","text":"Reading","lastTool":"Read","tools":2,"tokens":900,"ms":390,"background":true,"parentCallId":"c0"}
    """#
    let event = try JSONDecoder().decode(ChatEvent.self, from: Data(json.utf8))
    #expect(event == ChatEvent(id: 3, at: 1, kind: "task", text: "Reading", callId: "c1", parentCallId: "c0", taskId: "t1", state: "progress", agentType: "Explore", lastTool: "Read", tools: 2, tokens: 900, ms: 390, background: true))
    let call = try JSONDecoder().decode(ChatEvent.self, from: Data(#"{"id":4,"at":1,"kind":"tool_start","callId":"s1","tool":"Read","parentCallId":"c1"}"#.utf8))
    #expect(call.parentCallId == "c1")
    // an event of a host that predates it has none
    #expect(try golden("tools").events.allSatisfy { $0.parentCallId == nil && $0.taskId == nil && $0.state == nil })
}

private func subagents(_ rows: [FeedRow]) -> [Subagent] {
    rows.flatMap { row -> [Subagent] in if case .tools(_, let group) = row { group.subagents } else { [] } }
}

@Test func whatASubagentDidIsNotDrawnInTheMainConversationButItsLaunchingCallIsNotACallOfTheRunEither() {
    let rows = chatFeed(subagentTurn)
    // the subagent is a row of the run, the main agent's own call is its call, and the launching `Agent` call is neither an "other tool" nor drawn
    #expect(texts(rows) == ["user: Look into it", "tools: Worked | 1 command · 1 subagent", "agent: Done", "end: sonnet 5.5 · 1s"])
    let run = group(rows)
    #expect(run.calls.map(\.id) == ["m1"] && run.thoughts.isEmpty && run.subagents.map(\.id) == ["c1"])
}

@Test func aPageThatStartsInsideASubagentDrawsNoOrphanForItsCallsAndTextNorItsEnds() {
    let page = Array(subagentTurn[4...])
    // what the subagent did before the page is not here; its progress and end still make its row, and the main agent's own work is drawn as it would be
    #expect(texts(chatFeed(page)) == ["tools: Worked | 1 command · 1 subagent", "agent: Done", "end: sonnet 5.5"])
    let only = subagents(chatFeed(page))
    #expect(only.map(\.status) == [.completed] && only[0].type == "Agent" && only[0].name == "Agent")
}

@Test func aFeedWithNoLinkEventsIsTheFeedItWasAndOneWithThemIsTheSameWithTheLinkedEventsRemoved() throws {
    let before = chatFeed(try golden("tools").events)
    #expect(before == chatFeed(try golden("tools").events.filter { $0.parentCallId == nil && $0.kind != "task" }))
    #expect(subagents(before).isEmpty)
    // with the link events gone the launching call is drawn as the other tool it was, with no row
    let without = chatFeed(subagentTurn.filter { $0.parentCallId == nil && $0.kind != "task" })
    #expect(texts(without) == ["user: Look into it", "tools: Worked | 1 command · 1 other tool", "agent: Done", "end: sonnet 5.5 · 1s"])
}

// MARK: a subagent's row

private func task(_ id: Int, _ at: Int, _ call: String, _ state: String, text: String? = nil, type: String? = nil, lastTool: String? = nil, tools: Int? = nil, ms: Int? = nil) -> ChatEvent {
    ChatEvent(id: id, at: at, kind: "task", text: text, callId: call, taskId: "t-\(call)", state: state, agentType: type, lastTool: lastTool, tools: tools, ms: ms)
}

@Test func aSubagentRowHasItsTypeTitleStepStepsTimerAndStateFromEvents() {
    // running: from its start, its step is its last event, its count is its calls
    var events = [
        ChatEvent(id: 1, at: 1_000, kind: "tool_start", callId: "a1", tool: "Agent", arg: "{}"),
        task(2, 1_100, "a1", "started", text: "Find the adapter", type: "Explore"),
    ]
    var row = subagents(chatFeed(events))[0]
    #expect(row.type == "Explore" && row.name == "Find the adapter" && row.status == .running)
    #expect(row.step == nil && row.words == "Starting" && row.steps == 0)
    #expect(row.elapsedMs(now: 6_100) == 5_000)
    events.append(ChatEvent(id: 3, at: 1_200, kind: "tool_start", callId: "s1", tool: "Read", arg: "src/a.ts", parentCallId: "a1"))
    events.append(ChatEvent(id: 4, at: 1_300, kind: "tool_end", callId: "s1", tool: "Read", output: ["x"], status: "ok", parentCallId: "a1"))
    events.append(ChatEvent(id: 5, at: 1_400, kind: "tool_start", callId: "s2", tool: "Grep", arg: "KindChip", parentCallId: "a1"))
    row = subagents(chatFeed(events))[0]
    #expect(row.words == "Searching KindChip" && row.steps == 2)
    // a thought and its text are its last event too
    events.append(ChatEvent(id: 6, at: 1_500, kind: "reasoning", text: "Hm", parentCallId: "a1"))
    #expect(subagents(chatFeed(events))[0].words == "Thinking")
    // with no event of its own the step is the last tool of its latest progress, and the count is the provider's
    let progress = [task(1, 1_000, "a1", "started", text: "T", type: "Explore"), task(2, 2_000, "a1", "progress", lastTool: "Read", tools: 3), task(3, 3_000, "a1", "progress", lastTool: "Grep", tools: 4)]
    row = subagents(chatFeed(progress))[0]
    #expect(row.words == "Using Grep" && row.steps == 4)
    // the end states, each with its mark and its own duration
    let ends: [(String, SubagentStatus, String)] = [("completed", .completed, "Finished"), ("failed", .failed, "Failed"), ("stopped", .stopped, "Stopped")]
    for (state, status, words) in ends {
        row = subagents(chatFeed(progress + [task(4, 9_000, "a1", state, tools: 4, ms: 7_500)]))[0]
        #expect(row.status == status && row.words == words && row.steps == 4)
        // an ended subagent's timer stops: the provider's duration, whatever the time is now
        #expect(row.elapsedMs(now: 99_000) == 7_500)
        row = subagents(chatFeed(progress + [task(4, 9_000, "a1", state)]))[0]
        #expect(row.elapsedMs(now: 99_000) == 8_000)
    }
}

@Test func severalSubagentsLaunchedTogetherEachHaveARowInTheOrderTheyStarted() {
    let events = [
        ChatEvent(id: 1, at: 0, kind: "user", text: "go"),
        ChatEvent(id: 2, at: 10, kind: "tool_start", callId: "a1", tool: "Agent"), task(3, 11, "a1", "started", text: "One", type: "Explore"),
        ChatEvent(id: 4, at: 12, kind: "tool_start", callId: "a2", tool: "Agent"), task(5, 13, "a2", "started", text: "Two", type: "general-purpose"),
        ChatEvent(id: 6, at: 14, kind: "tool_start", callId: "a3", tool: "Agent"), task(7, 15, "a3", "started", text: "Three", type: "Explore"),
        task(8, 20, "a2", "completed"),
    ]
    let rows = chatFeed(events)
    #expect(texts(rows) == ["user: go", "tools: Working | 3 subagents"])
    let run = group(rows)
    #expect(run.subagents.map(\.name) == ["One", "Two", "Three"] && run.calls.isEmpty)
    #expect(run.subagents.map(\.status) == [.running, .completed, .running])
    // the line waits for the two that run; the chip counts them, and when none runs the line is the run's own
    #expect(run.runningSubagents == 2 && run.chip(waiting: false) == .subagents(2) && run.doing == "Waiting for them")
    #expect(run.chip(waiting: false)?.label == "2 subagents" && run.chip(waiting: true) == .needsYou)
    #expect(run.liveTimer(now: 100, turnStart: 0) == LiveTimer(primaryMs: 89, turnMs: 100, slow: false))
    let done = group(chatFeed(events + [task(9, 30, "a1", "failed"), task(10, 31, "a3", "stopped")]))
    #expect(done.runningSubagents == 0 && done.isWorking == false && done.doing == nil && done.chip(waiting: false) == .thinking)
    #expect(done.title == "Worked" && done.summary == "3 subagents")
}

@Test func theSummaryCountsSubagentsApartFromOtherToolsAndCallsAnAloneRunIsStillWorked() {
    var events = subagentTurn
    events.insert(ChatEvent(id: 16, at: 850, kind: "tool_start", callId: "w1", tool: "WebFetch", arg: "https://example.test"), at: 11)
    let run = group(chatFeed(events))
    #expect(run.summary == "1 command · 1 subagent · 1 other tool")
    #expect(ToolGroup(calls: []).title == "Thought")
}

@Test func aSubagentGoesOnFromEventsThatArriveAfterTheTurnThatLaunchedItEnded() {
    let launch: [ChatEvent] = [
        ChatEvent(id: 1, at: 0, kind: "user", text: "go"),
        ChatEvent(id: 2, at: 10, kind: "tool_start", callId: "a1", tool: "Agent"), task(3, 11, "a1", "started", text: "Slow", type: "Explore"),
        ChatEvent(id: 4, at: 12, kind: "tool_end", callId: "a1", tool: "Agent", output: ["Async agent launched"], status: "ok"),
        ChatEvent(id: 5, at: 20, kind: "assistant", text: "I will wait."),
        ChatEvent(id: 6, at: 30, kind: "turn_end", outcome: "ok"),
    ]
    // the turn ended and the subagent still runs: the end of the turn does not stop it, as it stops a call
    let ended = subagents(chatFeed(launch))
    #expect(ended.map(\.status) == [.running])
    // what comes after the turn's end updates the row it had, and the run that launched it is not another
    let after = chatFeed(launch + [
        ChatEvent(id: 7, at: 40, kind: "tool_start", callId: "s1", tool: "Read", arg: "late.ts", parentCallId: "a1"),
        task(8, 50, "a1", "progress", lastTool: "Read", tools: 1),
        task(9, 60, "a1", "completed", tools: 1, ms: 50),
    ])
    #expect(texts(after) == ["user: go", "tools: Worked | 1 subagent", "agent: I will wait.", "end: 0s"])
    let row = subagents(after)[0]
    #expect(row.status == .completed && row.steps == 1 && row.words == "Finished" && row.endedAt == 60)
}

@Test func aSubagentWithAStartAndNoEndKeepsRunningAndOneThatIsNotLaunchedHereIsNoRow() {
    let events = [
        ChatEvent(id: 1, at: 0, kind: "user", text: "go"),
        ChatEvent(id: 2, at: 10, kind: "tool_start", callId: "a1", tool: "Agent"), task(3, 11, "a1", "started", text: "Never ends", type: "Explore"),
        ChatEvent(id: 4, at: 30, kind: "turn_end", outcome: "ok"),
        // a nested subagent is its parent's, not the conversation's
        ChatEvent(id: 5, at: 40, kind: "task", text: "Nested", callId: "n1", parentCallId: "a1", taskId: "t-n1", state: "started", agentType: "Explore"),
    ]
    let found = subagents(chatFeed(events))
    #expect(found.map(\.status) == [.running] && found[0].name == "Never ends")
    #expect(group(chatFeed(events)).isWorking)
}

@Test func theFixtureHostServesThreeParallelSubagentsOneEndingAfterTheTurnAndOneThatNeverEnds() async throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.chatSocketPath })
    let session = "a7b8c9d0-6e5f-4a21-9c4d-5e6f7a8b9c07"
    let reply = try await host.events(session, after: 0, limit: 200)
    let rows = chatFeed(reply.events)
    // the three launching calls are not calls of the run, and the thought before them is
    let run = group(rows)
    #expect(run.calls.isEmpty && run.thoughts.count == 1 && run.subagents.count == 3)
    #expect(run.subagents.map(\.type) == ["Explore", "general-purpose", "Explore"])
    #expect(run.subagents.map(\.id) == ["a1", "a2", "a3"])
    // one finished before the turn ended, one after it, and the third has a start and no end (so it is the only one the line waits for)
    #expect(run.subagents.map(\.status) == [.completed, .completed, .running])
    #expect(run.subagents[1].endedAt == 1_791_960_004_500 && run.subagents[0].endedAt == 1_791_960_009_000)
    #expect(run.subagents[0].steps == 1 && run.subagents[1].words == "Finished" && run.subagents[2].words == "Starting")
    // while the turn went on the line waited for three; the second ended before it did, and the first after it
    #expect(group(chatFeed(reply.events.filter { $0.id < 17 })).chip(waiting: false) == .subagents(3))
    #expect(group(chatFeed(reply.events.filter { $0.id < 20 })).chip(waiting: false) == .subagents(2))
    #expect(group(chatFeed(reply.events.filter { $0.id < 21 })).runningSubagents == 2)
    #expect(run.runningSubagents == 1 && run.chip(waiting: false) == .subagents(1) && run.liveTimer(now: 1_791_960_100_000).primaryMs == 97_500)
    // what the subagents said and did is not in the main conversation
    #expect(texts(rows).filter { $0.hasPrefix("agent") } == ["agent: Three subagents are look"])
}

// MARK: a subagent's view

private func flow(_ work: SubagentWork?) -> [String] {
    (work?.items ?? []).map {
        switch $0 {
        case .message(_, let text): "message: \(text)"
        case .note(_, let text): "note: \(text)"
        case .error(_, let text): "error: \(text)"
        case .skill: "skill"
        case .tools(_, let group, let live): "tools\(live ? " live" : ""): \(group.title) | \(group.summary) | \(group.thoughts.map(\.text).joined(separator: ","))"
        case .slice: "slice"
        }
    }
}

@Test func aSubagentsViewIsItsOwnCallsThoughtsAndMessagesWithTheRowOfTheSubagentItLaunched() {
    var events = subagentTurn
    events[1].arg = #"{"description":"Explore","prompt":"Find \"it\".\nReport paths.","subagent_type":"Explore"}"#
    let work = subagentWork(in: events, call: "c1")
    // the header says what the row said: its title and type, finished and how long it took
    #expect(work?.header == SubagentHeader(title: "Explore", type: "Explore", state: .completed, startedAt: 110, durationMs: 600, taskId: "t1"))
    // the brief is the prompt it was launched with; then its thought and call as one run with the row of the subagent it launched (still going,
    // so the run is live: the line waits for it), and its message
    #expect(work?.brief == "Find \"it\".\nReport paths.")
    #expect(flow(work) == ["tools live: Working | 1 thought · 1 file read · 1 subagent | Where is it?", "message: Found it in a.ts"])
    guard case .tools(_, let run, _)? = work?.items.first else { Issue.record("no run"); return }
    #expect(run.subagents.map(\.id) == ["c3"] && run.subagents[0].name == "Look inside" && run.subagents[0].status == .running)
    // what the main agent did and said is not in it, and the launching call of the nested subagent is not a call of the run
    #expect(flow(work).allSatisfy { $0.contains("pnpm test") == false && $0.contains("Done") == false })
}

@Test func theViewOfASubagentLaunchedByASubagentIsItsOwnAndHasNoneOfItsParents() {
    let work = subagentWork(in: subagentTurn, call: "c3")
    #expect(work?.header.title == "Look inside" && work?.header.type == "general-purpose" && work?.header.state == .running)
    #expect(work?.header.durationMs == nil && work?.brief == nil && work?.items.isEmpty == true)
    // opened from a parent that launched it, and a third level goes one level at a time
    var deeper = subagentTurn
    deeper.append(ChatEvent(id: 16, at: 1200, kind: "tool_start", callId: "d1", tool: "Grep", arg: "x", parentCallId: "c3"))
    deeper.append(ChatEvent(id: 17, at: 1210, kind: "task", text: "Deepest", callId: "c4", parentCallId: "c3", taskId: "t3", state: "started", agentType: "Explore"))
    deeper.append(ChatEvent(id: 18, at: 1220, kind: "assistant", text: "deep", parentCallId: "c4"))
    #expect(flow(subagentWork(in: deeper, call: "c3")) == ["tools live: Working | 1 search · 1 subagent | "])
    #expect(subagentWork(in: deeper, call: "c3").flatMap { work -> [String] in
        guard case .tools(_, let run, _)? = work.items.first else { return [] }
        return run.subagents.map(\.id) + run.calls.map(\.id)
    } == ["c4", "d1"])
    #expect(flow(subagentWork(in: deeper, call: "c4")) == ["message: deep"])
    #expect(flow(subagentWork(in: deeper, call: "c1")).contains { $0.hasPrefix("message: Found it") })
}

@Test func whileASubagentRunsItsLastRunIsLiveAndOnceItEndedACallThatNeverEndedWasStopped() {
    let begun: [ChatEvent] = [
        ChatEvent(id: 1, at: 0, kind: "tool_start", callId: "a1", tool: "Agent"), task(2, 10, "a1", "started", text: "Slow", type: "Explore"),
        ChatEvent(id: 3, at: 20, kind: "tool_start", callId: "s1", tool: "Read", arg: "a.ts", parentCallId: "a1"),
        ChatEvent(id: 4, at: 25, kind: "tool_end", callId: "s1", tool: "Read", output: ["x"], status: "ok", parentCallId: "a1"),
        ChatEvent(id: 5, at: 30, kind: "assistant", text: "Reading", parentCallId: "a1"),
        ChatEvent(id: 6, at: 40, kind: "tool_start", callId: "s2", tool: "Bash", arg: "pnpm test", parentCallId: "a1"),
    ]
    // the run the subagent is working in is the one the line shows live, as the conversation's is for the main agent; the earlier one is not
    #expect(flow(subagentWork(in: begun, call: "a1")) == ["tools: Explored | 1 file read | ", "message: Reading", "tools live: Working | 1 command | "])
    let ended = subagentWork(in: begun + [task(7, 50, "a1", "stopped", ms: 40)], call: "a1")
    #expect(ended?.header.state == .stopped && ended?.header.durationMs == 40)
    #expect(flow(ended) == ["tools: Explored | 1 file read | ", "message: Reading", "tools: Worked | 1 command | "])
    guard case .tools(_, let last, _)? = ended?.items.last else { Issue.record("no run"); return }
    #expect(last.calls.map(\.status) == [.stopped] && last.isStopped)
    // a call nobody launched has no view
    #expect(subagentWork(in: begun, call: "zz") == nil)
}

@Test func theBriefIsThePromptOfTheLaunchingCallsInputCutLikeAnythingTheHostStoresAndNilWithoutOne() {
    #expect(brief(of: #"{"description":"d","prompt":"Read a.ts","subagent_type":"Explore"}"#) == "Read a.ts")
    #expect(brief(of: #"{"prompt":"  Say \"hi\" \\ done\n\nbye  "}"#) == "Say \"hi\" \\ done\n\nbye")
    // cut at 1,024 characters: no closing quote, maybe an escape left half, and the ellipsis the host ends it with
    #expect(brief(of: #"{"description":"d","prompt":"Read the chat adapter and its tests, then\nlist wh…"#) == "Read the chat adapter and its tests, then\nlist wh…")
    #expect(brief(of: #"{"prompt":"half an escape \"#) == "half an escape")
    #expect(brief(of: #"{"description":"d","subagent_type":"Explore"}"#) == nil && brief(of: "Agent") == nil && brief(of: #"{"prompt":""}"#) == nil)
}

@Test func theStateOfASubagentReadsAsRunningWithItsTimerOrHowItEnded() {
    func header(_ state: SubagentStatus, ms: Int? = nil) -> SubagentHeader { SubagentHeader(title: "T", type: "Explore", state: state, startedAt: 1_000, durationMs: ms) }
    #expect(header(.running).stateWords(now: 72_000) == "Running 1m 11s")
    #expect(header(.running).stateWords(now: 500) == "Running 0 ms")
    #expect(header(.completed, ms: 42_000).stateWords(now: 99_000) == "Finished · 42 s")
    #expect(header(.failed, ms: 5).stateWords(now: 0) == "Failed" && header(.stopped).stateWords(now: 0) == "Stopped")
    #expect(header(.running).subtitle(of: "Fix the login") == "Explore · Subagent of Fix the login")
}

@MainActor @Test func theModelRebuildsTheOpenSubagentsViewAsEventsArriveAndLeavesItWhenAskedTo() async {
    let host = ScriptedHost()
    host.state = .working
    host.events = Array(subagentTurn[..<6])
    let model = ConversationModel(host: host, sessionId: "s", log: { _ in })
    await model.poll()
    #expect(model.openSubagent == nil)
    model.show(subagent: "c1")
    #expect(model.openSubagent?.header.state == .running && flow(model.openSubagent) == ["tools live: Explored | 1 thought · 1 file read | Where is it?"])
    // the conversation's own feed is as it was
    let before = model.rows
    host.events = subagentTurn
    await model.poll()
    #expect(model.openSubagent?.header.state == .completed && flow(model.openSubagent).last == "message: Found it in a.ts")
    model.show(subagent: nil)
    #expect(model.openSubagent == nil && model.rows != before && texts(model.rows).first == "user: Look into it")
}

// MARK: stopping a subagent

@Test func aRunningSubagentsHeaderOffersStopOnlyWhileItRunsAndOnlyAHostThatListsItAndATaskToStopIt() {
    func header(_ state: SubagentStatus, task: String? = "t1", host: Bool = true, epic: String? = nil) -> SubagentHeader {
        SubagentHeader(title: "T", type: "Explore", state: state, startedAt: 0, durationMs: nil, epic: epic, taskId: task, hostStops: host)
    }
    #expect(header(.running).canStop)
    #expect(header(.running, epic: "Epic").canStop == false)
    for ended in [SubagentStatus.completed, .failed, .stopped] { #expect(header(ended).canStop == false) }
    #expect(header(.running, host: false).canStop == false && header(.running, task: nil).canStop == false)
    #expect(subagentWork(in: subagentTurn, call: "c1")?.header.taskId == "t1")
}

@MainActor @Test func stopInTheSubagentsViewAsksTheHostForThatTaskAndTheViewShowsStoppedOnlyWhenTheEventArrives() async {
    let host = ScriptedHost()
    host.state = .working
    host.events = Array(subagentTurn[..<6])
    let model = ConversationModel(host: host, sessionId: "s", log: { _ in })
    await model.poll()
    model.show(subagent: "c1")
    #expect(model.openSubagent?.header.canStop == true)
    await model.stopOpenSubagent()
    #expect(host.stopped == ["s t1"])
    // the request is not the end: the header says Running until the host's `stopped` event
    #expect(model.openSubagent?.header.state == .running)
    await model.poll()
    #expect(model.openSubagent?.header.state == .running && model.openSubagent?.header.canStop == true)
    host.events.append(ChatEvent(id: 7, at: 500, kind: "task", callId: "c1", taskId: "t1", state: "stopped"))
    await model.poll()
    #expect(model.openSubagent?.header.state == .stopped && model.openSubagent?.header.canStop == false)
    await model.stopOpenSubagent()
    #expect(host.stopped == ["s t1"], "an ended subagent is not asked to stop again")
}

@MainActor @Test func aHostThatDoesNotListStopTaskGetsNoStopAndNoRequest() async {
    let host = ScriptedHost()
    host.state = .working
    host.capabilities = [.interrupt, .send, .events]
    host.events = Array(subagentTurn[..<6])
    let model = ConversationModel(host: host, sessionId: "s", log: { _ in })
    await model.poll()
    model.show(subagent: "c1")
    #expect(model.openSubagent?.header.state == .running && model.openSubagent?.header.canStop == false)
    await model.stopOpenSubagent()
    #expect(host.stopped.isEmpty)
}

@MainActor @Test func aRefusedStopLeavesTheViewAsItWasAndTheNextPollTellsHowItStands() async {
    let host = ScriptedHost()
    host.state = .working
    host.events = Array(subagentTurn[..<6])
    host.refusingStopTask = .remote(.words("That subagent is not running"))
    let model = ConversationModel(host: host, sessionId: "s", log: { _ in })
    await model.poll()
    model.show(subagent: "c1")
    await model.stopOpenSubagent()
    #expect(host.stopped == ["s t1"] && model.openSubagent?.header.state == .running && model.refusal == nil)
}

@Test func theFixtureHostListsStopTaskAndStopsARunningSubagentOnlyOnce() async throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.chatSocketPath })
    let id = "a7b8c9d0-6e5f-4a21-9c4d-5e6f7a8b9c07"
    #expect(try await host.capabilities().contains(.stopTask))
    await #expect(throws: ControlError.remote(Refusal(code: "session.task.notRunning", text: "That task is not running"))) { try await host.stopTask(id, task: "t2") } // finished
    await #expect(throws: ControlError.remote(Refusal(code: "session.task.notRunning", text: "That task is not running"))) { try await host.stopTask(id, task: "nope") }
    try await host.stopTask(id, task: "t3")
    let after = try await host.events(id, after: 25, limit: 200).events
    #expect(after.map(\.kind) == ["task"] && after[0].state == "stopped" && after[0].callId == "a3" && after[0].taskId == "t3")
    await #expect(throws: ControlError.remote(Refusal(code: "session.task.notRunning", text: "That task is not running"))) { try await host.stopTask(id, task: "t3") }
}

@Test func theFixtureHostServesTheSubagentViewWithItsBriefItsThoughtItsMessageAndItsNestedSubagent() async throws {
    let events = try golden("subagents").events
    let work = subagentWork(in: events, call: "a1")
    #expect(work?.header.title == "Find subagent code in chat host" && work?.header.state == .completed)
    #expect(work?.brief?.hasPrefix("Read the chat adapter in src/chat/claude.ts") == true && work?.brief?.contains("\nReport file paths") == true)
    #expect(flow(work) == [
        "tools: Explored | 1 search | ", "message: translate() never reads parent_tool_use_id.",
        "tools: Worked | 1 thought · 1 subagent | translate() drops sidechain info; checking the types next.",
    ])
    #expect(subagentWork(in: events, call: "a3")?.header.state == .running)
    #expect(subagentWork(in: events, call: "n1")?.header.title == "Check the runner types")
}

// MARK: a subagent that outlives its session's work

private func launched(_ call: String, at: Int, id: Int) -> [ChatEvent] {
    [ChatEvent(id: id, at: at, kind: "tool_start", callId: call, tool: "Agent", arg: "{}"), task(id + 1, at + 1, call, "started", text: "Look", type: "Explore")]
}

@Test func aSubagentWithAStartAndNoEndShowsStoppedInItsRowTheParentsLineAndItsViewWhenTheSessionIsNotWorking() {
    var events = launched("a1", at: 10, id: 2) + [
        ChatEvent(id: 4, at: 50, kind: "tool_start", callId: "s1", tool: "Read", arg: "a.ts", parentCallId: "a1"),
        ChatEvent(id: 5, at: 60, kind: "turn_end", outcome: "ok"),
    ]
    events.insert(ChatEvent(id: 1, at: 0, kind: "user", text: "go"), at: 0)
    // working: it runs, the parent's line waits for it
    var run = group(chatFeed(events, working: true))
    #expect(run.subagents.map(\.status) == [.running] && run.doing == "Waiting for them" && run.chip(waiting: false) == .subagents(1))
    #expect(subagentWork(in: events, call: "a1", working: true)?.header.state == .running)
    // idle: the row, the parent's line (no more "Waiting for them") and the view all say stopped
    run = group(chatFeed(events, working: false))
    #expect(run.subagents.map(\.status) == [.stopped] && run.subagents[0].words == "Stopped" && run.subagents[0].endedAt == 60)
    #expect(run.runningSubagents == 0 && run.isWorking == false && run.doing == nil && run.chip(waiting: false) == .thinking)
    let work = subagentWork(in: events, call: "a1", working: false)
    #expect(work?.header.state == .stopped && work?.header.durationMs == 49 && work?.header.stateWords(now: 0) == "Stopped")
    // one that ended keeps how it ended
    let done = events + [task(9, 55, "a1", "completed")]
    #expect(group(chatFeed(done, working: false)).subagents.map(\.status) == [.completed])
}

@MainActor @Test func theConversationDrawsAnUnfinishedSubagentStoppedWhileTheHostSaysIdleAndRunningWhileItSaysWorking() async {
    let host = ScriptedHost()
    host.events = launched("a1", at: 10, id: 1) + [ChatEvent(id: 3, at: 60, kind: "turn_end", outcome: "ok")]
    host.state = .working
    let model = ConversationModel(host: host, sessionId: "s", log: { _ in })
    await model.poll()
    #expect(group(model.rows).subagents.map(\.status) == [.running])
    // no new event, only the state: the feed is drawn again
    host.state = .idle
    await model.poll()
    #expect(group(model.rows).subagents.map(\.status) == [.stopped])
}

@MainActor @Test func stopInterruptsTheTurnThenStopsEachRunningSubagentAndNoneThatEnded() async {
    let host = ScriptedHost()
    host.state = .working
    host.events = launched("a1", at: 10, id: 1) + launched("a2", at: 20, id: 3) + launched("a3", at: 30, id: 5) + [task(7, 40, "a3", "completed")]
    let model = ConversationModel(host: host, sessionId: "s", log: { _ in })
    await model.poll()
    await model.stop()
    #expect(host.interrupts == 1)
    #expect(host.stopped == ["s t-a1", "s t-a2"])
    // a host that cannot stop a subagent only gets the interrupt
    let older = ScriptedHost()
    older.capabilities = [.interrupt, .send, .events]
    older.state = .working
    older.events = launched("a1", at: 10, id: 1)
    let other = ConversationModel(host: older, sessionId: "s", log: { _ in })
    await other.poll()
    await other.stop()
    #expect(older.interrupts == 1 && older.stopped.isEmpty)
}

@Test func theEverythingGoldenHasEveryKindOfRowAndTheQuestionGoldenAsksTwoQuestions() throws {
    let all = try golden("everything")
    let rows = chatFeed(all.events, pending: all.pending)
    let kinds = Set(texts(rows).map { String($0.prefix { $0 != ":" }) })
    // a user bubble, the agent's markdown, a run of work, a permission allowed and one declined, a card no longer waiting, an error, the turn lines and a stop
    #expect(kinds.isSuperset(of: ["user", "agent", "tools", "allowed", "declined", "line", "error", "end", "stopped"]))
    #expect(rows.contains { if case .tools(_, let group) = $0 { group.thoughts.isEmpty == false } else { false } })
    let asked = try golden("question")
    let cards = chatFeed(asked.events, pending: ["q1"]).compactMap { row -> ApprovalCard? in if case .approval(_, let card) = row { card } else { nil } }
    #expect(cards.count == 1 && cards[0].questions.map(\.multiSelect) == [false, true])
}

// MARK: the work of the feed

private final class Flag: @unchecked Sendable { var raised = false }

/// A model that has read a session of 5,005 events.
@MainActor private func modelOfALongSession() async -> (model: ConversationModel, host: ScriptedHost) {
    let host = ScriptedHost()
    host.events = longChatEvents(rounds: 715)
    let model = ConversationModel(host: host, sessionId: "s", log: { _ in })
    await model.poll()
    return (model, host)
}

@MainActor @Test func anIdlePollDoesNoFeedWorkAndDoesNotTouchTheRows() async {
    let (model, _) = await modelOfALongSession()
    #expect(model.cursor == 5005 && model.rows.isEmpty == false)
    let before = model.feedWork
    let touched = Flag()
    withObservationTracking { _ = model.rows } onChange: { touched.raised = true }
    await model.poll()
    #expect(model.feedWork == before && touched.raised == false)
}

@MainActor @Test func aNewEventCostsOneUnitOfFeedWork() async {
    let (model, host) = await modelOfALongSession()
    let before = model.feedWork
    host.events.append(say(5006))
    await model.poll()
    #expect(model.cursor == 5006)
    withKnownIssue("the feed is rebuilt from every event") { #expect(model.feedWork - before == 1) }
}

@MainActor @Test func aStreamingTokenCostsAtMostOneUnitOfFeedWork() async {
    let (model, host) = await modelOfALongSession()
    let before = model.feedWork
    host.streaming = "Module 715 has"
    await model.poll()
    withKnownIssue("the feed is rebuilt from every event") { #expect(model.feedWork - before <= 1) }
}

@MainActor @Test func aPollAskedWhileAnotherIsInFlightNeverRepeatsAnEvent() async {
    let host = ScriptedHost()
    let (gate, open) = AsyncStream<Void>.makeStream()
    host.hold = { for await _ in gate {} }
    let model = ConversationModel(host: host, sessionId: "s", log: { _ in })
    // the round `run()` starts, held inside `events` with the cursor at 0
    let first = Task { await model.poll() }
    while host.asked.isEmpty { await Task.yield() }
    host.events = [say(1), say(2)]
    // an action's poll while the first waits: it does not read, the one under way goes round again when it ends
    await model.poll()
    #expect(host.asked.map(\.after) == [0])
    open.finish()
    await first.value
    #expect(host.asked.map(\.after) == [0, 2])
    #expect(model.rows.map(\.id) == ["e1", "e2"] && model.cursor == 2)
}

@MainActor @Test func aReplyBehindTheCursorNeitherMovesItBackNorAddsOldEvents() async {
    let host = ScriptedHost()
    host.events = (1...3).map(say)
    let model = ConversationModel(host: host, sessionId: "s", log: { _ in })
    await model.poll()
    #expect(model.cursor == 3 && model.rows.count == 3)
    host.rewind = true
    await model.poll()
    #expect(model.cursor == 3 && model.rows.count == 3)
}

@MainActor @Test func aHostThatKeepsAnsweringAFullPageOfOldEventsDoesNotKeepTheRoundReading() async {
    let host = ScriptedHost()
    host.events = (1...200).map(say)
    let model = ConversationModel(host: host, sessionId: "s", log: { _ in })
    await model.poll()
    #expect(model.cursor == 200)
    let before = host.asked.count
    // a full page with nothing new is not a reason to ask again: the cursor would not move
    host.stale = true
    await model.poll()
    #expect(host.asked.count - before == 1)
    #expect(model.cursor == 200 && model.rows.count == 200)
}

@MainActor @Test func aQueuedMessageIsStillDeliveredAndReadAgainWhenTheRoundThatSeesTheAgentIdleEnds() async {
    let host = ScriptedHost()
    host.state = .working
    host.events = [say(1)]
    let model = ConversationModel(host: host, sessionId: "s", log: { _ in })
    await model.poll()
    model.draft = "next"
    await model.submit()
    #expect(model.queued == "next" && host.sent.isEmpty)
    host.state = .idle
    host.events.append(say(2))
    let before = host.asked.count
    await model.poll()
    // the round delivers it, and the poll `deliver` asks from inside the round is not lost: one more pass reads what the send caused
    #expect(host.sent == ["next"])
    #expect(host.asked.count - before == 2)
    #expect(model.rows.map(\.id).contains("e2"))
}

@MainActor @Test func aSessionOffersTheOtherAgentsAndChangesToThePickedOneWithTheNextMessageNotBefore() async throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.chatSocketPath })

    // an idle claude session: the panel lists the host's agents (the one not found is listed, off)
    let idle = ConversationModel(host: host, sessionId: "c3d4e5f6-2a1b-4c8d-9e0f-1a2b3c4d5e03")
    await idle.poll()
    #expect(idle.canSwitchAgent && idle.canSwitchNow)
    #expect(idle.switchTargets.map(\.name) == ["claude", "codex", "claude-beta"] && idle.switchTargets.map(\.available) == [true, true, false])
    // its own agent is no pick; another is only picked: the session keeps its agent, and the panel does not list options it cannot know yet
    idle.chooseAgent("claude")
    #expect(idle.pendingAgent == nil)
    idle.chooseAgent("codex")
    #expect(idle.pendingAgent == "codex" && idle.agent == "claude" && idle.shownOptions.isEmpty)
    // changing one's mind costs nothing
    idle.chooseAgent("claude")
    #expect(idle.pendingAgent == nil)
    // the message makes the change
    idle.chooseAgent("codex")
    idle.draft = "go on"
    await idle.submit()
    #expect(idle.agent == "codex" && idle.pendingAgent == nil && idle.refusal == nil && idle.optionRefusal == nil)

    // an agent the host refuses stops the message, says why in words, keeps the text in the box and stays picked
    let refused = ConversationModel(host: host, sessionId: "c3d4e5f6-2a1b-4c8d-9e0f-1a2b3c4d5e03")
    await refused.poll()
    refused.chooseAgent("claude-beta")
    refused.draft = "go on"
    await refused.submit()
    #expect(refused.refusal?.text.contains("claude-beta") == true && refused.draft == "go on" && refused.pendingAgent == "claude-beta")

    // one that works takes no pick: the panel's tabs are off while it answers
    let working = ConversationModel(host: host, sessionId: "5d1f7c3a-0b6e-4a52-9a1d-3c7e8b2f4a01")
    await working.poll()
    working.chooseAgent("codex")
    #expect(working.agent == "claude" && working.pendingAgent == nil)
}
