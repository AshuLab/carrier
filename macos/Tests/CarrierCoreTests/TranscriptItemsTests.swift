import Foundation
import Testing
@testable import CarrierCore

private func start(_ id: Int, _ call: String, _ tool: String, arg: String = "x") -> ExecEvent {
    ExecEvent(id: id, at: id, kind: "tool_start", callId: call, tool: tool, arg: arg)
}

private func end(_ id: Int, _ call: String, _ tool: String, status: String = "ok", ms: Int? = 80, summary: String = "done") -> ExecEvent {
    ExecEvent(id: id, at: id, kind: "tool_end", callId: call, tool: tool, summary: summary, status: status, durationMs: ms)
}

private func card(_ item: TranscriptItem) -> ToolCall? {
    if case .tool(_, let call) = item { return call }
    return nil
}

@Test func aCallAndItsEndBecomeOneCardBetweenTheMessages() {
    let items = transcriptItems([
        ExecEvent(id: 1, at: 1, kind: "say", text: "reading"), start(2, "a", "Read", arg: "src/a.ts"), end(3, "a", "Read", summary: "212 lines"),
        ExecEvent(id: 4, at: 4, kind: "say", text: "done"),
    ])
    #expect(items.map(\.id) == [1, 2, 4])
    let read = card(items[1])
    #expect(read?.tool == "Read" && read?.kind == .read && read?.arg == "src/a.ts")
    // what the engine counted: its output is only the first and last lines
    #expect(read?.status == .ok && read?.result == "212 lines" && read?.durationMs == 80)
}

@Test func aCallWithoutItsEndIsPendingAndHasNoDuration() {
    let item = card(transcriptItems([start(1, "a", "Bash", arg: "pnpm test")])[0])
    #expect(item?.status == .running)
    #expect(item?.durationMs == nil)
    #expect(item?.arg == "pnpm test")
}

@Test func anEndThatArrivesBeforeItsStartStillMakesOneCard() {
    let items = transcriptItems([end(1, "a", "Grep"), start(2, "a", "Grep", arg: "token")])
    #expect(items.count == 1)
    #expect(items[0].id == 1)
    #expect(card(items[0])?.status == .ok)
    #expect(card(items[0])?.arg == "token")
}

@Test func theSameEventTwiceChangesNothing() {
    let events = [start(1, "a", "Read"), end(2, "a", "Read"), ExecEvent(id: 3, at: 3, kind: "say", text: "hi")]
    #expect(transcriptItems(events + events) == transcriptItems(events))
    #expect(transcriptItems(events + events).count == 2)
}

@Test func eventsOutOfOrderByIdAreMergedInIdOrder() {
    let items = transcriptItems([ExecEvent(id: 4, at: 4, kind: "say", text: "last"), end(3, "a", "Edit"), start(2, "a", "Edit"), ExecEvent(id: 1, at: 1, kind: "note", text: "first")])
    #expect(items.map(\.id) == [1, 2, 4])
}

@Test func anUnknownToolGetsTheGenericIconAndNoNameIsLost() {
    let item = card(transcriptItems([start(1, "a", "FutureTool"), end(2, "a", "FutureTool")])[0])
    #expect(item?.tool == "FutureTool")
    #expect(item?.kind.icon == "wrench.and.screwdriver")
}

@Test func notesAndErrorsArePlainItemsAndUnknownKindsAreLeftOut() {
    let items = transcriptItems([
        ExecEvent(id: 1, at: 1, kind: "note", text: "resumed"), ExecEvent(id: 2, at: 2, kind: "error", text: "boom"),
        ExecEvent(id: 3, at: 3, kind: "task"), ExecEvent(id: 4, at: 4, kind: "future_kind"),
    ])
    #expect(items == [.note(id: 1, text: "resumed"), .error(id: 2, text: "boom")])
}

@Test func eachToolHasItsIconAndEachCallItsStatus() {
    #expect(["Read", "Grep", "Edit", "Bash", "Nope"].map { ToolKind(tool: $0).icon } == ["doc.text", "magnifyingglass", "pencil", "terminal", "wrench.and.screwdriver"])
    #expect(["Write", "MultiEdit"].map { ToolKind(tool: $0).icon } == ["pencil", "pencil"])
    #expect(["shell", "exec_command"].map { ToolKind(tool: $0).icon } == ["terminal", "terminal"])
    #expect(ToolKind(tool: nil).icon == "wrench.and.screwdriver")
    #expect(ToolStatus.ok.icon == "checkmark.circle.fill")
    #expect(ToolStatus.error.icon == "xmark.circle.fill")
    #expect(ToolStatus.pending.icon == nil)

    let cards = transcriptItems([start(1, "a", "Bash"), end(2, "a", "Bash", status: "err"), start(3, "b", "Read"), end(4, "b", "Read"), start(5, "c", "Edit")]).compactMap(card)
    #expect(cards.map(\.status) == [.failed, .ok, .running])
}

