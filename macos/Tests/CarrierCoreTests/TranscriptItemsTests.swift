import Foundation
import Testing
@testable import CarrierCore

private func start(_ id: Int, _ call: String, _ tool: String, arg: String = "x") -> ExecEvent {
    ExecEvent(id: id, at: id, kind: "tool_start", callId: call, tool: tool, arg: arg)
}

private func end(_ id: Int, _ call: String, _ tool: String, status: String = "ok", ms: Int? = 80, summary: String = "done") -> ExecEvent {
    ExecEvent(id: id, at: id, kind: "tool_end", callId: call, tool: tool, summary: summary, status: status, durationMs: ms)
}

private func card(_ item: TranscriptItem) -> TranscriptCard? {
    if case .tool(_, let card) = item { return card }
    return nil
}

@Test func aCallAndItsEndBecomeOneCardBetweenTheMessages() {
    let items = transcriptItems([
        ExecEvent(id: 1, at: 1, kind: "say", text: "reading"), start(2, "a", "Read", arg: "src/a.ts"), end(3, "a", "Read", summary: "212 lines"),
        ExecEvent(id: 4, at: 4, kind: "say", text: "done"),
    ])
    #expect(items.map(\.id) == [1, 2, 4])
    #expect(card(items[1]) == TranscriptCard(tool: "Read", kind: .read, arg: "src/a.ts", summary: "212 lines", status: .ok, duration: "80 ms", durationMs: 80))
}

