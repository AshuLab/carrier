import Foundation
import Testing
@testable import CarrierCore

private func agent(_ harness: String = "claude") -> PanelSnapshot.Agent { PanelSnapshot.Agent(harness: harness, model: "m", provider: nil) }

private func session(
    _ id: String, _ stage: String, round: Int? = nil, status: String, harness: String = "claude", at: Int = 0, until: Int? = nil
) -> SessionsReply.Session {
    SessionsReply.Session(
        executionId: id, stage: stage, role: stage == "review" ? "reviewer" : "author", round: round, agent: agent(harness),
        status: status, startedAt: at, finishedAt: until, resume: nil
    )
}

private func failed(_ failure: SessionFailure?) -> SessionsReply.Session {
    var session = session("f", "ship", status: "failed")
    session.failure = failure
    return session
}

private func reply(_ sessions: SessionsReply.Session...) -> SessionsReply { SessionsReply(sessions: sessions) }

private func call(_ id: Int, _ callId: String, _ tool: String, arg: String? = nil, status: String = "ok", diff: [(String, String)] = []) -> [ExecEvent] {
    [
        ExecEvent(id: id, at: id, kind: "tool_start", callId: callId, tool: tool, arg: arg),
        ExecEvent(id: id + 1, at: id, kind: "tool_end", callId: callId, tool: tool, status: status, diff: diff.map { .init(sign: $0.0, text: $0.1) }),
    ]
}

private func transcript(_ events: [ExecEvent], structured: Bool = true) -> Transcript {
    var transcript = Transcript()
    transcript.apply(EventsReply(events: events, next: events.last?.id ?? 0, running: false, structured: structured))
    return transcript
}

// MARK: the counts line

@Test func theCountsLineKeepsTheToolCallsAndDropsWhatIsZero() {
    #expect(countsLine(SessionCounts()) == "0 tool calls")
    #expect(countsLine(SessionCounts(calls: 1)) == "1 tool call")
    #expect(countsLine(SessionCounts(calls: 8, edits: 2, added: 42, removed: 8, tests: 1, errors: 2)) == "8 tool calls · 2 edits +42 −8 · 1 test run · 2 errors")
    #expect(countsLine(SessionCounts(calls: 3, edits: 1, added: 0, removed: 0)) == "3 tool calls · 1 edit +0 −0")
    #expect(countsLine(SessionCounts(calls: 2, tests: 2)) == "2 tool calls · 2 test runs")
    #expect(countsLine(SessionCounts(calls: 2, errors: 1)) == "2 tool calls · 1 error")
}

@Test func theCountsComeFromTheEventsAJoinedCallIsOneCallAndAnErrorIsAnEventOrAFailedCall() {
    let events = call(1, "a", "Read") + call(3, "b", "Edit", diff: [(" ", "x"), ("-", "old"), ("+", "new"), ("+", "newer")])
        + call(5, "c", "Bash", arg: "pnpm test", status: "err") + [ExecEvent(id: 7, at: 7, kind: "error"), ExecEvent(id: 8, at: 8, kind: "say")]
    #expect(sessionCounts(events) == SessionCounts(calls: 3, edits: 1, added: 2, removed: 1, tests: 1, errors: 2))
    #expect(sessionCounts([]) == SessionCounts())
}

@Test func aCallStillRunningCountsOnceAndAnEventWithNoCallIdIsACallOfItsOwn() {
    let running = ExecEvent(id: 1, at: 1, kind: "tool_start", callId: "a", tool: "Read")
    let loose = ExecEvent(id: 2, at: 2, kind: "tool_start", tool: "Grep")
    #expect(sessionCounts([running, loose]).calls == 2)
}

@Test(arguments: ["pnpm test", "swift test", "pnpm -C macos test:unit", "cd app && npx vitest run", "pytest -q", "node --test x.ts"])
func aCommandThatRunsTestsIsATestRun(command: String) {
    #expect(sessionCounts(call(1, "a", "Bash", arg: command)).tests == 1)
}

@Test(arguments: ["ls tests/", "cat test.txt", "pnpm build", "git status"])
func otherCommandsAreNot(command: String) {
    #expect(sessionCounts(call(1, "a", "Bash", arg: command)).tests == 0)
}

@Test func onlyAShellCommandIsATestRun() {
    #expect(sessionCounts(call(1, "a", "Read", arg: "pnpm test")).tests == 0)
}

// MARK: the list

