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
    #expect(card(items[1]) == TranscriptCard(tool: "Read", kind: .read, arg: "src/a.ts", summary: "212 lines", status: .ok, duration: "80 ms"))
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
    #expect(ToolStatus.ok.icon == "checkmark")
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
    #expect(transcriptBody(structured) == .items([.message(id: 1, text: "hi")]))
    #expect(transcriptBody(nil) == .items([]))
}

@Test func durationsInMillisecondsSecondsAndMinutes() {
    #expect(formatCallDuration(0) == "0 ms")
    #expect(formatCallDuration(340) == "340 ms")
    #expect(formatCallDuration(999) == "999 ms")
    #expect(formatCallDuration(1000) == "1.0 s")
    #expect(formatCallDuration(6240) == "6.2 s")
    #expect(formatCallDuration(59_949) == "59.9 s")
    #expect(formatCallDuration(59_960) == "1m 00s")
    #expect(formatCallDuration(125_000) == "2m 05s")
}