@Test func aCallWithoutItsEndIsPendingAndHasNoDuration() {
    let item = card(transcriptItems([start(1, "a", "Bash", arg: "pnpm test")])[0])
    #expect(item?.status == .pending)
    #expect(item?.duration == nil)
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

@Test func eachToolHasItsIconAndEachStatusItsMark() {
    #expect(["Read", "Grep", "Edit", "Bash", "Nope"].map { ToolKind(tool: $0).icon } == ["doc.text", "magnifyingglass", "pencil", "terminal", "wrench.and.screwdriver"])
    #expect(["Write", "MultiEdit"].map { ToolKind(tool: $0).icon } == ["pencil", "pencil"])
    #expect(["shell", "exec_command"].map { ToolKind(tool: $0).icon } == ["terminal", "terminal"])
    #expect(ToolKind(tool: nil).icon == "wrench.and.screwdriver")
    #expect(ToolStatus.ok.icon == "checkmark.circle.fill")
    #expect(ToolStatus.error.icon == "xmark.circle.fill")
    #expect(ToolStatus.pending.icon == nil)

    let cards = transcriptItems([start(1, "a", "Bash"), end(2, "a", "Bash", status: "err"), start(3, "b", "Read"), end(4, "b", "Read"), start(5, "c", "Edit")]).compactMap(card)
    #expect(cards.map(\.status) == [.error, .ok, .pending])
}

@Test func aHarnessWithoutEventsShowsItsTailLines() {
    var transcript = Transcript()
    transcript.apply(EventsReply(events: [], next: 0, running: true, structured: false))
    transcript.tail = ["ran tests", "edited a.ts"]
    #expect(transcriptBody(transcript) == .tail(["ran tests", "edited a.ts"]))

    var structured = Transcript()
    structured.apply(EventsReply(events: [ExecEvent(id: 1, at: 1, kind: "say", text: "hi")], next: 1, running: true, structured: true))
    structured.tail = ["ignored"]
    #expect(transcriptBody(structured) == .items([.item(.message(id: 1, text: "hi"))]))
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
    #expect(card(transcriptItems([start(1, "a", "Edit"), edit])[0])?.diff == nil)
}

@Test func anEditCardCarriesItsDiff() {
    let edit = ExecEvent(id: 2, at: 2, kind: "tool_end", callId: "a", tool: "Edit", status: "ok", diff: lines([("-", "a"), ("+", "b")]))
    let diff = card(transcriptItems([start(1, "a", "Edit"), edit])[0])?.diff
    #expect(diff == CardDiff(rows: [DiffRow(sign: .removed, text: "a"), DiffRow(sign: .added, text: "b")], added: 1, removed: 1))
}

// MARK: edit headers

private func editCard(_ path: String, status: String = "ok", summary: String = "The file has been updated successfully.", diff: [ExecEvent.DiffLine]? = nil) -> TranscriptCard {
    let end = ExecEvent(id: 2, at: 2, kind: "tool_end", callId: "a", tool: "Edit", summary: summary, status: status, durationMs: 80, diff: diff)
    return card(transcriptItems([start(1, "a", "Edit", arg: path), end])[0])!
}

@Test(arguments: [
    ("/Users/x/.solve/worktrees/carrier/the-slices-tab--lane-1/src/orchestration/engine.ts", "engine.ts", "src/orchestration"),
    ("/Users/x/.solve/worktrees/carrier/lane-1/README.md", "README.md", ""),
    ("/Users/x/other/repo/src/execution/fake.ts", "fake.ts", "…/src/execution"),
    ("/tmp/notes.md", "notes.md", "…/tmp"),
    ("src/terminal/dashboard/panel.ts", "panel.ts", "src/terminal/dashboard"),
    ("engine.ts", "engine.ts", ""),
])
func anEditNamesItsFileAndShowsTheFolderRelativeToTheWorktree(path: String, name: String, folder: String) {
    let edit = editCard(path)
    #expect(edit.editName == name)
    #expect(edit.editFolder == folder)
}

@Test func anEditHeaderCountsComeOnceFromTheDiffAndAnEditWithoutOneHasNone() {
    let diff = lines([(" ", "keep"), ("-", "old"), ("+", "new"), ("+", "newer")])
    let counted = editCard("a.ts", diff: diff)
    #expect(counted.shownDiff?.added == 2)
    #expect(counted.shownDiff?.removed == 1)
    #expect(counted.editReason == nil)
    #expect(editCard("a.ts").shownDiff == nil)
}

@Test func aFailedEditShowsTheEngineTextAndNoDiff() {
    let failed = editCard("a.ts", status: "err", summary: "File modified since it was read.", diff: lines([("+", "x")]))
    #expect(failed.editReason == "File modified since it was read.")
    #expect(failed.shownDiff == nil)
    #expect(editCard("a.ts", status: "err", summary: "").editReason == nil)
}

@Test func aRunningEditHasNothingButItsName() {
    let running = card(transcriptItems([start(1, "a", "Edit", arg: "src/a.ts")])[0])!
    #expect(running.status == .pending)
    #expect(running.editName == "a.ts")
    #expect(running.editReason == nil)
    #expect(running.shownDiff == nil)
}

// MARK: long diffs

private func added(_ count: Int) -> [ExecEvent.DiffLine] { (1...count).map { .init(sign: "+", text: "line \($0)") } }

@Test(arguments: [(30, 30, 0), (31, 30, 1), (100, 30, 70)])
func aDiffIsCutAtThirtyRowsAndSaysHowManyAreLeftOut(rows: Int, shown: Int, hidden: Int) {
    let edit = editCard("a.ts", diff: added(rows))
    let cut = edit.visibleDiffRows(expanded: false)
    #expect(cut.rows.count == shown)
    #expect(cut.hidden == hidden)
    // the header counts are those of the whole diff
    #expect(edit.shownDiff?.added == rows)
    // once opened, every row, and the footer still has "Show less" to offer
    #expect(edit.visibleDiffRows(expanded: true).rows.count == rows)
    #expect(edit.visibleDiffRows(expanded: true).hidden == 0)
    #expect(edit.diffIsCut == (hidden > 0))
}

@Test func anEditWithNoDiffHasNoRowsToCut() {
    #expect(editCard("a.ts").visibleDiffRows(expanded: false).rows.isEmpty)
    #expect(editCard("a.ts", status: "err", diff: added(40)).visibleDiffRows(expanded: false).rows.isEmpty)
}

@Test func anEditThatOnlyAddsLinesIsNewAndOneWithARemovedOrContextRowIsNot() {
    #expect(editCard("a.ts", diff: added(4)).isNewFile)
    #expect(editCard("a.ts", diff: lines([("+", "a"), ("-", "b")])).isNewFile == false)
    #expect(editCard("a.ts", diff: lines([("+", "a"), (" ", "keep")])).isNewFile == false)
    #expect(editCard("a.ts").isNewFile == false)
    #expect(editCard("a.ts", status: "err", diff: added(2)).isNewFile == false)
}

// MARK: command output

private func shell(_ id: Int, _ call: String, status: String, output: [String]?) -> [ExecEvent] {
    [start(id, call, "Bash"), ExecEvent(id: id + 1, at: id, kind: "tool_end", callId: call, tool: "Bash", status: status, output: output)]
}

@Test func outputIsCollapsedUnlessTheCommandFailed() {
    let cards = transcriptItems(shell(1, "a", status: "ok", output: ["fine"]) + shell(3, "b", status: "err", output: ["boom"]) + [start(5, "c", "Bash")]).compactMap(card)
    #expect(cards.map(\.output) == [["fine"], ["boom"], []])
    #expect(cards.map { $0.opensByDefault(.collapsed, opensFailed: true) } == [false, true, false])
}

@Test func onlyAnExitCodeFirstLineOfAFailedCallIsTheFailureLine() {
    let cards = transcriptItems(
        shell(1, "a", status: "err", output: ["Exit code 1", "boom"]) + shell(3, "b", status: "err", output: ["fatal: not a repo", "Exit code 1"])
            + shell(5, "c", status: "ok", output: ["Exit code 1", "fine"]) + shell(7, "d", status: "err", output: [])
    ).compactMap(card)
    #expect(cards.map(\.failureLine) == ["Exit code 1", nil, nil, nil])
}

@Test func aCallWithNoOutputHasNoLineCountAndOneWithOutputCountsItsLines() {
    let cards = transcriptItems(shell(1, "a", status: "ok", output: nil) + shell(3, "b", status: "ok", output: ["one"]) + shell(5, "c", status: "ok", output: ["a", "b"])).compactMap(card)
    #expect(cards.map(\.lineCount) == [nil, "1 line", "2 lines"])
}

@Test func theUserCanOpenAndCloseAnyOutputAndItIsKeptPerCard() {
    let items = transcriptItems(shell(1, "a", status: "ok", output: ["fine"]) + shell(3, "b", status: "err", output: ["boom"]))
    let (ok, failed) = (card(items[0])!, card(items[1])!)
    var folds = OutputFolds()
    func isOpen(_ index: Int, _ card: TranscriptCard) -> Bool { folds.isOpen(items[index].id, card, mode: .collapsed, opensFailed: true) }
    #expect(isOpen(0, ok) == false)
    #expect(isOpen(1, failed))
    folds.toggle(items[0].id, ok, mode: .collapsed, opensFailed: true)
    folds.toggle(items[1].id, failed, mode: .collapsed, opensFailed: true)
    #expect(isOpen(0, ok))
    #expect(isOpen(1, failed) == false)
    folds.toggle(items[0].id, ok, mode: .collapsed, opensFailed: true)
    #expect(isOpen(0, ok) == false)
}

@Test func theToolsModeAndTheFailedSwitchSetWhichOutputsOpenByThemselves() {
    let items = transcriptItems(shell(1, "a", status: "ok", output: ["fine"]) + shell(3, "b", status: "err", output: ["boom"]))
    let (ok, failed) = (card(items[0])!, card(items[1])!)
    let folds = OutputFolds()
    func opens(_ mode: ToolOutputMode, _ opensFailed: Bool) -> [Bool] {
        [folds.isOpen(items[0].id, ok, mode: mode, opensFailed: opensFailed), folds.isOpen(items[1].id, failed, mode: mode, opensFailed: opensFailed)]
    }
    #expect(opens(.collapsed, true) == [false, true])
    #expect(opens(.collapsed, false) == [false, false])
    #expect(opens(.expanded, true) == [true, true])
    #expect(opens(.expanded, false) == [true, true])
    #expect(opens(.hidden, true) == [false, false])
}

@Test func aGroupFollowsTheModeUntilTheUserFlipsItAndTheFlipIsKeptPerGroup() {
    var folds = GroupFolds()
    #expect(folds.isOpen(1, mode: .collapsed) == false && folds.isOpen(1, mode: .expanded))
    folds.toggle(1)
    #expect(folds.isOpen(1, mode: .collapsed) && folds.isOpen(1, mode: .expanded) == false)
    #expect(folds.isOpen(2, mode: .collapsed) == false)
    folds.toggle(1)
    #expect(folds.isOpen(1, mode: .collapsed) == false)
}

@Test func hiddenToolsLeaveTheFlowWithNoCallAndNoGroupAndKeepTheRest() {
    let events = [ExecEvent(id: 1, at: 1, kind: "say", text: "reading")] + shell(2, "a", status: "ok", output: ["x"]) + shell(4, "b", status: "ok", output: ["y"])
        + [ExecEvent(id: 6, at: 6, kind: "say", text: "done")] + shell(7, "c", status: "err", output: ["boom"])
    let flow = flowItems(transcriptItems(events))
    #expect(flow.map(\.id) == [1, 2, 6, 7])
    #expect(visibleFlow(flow, mode: .hidden).map(\.id) == [1, 6])
    #expect(visibleFlow(flow, mode: .collapsed) == flow && visibleFlow(flow, mode: .expanded) == flow)
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

private func call(_ tool: String = "Bash", status: ToolStatus = .ok, ms: Int? = 80) -> TranscriptCard {
    TranscriptCard(tool: tool, kind: ToolKind(tool: tool), arg: "x", summary: "", status: status, duration: ms.map(formatCallDuration), durationMs: ms)
}

@Test func aCallIsSlowFromTenSeconds() {
    #expect(call(ms: 9_999).isSlow == false)
    #expect(call(ms: 10_000).isSlow)
    #expect(call(status: .pending, ms: nil).isSlow == false)
}

@Test func onlyTheSkillToolIsASkill() {
    #expect(call("Skill").isSkill)
    #expect(call("Bash").isSkill == false)
}

// A quiet line shows its duration on hover or focus, and always when slow or failed; never while it runs.
@Test func aCallLineShowsItsDurationOnlyWhenItMatters() {
    #expect(call().showsDuration(active: false) == false)
    #expect(call().showsDuration(active: true))
    #expect(call(ms: 10_000).showsDuration(active: false))
    #expect(call(status: .error).showsDuration(active: false))
    #expect(call(status: .pending, ms: nil).showsDuration(active: true) == false)
}

// The chevron shows on hover, when open, and always on a failed call; a call with nothing to open or still running has none.
@Test func aCallLineShowsItsChevronOnHoverOpenOrFailure() {
    #expect(call().showsChevron(active: false, open: false) == false)
    #expect(call().showsChevron(active: true, open: false))
    #expect(call().showsChevron(active: false, open: true))
    #expect(call(status: .error).showsChevron(active: false, open: false))
    #expect(call(status: .pending, ms: nil).showsChevron(active: true, open: false) == false)
    #expect(call("Read").showsChevron(active: true, open: false) == false)
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