@Test func aRunningSessionIsOpenAndWearsTheRingAndTheFinishedOnesAboveAreFolded() {
    let list = sessionList(reply(
        session("c", "fix", round: 2, status: "running", at: 90_000),
        session("b", "review", round: 2, status: "finished", harness: "codex", at: 60_000, until: 85_000),
        session("a", "ship", status: "finished", at: 1000, until: 39_000)
    ), timeZone: TimeZone(identifier: "UTC")!)
    // oldest first, the running one at the bottom
    #expect(list.sections.map(\.id) == ["a", "b", "c"])
    #expect(list.sections.map(\.state) == [.done, .done, .running])
    #expect(list.sections.map(\.openByDefault) == [false, false, true])
    #expect(list.sections.map(\.agent) == ["Claude", "Codex", "Claude"])
    #expect(list.sections.map(\.initial) == ["C", "X", "C"])
    #expect(list.sections.map(\.role) == ["Builder", "Reviewer", "Fixer"])
    #expect(list.sections.map(\.place) == ["Ship", "Round 2", "Round 2"])
    #expect(list.sections.map(\.timeLabel) == ["38s", "25s", "since 00:01"])
}

@Test func aStoppedSessionIsOpenHasTheBadgeStateAndNoTime() {
    for status in ["failed", "timed_out", "interrupted", "invalid_result"] {
        let list = sessionList(reply(session("b", "fix", round: 1, status: status), session("a", "ship", status: "finished", until: 5)))
        #expect(list.sections.map(\.state) == [.done, .stopped])
        #expect(list.sections.map(\.openByDefault) == [false, true])
        #expect(list.sections[1].timeLabel == nil)
    }
}

@Test func whenEverySessionIsFinishedTheNewestIsOpen() {
    let list = sessionList(reply(session("c", "review", round: 1, status: "finished"), session("b", "ship", status: "finished")))
    #expect(list.sections.map(\.openByDefault) == [false, true])
}

@Test func aFailedSessionSaysItsKindAndDetailAndOneWithNoFailureSaysNothing() {
    let killed = SessionFailure(kind: "killed", detail: "SIGKILL", exitCode: nil, signal: "SIGKILL", hostFreeMemMb: 812, hostLoad: 6.4)
    #expect(sessionList(reply(failed(killed))).sections[0].failure == "killed: SIGKILL")
    #expect(sessionList(reply(failed(SessionFailure(kind: "unknown", detail: "", exitCode: 1)))).sections[0].failure == "unknown")
    // the same session with no failure, as an engine from before sends it, is the section it always was
    let plain = sessionList(reply(failed(nil))).sections[0]
    #expect(plain.failure == nil)
    var withFailure = sessionList(reply(failed(killed))).sections[0]
    withFailure.failure = nil
    #expect(withFailure == plain)
    #expect(sessionList(reply(session("ok", "ship", status: "finished"))).sections[0].failure == nil)
}

@Test func aShipSessionIsTheBuilderAndHasNoRound() {
    let section = sessionList(reply(session("a", "ship", status: "running"))).sections[0]
    #expect((section.role, section.place, section.state, section.openByDefault) == ("Builder", "Ship", .running, true))
}

private func many(_ n: Int, stopped: Set<Int> = []) -> SessionsReply {
    SessionsReply(sessions: (0..<n).map { session("s\($0)", "fix", round: $0, status: stopped.contains($0) ? "failed" : "finished") })
}

@Test(arguments: [0, 1, 5, 12])
func everySessionIsShownOldestFirstAndOnlyTheNewestIsOpen(total: Int) {
    let list = sessionList(many(total, stopped: [3, 7]))
    #expect(list.sections.map(\.id) == (0..<total).reversed().map { "s\($0)" })
    #expect(list.sections.map(\.openByDefault) == (0..<total).map { $0 == total - 1 })
}

@Test func theCountsAreThereOnlyWhenTheEventsAreAndTheHarnessHasAParser() {
    let sessions = reply(session("c", "fix", status: "running"), session("b", "review", status: "finished", harness: "codex"), session("a", "ship", status: "finished"))
    let list = sessionList(sessions, transcripts: [
        "c": transcript(call(1, "a", "Read") + call(3, "b", "Read")),
        "b": transcript(call(1, "a", "Read"), structured: false),
    ])
    #expect(list.sections.map { $0.counts.map(countsLine) } == [nil, nil, "2 tool calls"])
}

@Test func anEmptyTranscriptShowsZeroToolCalls() {
    let list = sessionList(reply(session("c", "fix", status: "running")), transcripts: ["c": transcript([])])
    #expect(list.sections[0].counts.map(countsLine) == "0 tool calls")
}

// MARK: folding