@Test func aHarnessWithoutEventsShowsItsTailLines() {
    var transcript = Transcript()
    transcript.apply(EventsReply(events: [], next: 0, running: true, structured: false))
    transcript.tail = ["ran tests", "edited a.ts"]
    #expect(transcriptBody(transcript) == .tail(["ran tests", "edited a.ts"]))

    var structured = Transcript()
    structured.apply(EventsReply(events: [ExecEvent(id: 1, at: 1, kind: "say", text: "hi")], next: 1, running: true, structured: true))
    structured.tail = ["ignored"]
    #expect(transcriptBody(structured) == .items([.message(id: 1, text: "hi")]))
    #expect(transcriptBody(nil) == .loading)
}

@Test func durationsInMillisecondsSecondsAndMinutes() {
    #expect(formatCallDuration(0) == "0 ms")
    #expect(formatCallDuration(340) == "340 ms")
    #expect(formatCallDuration(999) == "999 ms")
    #expect(formatCallDuration(1000) == "1 s")
    #expect(formatCallDuration(6240) == "6 s")
    #expect(formatCallDuration(59_999) == "59 s")
    #expect(formatCallDuration(60_000) == "1m 00s")
    #expect(formatCallDuration(125_000) == "2m 05s")
}

// MARK: diffs

private func lines(_ pairs: [(String, String)]) -> [ExecEvent.DiffLine] { pairs.map { .init(sign: $0.0, text: $0.1) } }

@Test func aDiffBecomesAddedRemovedAndContextLines() {
    let diff = cardDiff(lines([(" ", "const ttl = 60;"), ("-", "old"), ("+", "new"), ("+", "newer"), ("?", "odd sign")]))
    #expect(diff?.rows.map(\.sign) == [.context, .removed, .added, .added, .context])
    #expect(diff?.rows.map(\.text) == ["const ttl = 60;", "old", "new", "newer", "odd sign"])
    #expect(diff?.added == 2)
    #expect(diff?.removed == 1)
}

@Test func aDiffWithOnlyAdditionsHasNothingRemoved() {
    let diff = cardDiff(lines([("+", "a"), ("+", "b"), ("+", "c")]))
    #expect(diff?.rows.allSatisfy { $0.sign == .added } == true)
    #expect(diff?.added == 3)
    #expect(diff?.removed == 0)
}

@Test func aVeryLongLineIsCutAndAShortOneIsLeftAlone() {
    let long = String(repeating: "x", count: 1_000_000)
    let diff = cardDiff(lines([("+", long), ("+", String(repeating: "y", count: maxDiffLineLength))]))
    #expect(diff?.rows[0].text.count == maxDiffLineLength + 1)
    #expect(diff?.rows[0].text.hasSuffix("…") == true)
    #expect(diff?.rows[1].text.count == maxDiffLineLength)
    #expect(diff?.added == 2)
}

@Test func anEmptyOrMissingDiffIsNoDiff() {
    #expect(cardDiff([]) == nil)
    #expect(cardDiff(nil) == nil)
    let edit = ExecEvent(id: 2, at: 2, kind: "tool_end", callId: "a", tool: "Edit", status: "ok", diff: [])
    #expect(card(transcriptItems([start(1, "a", "Edit"), edit])[0])?.diff.isEmpty == true)
}

@Test func anEditCallCarriesItsDiff() {
    let edit = ExecEvent(id: 2, at: 2, kind: "tool_end", callId: "a", tool: "Edit", status: "ok", diff: lines([("-", "a"), ("+", "b")]))
    let call = card(transcriptItems([start(1, "a", "Edit"), edit])[0])
    #expect(call?.diff == [DiffRow(sign: .removed, text: "a"), DiffRow(sign: .added, text: "b")])
    #expect(call?.added == 1 && call?.removed == 1 && call?.result == "+1 −1")
}

// MARK: failures

