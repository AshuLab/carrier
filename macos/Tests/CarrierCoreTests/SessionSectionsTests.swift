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
    #expect(countsRuns(SessionCounts(calls: 8, edits: 2, added: 42, removed: 8, tests: 1, errors: 2)).filter { $0.tone != .plain }
        == [CountRun(text: "+42", tone: .added), CountRun(text: "−8", tone: .removed), CountRun(text: "2 errors", tone: .error)])
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

@Test func aRunningSessionIsOpenAndWearsTheRingAndTheFinishedOnesBelowAreFolded() {
    let list = sessionList(reply(
        session("c", "fix", round: 2, status: "running", at: 90_000),
        session("b", "review", round: 2, status: "finished", harness: "codex", at: 60_000, until: 85_000),
        session("a", "ship", status: "finished", at: 1000, until: 39_000)
    ), timeZone: TimeZone(identifier: "UTC")!)
    #expect(list.sections.map(\.id) == ["c", "b", "a"])
    #expect(list.sections.map(\.state) == [.running, .done, .done])
    #expect(list.sections.map(\.openByDefault) == [true, false, false])
    #expect(list.sections.map(\.agent) == ["Claude", "Codex", "Claude"])
    #expect(list.sections.map(\.initial) == ["C", "X", "C"])
    #expect(list.sections.map(\.role) == ["Fixer", "Reviewer", "Builder"])
    #expect(list.sections.map(\.place) == ["Round 2", "Round 2", "Ship"])
    #expect(list.sections.map(\.timeLabel) == ["since 00:01", "25s", "38s"])
    #expect(list.earlier == nil)
}

@Test func aStoppedSessionIsOpenHasTheBadgeStateAndNoTime() {
    for status in ["failed", "timed_out", "interrupted", "invalid_result"] {
        let list = sessionList(reply(session("b", "fix", round: 1, status: status), session("a", "ship", status: "finished", until: 5)))
        #expect(list.sections.map(\.state) == [.stopped, .done])
        #expect(list.sections.map(\.openByDefault) == [true, false])
        #expect(list.sections[0].timeLabel == nil)
    }
}

@Test func whenEverySessionIsFinishedTheNewestIsOpen() {
    let list = sessionList(reply(session("c", "review", round: 1, status: "finished"), session("b", "ship", status: "finished")))
    #expect(list.sections.map(\.openByDefault) == [true, false])
}

@Test func aShipSessionIsTheBuilderAndHasNoRound() {
    let section = sessionList(reply(session("a", "ship", status: "running"))).sections[0]
    #expect((section.role, section.place, section.state, section.openByDefault) == ("Builder", "Ship", .running, true))
}

@Test func theLineUnderTheListCountsTheSessionsThatAreNotShown() {
    func many(_ n: Int) -> SessionsReply { SessionsReply(sessions: (0..<n).map { session("s\($0)", "fix", round: $0, status: "finished") }) }
    #expect(sessionList(many(3)).earlier == nil)
    #expect(sessionList(many(4)).earlier == "1 earlier session")
    let long = sessionList(many(8))
    #expect(long.sections.count == 3 && long.earlier == "5 earlier sessions")
    #expect(sessionList(nil).sections.isEmpty && sessionList(nil).earlier == nil)
}

@Test func theCountsAreThereOnlyWhenTheEventsAreAndTheHarnessHasAParser() {
    let sessions = reply(session("c", "fix", status: "running"), session("b", "review", status: "finished", harness: "codex"), session("a", "ship", status: "finished"))
    let list = sessionList(sessions, transcripts: [
        "c": transcript(call(1, "a", "Read") + call(3, "b", "Read")),
        "b": transcript(call(1, "a", "Read"), structured: false),
    ])
    #expect(list.sections.map(\.counts) == ["2 tool calls", nil, nil])
}

@Test func anEmptyTranscriptShowsZeroToolCalls() {
    let list = sessionList(reply(session("c", "fix", status: "running")), transcripts: ["c": transcript([])])
    #expect(list.sections[0].counts == "0 tool calls")
}

// MARK: folding

@Test func foldingAndUnfoldingASectionIsKeptWhateverTheRepliesDoAfterwards() {
    let before = sessionList(reply(session("b", "fix", status: "running"), session("a", "ship", status: "finished"))).sections
    var folds = SessionFolds()
    #expect(before.map { folds.isOpen($0) } == [true, false])

    folds.toggle(before[0])
    folds.toggle(before[1])
    #expect(before.map { folds.isOpen($0) } == [false, true])

    // the running one stops and a new one arrives: what was chosen stays, what was not follows its default
    let after = sessionList(reply(session("c", "review", status: "running"), session("b", "fix", status: "finished"), session("a", "ship", status: "finished"))).sections
    #expect(after.map { folds.isOpen($0) } == [true, false, true])

    folds.toggle(after[2])
    #expect(folds.isOpen(after[2]) == false)
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
    folds.toggle(sessionList(data.sessions).sections[0])
    #expect(epicFocus(ref, running: true, data: data, folds: folds).transcript == nil)
    #expect(epicFocus(ref, running: true, data: nil, folds: folds) == EpicFocus(epic: ref, epicRunning: true))
}