@Test func foldingAndUnfoldingASectionIsKeptWhateverTheRepliesDoAfterwards() {
    let before = sessionList(reply(session("b", "fix", status: "running"), session("a", "ship", status: "finished"))).sections
    var folds = SessionFolds()
    #expect(before.map { folds.isOpen($0) } == [false, true])

    folds.toggle(before[0])
    folds.toggle(before[1])
    #expect(before.map { folds.isOpen($0) } == [true, false])

    // the running one stops and a new one arrives: what was chosen stays, what was not follows its default
    let after = sessionList(reply(session("c", "review", status: "running"), session("b", "fix", status: "finished"), session("a", "ship", status: "finished"))).sections
    #expect(after.map { folds.isOpen($0) } == [true, false, true])

    folds.toggle(after[0])
    #expect(folds.isOpen(after[0]) == false)
}

// MARK: what the poller is asked for

@Test func theOpenRunningSessionIsFollowedAndTheOthersCountedOnce() {
    let ref = EpicRef(repo: "acme/web", issue: 12)
    var data = EpicData()
    data.sessions = reply(session("c", "fix", status: "running"), session("b", "review", status: "finished"), session("a", "ship", status: "failed"))
    var folds = SessionFolds()
    let focus = epicFocus(ref, running: true, data: data, folds: folds)
    #expect(focus.transcript == "c" && focus.counting == ["b", "a"])

    // folded: not followed
    folds.toggle(sessionList(data.sessions).sections.last!)
    #expect(epicFocus(ref, running: true, data: data, folds: folds).transcript == nil)
    #expect(epicFocus(ref, running: true, data: nil, folds: folds) == EpicFocus(epic: ref, epicRunning: true, filesTabVisible: true))
}

// MARK: loading and lazy bodies

@Test func aSessionWhoseEventsHaveNotArrivedIsLoadingAndOneWithNoEventsIsEmpty() {
    let sessions = reply(session("a", "ship", status: "finished"))
    #expect(sessionList(sessions).sections[0].body == .loading)
    #expect(sessionList(sessions, transcripts: ["a": transcript([])]).sections[0].body == .items([]))
}

@Test func theListIsLoadingUntilTheSessionsReplyArrives() {
    #expect(sessionList(nil).loaded == false)
    #expect(sessionList(SessionsReply(sessions: [])).loaded)
}

@Test func onlyTheOpenSessionsGetABodyWhenTheFoldsAreGiven() {
    let sessions = reply(session("b", "fix", status: "finished"), session("a", "ship", status: "finished"))
    let all = ["a": transcript(call(1, "x", "Read")), "b": transcript(call(1, "y", "Read"))]
    #expect(sessionList(sessions, transcripts: all).sections.map(\.body) != [.items([]), .items([])])
    var folds = SessionFolds()
    let list = sessionList(sessions, transcripts: all, folds: folds)
    #expect(list.sections[0].body == .items([]))
    #expect(list.sections[1].body != .items([]))
    folds.toggle(list.sections[0])
    #expect(sessionList(sessions, transcripts: all, folds: folds).sections[0].body != .items([]))
}

// MARK: the result card

@Test func aCompletedResultShowsTheCIVerdictAndNotTheSummary() {
    let result = SessionResult(outcome: "completed", summary: "Built it.", verification: .init(ci: "passed", evidence: "Run 12 succeeded."), reason: nil)
    #expect(resultCard(result) == ResultCard(outcome: "Completed", tone: .good, ci: .init(verdict: "passed", evidence: "Run 12 succeeded."), reason: nil))
    let absent = SessionResult(outcome: "completed", summary: "Built it.", verification: .init(ci: "absent", evidence: "No CI configured."), reason: nil)
    #expect(resultCard(absent)?.ci == .init(verdict: "absent", evidence: "No CI configured."))
    #expect(resultCard(result)?.hasDetails == true)
}

@Test func theResultRowOpensOnlyWhenThereIsEvidenceAndSaysSo() {
    let stop = resultCard(SessionResult(outcome: "needs_human", summary: "s", verification: nil, reason: "Which?"))!
    #expect(stop.hasDetails == false)
    #expect(resultAccessibilityLabel(stop, open: false) == "Needs a human")
    let done = resultCard(SessionResult(outcome: "completed", summary: "s", verification: .init(ci: "passed", evidence: "e"), reason: nil))!
    #expect(resultAccessibilityLabel(done, open: false) == "Completed, CI passed, closed")
    #expect(resultAccessibilityLabel(done, open: true) == "Completed, CI passed, open")
    let list = sessionList(reply(session("a", "ship", status: "finished", until: 5)))
    var folds = SessionFolds()
    #expect(folds.isResultOpen(list.sections[0]) == false)
    folds.toggleResult(list.sections[0])
    #expect(folds.isResultOpen(list.sections[0]))
}