@Test func aFailedCallWithNoOutputSaysWhyInTheEnginesWordsAndAFailedEditShowsNoDiff() {
    func failed(_ tool: String, summary: String, output: [String]? = nil, diff: [ExecEvent.DiffLine]? = nil) -> ToolCall? {
        let end = ExecEvent(id: 2, at: 2, kind: "tool_end", callId: "a", tool: tool, summary: summary, status: "err", output: output, diff: diff)
        return card(transcriptItems([start(1, "a", tool), end])[0])
    }
    #expect(failed("Edit", summary: "File modified since it was read.", diff: lines([("+", "x")]))?.output == ["File modified since it was read."])
    #expect(failed("Edit", summary: "File modified since it was read.", diff: lines([("+", "x")]))?.diff.isEmpty == true)
    #expect(failed("Bash", summary: "2 failed", output: ["Exit code 1", "boom"])?.output == ["Exit code 1", "boom"])
    #expect(failed("Bash", summary: "")?.output == [])
    #expect(failed("Bash", summary: "2 failed")?.result == "failed")
}

@Test func aDurationTheEngineGaveIsTheCallsAndWithoutOneTheEventsTimesAre() {
    let timed = card(transcriptItems([start(1, "a", "Bash"), end(2, "a", "Bash", ms: 7_000)])[0])
    #expect(timed?.durationMs == 7_000)
    let untimed = card(transcriptItems([start(10, "a", "Bash"), end(30, "a", "Bash", ms: nil)])[0])
    #expect(untimed?.durationMs == 20)
}

private func shell(_ id: Int, _ call: String, status: String, output: [String]?) -> [ExecEvent] {
    [start(id, call, "Bash"), ExecEvent(id: id + 1, at: id, kind: "tool_end", callId: call, tool: "Bash", status: status, output: output)]
}

@Test func hiddenToolsLeaveTheFlowWithNoCallAndNoSkillAndKeepTheRest() {
    let events = [ExecEvent(id: 1, at: 1, kind: "say", text: "reading")] + shell(2, "a", status: "ok", output: ["x"]) + shell(4, "b", status: "ok", output: ["y"])
        + [ExecEvent(id: 6, at: 6, kind: "say", text: "done")] + shell(7, "c", status: "err", output: ["boom"])
        + [start(9, "s", "Skill", arg: "solve:ship"), ExecEvent(id: 10, at: 10, kind: "note", text: "created 736")]
    let flow = flowItems(transcriptItems(events))
    #expect(flow.map(\.id) == [1, 2, 6, 7, 9, 10])
    #expect(visibleFlow(flow, mode: .hidden).map(\.id) == [1, 6, 10])
    #expect(visibleFlow(flow, mode: .collapsed) == flow && visibleFlow(flow, mode: .expanded) == flow)
}

@Test func theReasoningSettingTakesTheThoughtsOutOfARunAndAThoughtOnlyRunGoes() {
    let thought = ExecEvent(id: 1, at: 1, kind: "reasoning", text: "\n  Check the floor first.\n")
    let flow = flowItems(transcriptItems([thought] + shell(2, "a", status: "ok", output: nil) + [ExecEvent(id: 4, at: 4, kind: "say", text: "hi"), ExecEvent(id: 5, at: 5, kind: "reasoning", text: "more")]))
    #expect(flow.map(\.id) == [1, 4, 5])
    guard case .tools(_, let run, _) = flow[0] else {
        Issue.record("the thought and the call are one run")
        return
    }
    #expect(run.thoughts.map(\.text) == ["Check the floor first."] && run.calls.count == 1 && run.thoughts[0].before == 0)
    let quiet = visibleFlow(flow, mode: .collapsed, showsReasoning: false)
    #expect(quiet.map(\.id) == [1, 4])
    guard case .tools(_, let calls, _) = quiet[0] else {
        Issue.record("the run keeps its call")
        return
    }
    #expect(calls.thoughts.isEmpty && calls.calls.count == 1)
}

@Test func aSliceRowIsClosedUntilTheUserOpensItAndTheChoiceIsKeptPerSubagent() {
    var folds = SliceFolds()
    #expect(folds.isOpen("a") == false)
    folds.toggle("a")
    #expect(folds.isOpen("a"))
    #expect(folds.isOpen("b") == false)
    folds.toggle("a")
    #expect(folds.isOpen("a") == false)
}

// MARK: long transcripts

private func reply(_ events: [ExecEvent]) -> EventsReply { EventsReply(events: events, next: events.last?.id ?? 0, running: true, structured: true) }