@Test func aStoppedResultShowsItsReasonAndNoCILine() {
    let result = SessionResult(outcome: "needs_human", summary: "Stopped.", verification: nil, reason: "Which of the two wins?")
    #expect(resultCard(result) == ResultCard(outcome: "Needs a human", tone: .stop, ci: nil, reason: "Which of the two wins?"))
}

@Test func aReviewThatAsksForChangesHasNeitherCIOrReason() {
    let result = SessionResult(outcome: "changes_requested", summary: "Two blockers.", verification: nil, reason: "ignored")
    #expect(resultCard(result) == ResultCard(outcome: "Changes requested", tone: .warning, ci: nil, reason: nil))
}

@Test func anOutcomeAddedLaterStillGetsALabel() {
    #expect(resultCard(SessionResult(outcome: "gave_up", summary: "s"))?.outcome == "Gave Up")
}

@Test func noResultMeansNoCard() {
    #expect(resultCard(nil) == nil)
    let list = sessionList(reply(session("a", "ship", status: "finished", until: 5)))
    #expect(list.sections[0].result == nil)
}

@Test func theSessionSectionCarriesItsCard() {
    var done = session("a", "review", round: 1, status: "finished", until: 5)
    done.result = SessionResult(outcome: "completed", summary: "Approved.", verification: .init(ci: "passed", evidence: "ok"), reason: nil)
    #expect(sessionList(reply(done)).sections[0].result?.outcome == "Completed")
}

@Test func onlyWebAddressesInTheTextBecomeLinks() {
    let text = linkedText("Review at https://github.com/acme/web/pull/1#r. See also ftp://host/file and mailto:a@b.co.")
    let links = text.runs.compactMap(\.link)
    #expect(links == [URL(string: "https://github.com/acme/web/pull/1#r")!])
    #expect(String(text.characters) == "Review at https://github.com/acme/web/pull/1#r. See also ftp://host/file and mailto:a@b.co.")
}

@Test func anAgentsMessageShowsItsMarkdown() {
    let blocks = markdownBlocks("**no blockers**, see `a.ts`.\n\n\n- one\n  - two\n## Next\nhttps://github.com/acme/web/pull/1 and [x](javascript:alert(1)) and [ok](https://a.co)\n")
    func text(_ block: MarkdownBlock) -> String {
        switch block {
        case .line(let line), .bullet(_, let line): String(line.characters)
        case .gap: "·"
        }
    }
    #expect(blocks.map(text) == ["no blockers, see a.ts.", "·", "one", "two", "Next", "https://github.com/acme/web/pull/1 and x and ok"])
    guard case .line(let first) = blocks[0], case .bullet(let level, _) = blocks[3], case .line(let last) = blocks[5] else {
        Issue.record("the blocks are not a line, a gap, bullets and a last line")
        return
    }
    #expect(level == 1)
    #expect(first.runs.contains { $0.inlinePresentationIntent == .stronglyEmphasized && String(first.characters[$0.range]) == "no blockers" })
    #expect(first.runs.contains { $0.inlinePresentationIntent == .code && String(first.characters[$0.range]) == "a.ts" })
    #expect(last.runs.compactMap(\.link) == [URL(string: "https://github.com/acme/web/pull/1")!, URL(string: "https://a.co")!])
}

// MARK: the flow of a session's rows

private func timed(_ id: Int, _ tool: String, arg: String = "x", ms: Int = 100, status: String = "ok", ended: Bool = true) -> [ExecEvent] {
    let callId = "c\(id)"
    let start = ExecEvent(id: id, at: id, kind: "tool_start", callId: callId, tool: tool, arg: arg)
    return ended ? [start, ExecEvent(id: id + 1, at: id, kind: "tool_end", callId: callId, tool: tool, status: status, durationMs: ms)] : [start]
}

private func say(_ id: Int) -> [ExecEvent] { [ExecEvent(id: id, at: id, kind: "say", text: "hi")] }

/// The shape of a section's rows: `i` an item, `g3` a group of three calls.
private func shape(_ events: [ExecEvent]) -> [String] {
    let sessions = reply(session("x", "ship", status: "running"))
    guard case .items(let flow) = sessionList(sessions, transcripts: ["x": transcript(events)]).sections[0].body else { return ["tail"] }
    return flow.map { if case .group(_, let calls) = $0 { "g\(calls.count)" } else { "i" } }
}

private func group(_ events: [ExecEvent]) -> (id: Int, calls: [TranscriptItem])? {
    let sessions = reply(session("x", "ship", status: "running"))
    guard case .items(let flow) = sessionList(sessions, transcripts: ["x": transcript(events)]).sections[0].body else { return nil }
    for item in flow { if case .group(let id, let calls) = item { return (id, calls) } }
    return nil
}

@Test func aRunOfThreeSuccessfulCallsIsOneGroupAndARunOfOneIsALine() {
    #expect(shape(timed(1, "Bash") + timed(3, "Read") + timed(5, "Grep")) == ["g3"])
    #expect(shape(say(1) + timed(2, "Bash") + say(4)) == ["i", "i", "i"])
    #expect(shape(timed(1, "Bash") + timed(3, "Bash")) == ["g2"])
}

@Test func aFailureAMessageASkillOrAnEditEndsTheRun() {
    let run = timed(1, "Bash") + timed(3, "Bash") + timed(5, "Bash", status: "err") + timed(7, "Read") + timed(9, "Read")
    #expect(shape(run) == ["g2", "i", "g2"])
    #expect(shape(timed(1, "Bash") + timed(3, "Bash") + say(5) + timed(6, "Bash") + timed(8, "Bash")) == ["g2", "i", "g2"])
    #expect(shape(timed(1, "Bash") + timed(3, "Bash") + timed(5, "Skill") + timed(7, "Bash") + timed(9, "Bash") + timed(11, "Edit") + timed(13, "Bash")) == ["g2", "i", "g2", "i", "i"])
}

@Test func aPendingCallIsALineAfterTheGroupAndJoinsItOnceItEndsWell() {
    let pending = timed(1, "Bash") + timed(3, "Bash") + timed(5, "Bash", ended: false)
    #expect(shape(pending) == ["g2", "i"])
    let ended = pending + [ExecEvent(id: 6, at: 6, kind: "tool_end", callId: "c5", tool: "Bash", status: "ok", durationMs: 100)]
    #expect(shape(ended) == ["g3"])
    #expect(group(ended)?.id == 1)
    // ended badly, it stays a line
    let failed = pending + [ExecEvent(id: 6, at: 6, kind: "tool_end", callId: "c5", tool: "Bash", status: "err")]
    #expect(shape(failed) == ["g2", "i"])
}

@Test func aGroupKeepsItsIdWhenCallsAreAppendedAndTheTranscriptIsNotRebuilt() {
    var live = Transcript()
    func apply(_ events: [ExecEvent]) { live.apply(EventsReply(events: events, next: events.last?.id ?? 0, running: true, structured: true)) }
    func firstGroup() -> Int? {
        guard case .items(let flow) = transcriptBody(live) else { return nil }
        for item in flow { if case .group(let id, _) = item { return id } }
        return nil
    }
    apply(timed(10, "Bash") + timed(12, "Read"))
    #expect(firstGroup() == 10)
    let before = live.work
    apply(timed(14, "Grep"))
    #expect(firstGroup() == 10)
    #expect(live.work - before == 2)
}

@Test func aGroupsLabelCountsByKindInFirstCallOrderAndItsDurationIsTheSum() {
    func label(_ events: [ExecEvent]) -> String? { group(events).map { callGroupLabel($0.calls) } }
    let events = timed(1, "Bash", ms: 1000) + timed(3, "Bash", ms: 2000) + timed(5, "Bash", ms: 3000) + timed(7, "Read", ms: 100)
    #expect(label(events) == "Ran 3 commands · read 1 file")
    #expect(group(events).flatMap { callGroupDuration($0.calls) } == "6.1 s")
    #expect(label(timed(1, "Read") + timed(3, "Grep")) == "Read 1 file · searched 1 time")
    #expect(label(timed(1, "Grep") + timed(3, "Grep")) == "Searched 2 times")
    #expect(label(timed(1, "WebFetch") + timed(3, "WebFetch")) == "Used 2 tools")
    #expect(label(timed(1, "Bash") + timed(3, "Read") + timed(5, "Grep") + timed(7, "WebFetch") + timed(9, "Grep")) == "Ran 1 command · read 1 file · +3 more")
}

@Test func aHarnessWithNoParserKeepsItsTail() {
    var plain = Transcript()
    plain.apply(EventsReply(events: [], next: 0, running: true, structured: false))
    plain.tail = ["ran tests"]
    let sessions = reply(session("x", "ship", status: "running", harness: "codex"))
    #expect(sessionList(sessions, transcripts: ["x": plain]).sections[0].body == .tail(["ran tests"]))
}