@Test func fiveThousandEventsMergeInUnderASecond() {
    let events = longTranscriptEvents(rounds: 556)
    #expect(events.count >= 5_000)
    let clock = ContinuousClock()
    var whole = Transcript()
    let atOnce = clock.measure { whole.apply(reply(events)) }
    #expect(atOnce < .seconds(1))
    // the way it really arrives: a few events a second, for as long as the session runs
    var piecemeal = Transcript()
    let oneByOne = clock.measure { for event in events { piecemeal.apply(reply([event])) } }
    #expect(oneByOne < .seconds(1))
    #expect(whole.items == piecemeal.items)
    #expect(whole.items.count == 556 * 5)
}

@Test func anAppendProcessesOnlyTheNewEvent() {
    var transcript = Transcript()
    transcript.apply(reply(longTranscriptEvents(rounds: 100)))
    let before = transcript.work
    #expect(before == 900)

    transcript.apply(reply([ExecEvent(id: 901, at: 1, kind: "say", text: "more")]))
    #expect(transcript.work - before == 1)
    #expect(transcript.items.count == 501)

    // a repeated reply is not processed at all
    transcript.apply(reply([ExecEvent(id: 901, at: 1, kind: "say", text: "more")]))
    #expect(transcript.work - before == 1)

    // the end of a call changes its own card, not the list
    transcript.apply(reply([start(902, "z", "Read"), end(903, "z", "Read")]))
    #expect(transcript.work - before == 3)
    #expect(transcript.items.count == 502)
}

@Test func anEventOlderThanTheNewestRebuildsAndKeepsTheOrder() {
    var transcript = Transcript()
    transcript.apply(reply([ExecEvent(id: 5, at: 5, kind: "say", text: "later")]))
    transcript.apply(reply([ExecEvent(id: 2, at: 2, kind: "say", text: "earlier")]))
    #expect(transcript.items.map(\.id) == [2, 5])
}

private func rows(_ spec: String) -> [DiffRow] {
    spec.map { c in
        switch c {
        case "+": DiffRow(sign: .added, text: "a")
        case "-": DiffRow(sign: .removed, text: "r")
        case "@": DiffRow(sign: .hunk, text: "@@")
        default: DiffRow(sign: .context, text: "c")
        }
    }
}

private func shape(_ pairs: [DiffPair]) -> [String] {
    pairs.map { p in
        func mark(_ row: DiffRow?) -> String { row.map { $0.sign == .removed ? "-" : $0.sign == .added ? "+" : $0.sign == .hunk ? "@" : "=" } ?? "_" }
        return mark(p.left) + mark(p.right)
    }
}

@Test func aPureAdditionIsAddedLinesWithNothingOnTheLeft() {
    #expect(shape(splitDiffPairs(rows("++"))) == ["_+", "_+"])
}

@Test func aPureRemovalIsRemovedLinesWithNothingOnTheRight() {
    #expect(shape(splitDiffPairs(rows("--"))) == ["-_", "-_"])
}

@Test func aChangedBlockWithMoreRemovedThanAddedLeavesTheRightEmptyAtTheEnd() {
    #expect(shape(splitDiffPairs(rows("---+"))) == ["-+", "-_", "-_"])
}

@Test func aChangedBlockWithMoreAddedThanRemovedLeavesTheLeftEmptyAtTheEnd() {
    #expect(shape(splitDiffPairs(rows("-+++"))) == ["-+", "_+", "_+"])
}

@Test func contextAndHunkLinesFillBothSidesAndEndABlock() {
    #expect(shape(splitDiffPairs(rows("@=-+=+"))) == ["@@", "==", "-+", "==", "_+"])
    #expect(splitDiffPairs([]).isEmpty)
}

@Test(arguments: [(30, 30, 0), (31, 30, 1), (100, 30, 70)])
func aDiffIsCutAtThirtyRowsAndSaysHowManyAreLeftOut(rows: Int, shown: Int, hidden: Int) {
    let diff = (0..<rows).map { DiffRow(sign: .added, text: "line \($0)") }
    let cut = visibleDiffRows(diff, expanded: false)
    #expect(cut.rows.count == shown && cut.hidden == hidden)
    // opened, every row
    #expect(visibleDiffRows(diff, expanded: true).rows.count == rows)
    #expect(visibleDiffRows(diff, expanded: true).hidden == 0)
}
