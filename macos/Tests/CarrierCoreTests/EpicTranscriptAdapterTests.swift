import Testing
@testable import CarrierCore

// The epic's events (the engine's harness parser) become the chat's `ToolGroup`s, so the epic draws a run with the chat's views.

private func run(_ flow: [FlowItem], at index: Int = 0) -> ToolGroup? {
    guard case .tools(_, let group, _)? = flow.filter({ if case .tools = $0 { true } else { false } })[safe: index] else { return nil }
    return group
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

private func chatGroup(_ events: [ChatEvent]) -> ToolGroup? {
    for row in chatFeed(events) { if case .tools(_, let group) = row { return group } }
    return nil
}

@Test func anEpicRunIsTheGroupTheChatBuildsFromTheEquivalentEvents() {
    let epic = [
        ExecEvent(id: 1, at: 1000, kind: "tool_start", callId: "a", tool: "Bash", arg: "pnpm vitest run"),
        ExecEvent(id: 2, at: 1500, kind: "tool_end", callId: "a", tool: "Bash", status: "err", durationMs: 500, output: ["Exit code 1", "FAIL  a.test.ts"]),
        ExecEvent(id: 3, at: 1600, kind: "tool_start", callId: "b", tool: "Edit", arg: "src/a.ts"),
        ExecEvent(id: 4, at: 1700, kind: "tool_end", callId: "b", tool: "Edit", status: "ok", durationMs: 100, diff: [.init(sign: "-", text: "old"), .init(sign: "+", text: "new")]),
        ExecEvent(id: 5, at: 1800, kind: "tool_start", callId: "c", tool: "Grep", arg: "grossFloor"),
        ExecEvent(id: 6, at: 1900, kind: "tool_end", callId: "c", tool: "Grep", status: "ok", output: ["a.ts:1", "b.ts:2"]),
        ExecEvent(id: 7, at: 2000, kind: "tool_start", callId: "d", tool: "Read", arg: "src/b.ts"),
    ]
    let chat = [
        ChatEvent(id: 1, at: 1000, kind: "tool_start", callId: "a", tool: "Bash", arg: "pnpm vitest run"),
        ChatEvent(id: 2, at: 1500, kind: "tool_end", callId: "a", tool: "Bash", output: ["Exit code 1", "FAIL  a.test.ts"], status: "err"),
        ChatEvent(id: 3, at: 1600, kind: "tool_start", callId: "b", tool: "Edit", arg: "src/a.ts"),
        ChatEvent(id: 4, at: 1700, kind: "tool_end", callId: "b", tool: "Edit", output: ["-old", "+new"], status: "ok"),
        ChatEvent(id: 5, at: 1800, kind: "tool_start", callId: "c", tool: "Grep", arg: "grossFloor"),
        ChatEvent(id: 6, at: 1900, kind: "tool_end", callId: "c", tool: "Grep", output: ["a.ts:1", "b.ts:2"], status: "ok"),
        ChatEvent(id: 7, at: 2000, kind: "tool_start", callId: "d", tool: "Read", arg: "src/b.ts"),
    ]
    let flow = flowItems(transcriptItems(epic), running: true)
    #expect(flow.count == 1)
    // the engine sends an edit's diff apart from its output, which the chat host stores as the diff's lines: the rest is the same
    var equivalent = chatGroup(chat)
    equivalent?.calls[1].output = []
    #expect(run(flow) == equivalent)

    // what the card reads: a failed call counted, the edit with its diff inside the group, the call going on
    let group = run(flow)
    #expect(group?.failed == 1 && group?.isWorking == true && group?.doing == "Reading src/b.ts")
    #expect(group?.calls[1].diff == [DiffRow(sign: .removed, text: "old"), DiffRow(sign: .added, text: "new")])
    #expect(group?.calls[1].result == "+1 −1")
    guard case .tools(_, _, let live)? = flow.first else { return }
    #expect(live)
}

@Test func theEpicsOwnRowsSitBetweenTheRunsInEventOrder() {
    let events = [
        ExecEvent(id: 1, at: 1, kind: "say", text: "Starting"),
        ExecEvent(id: 2, at: 2, kind: "tool_start", callId: "a", tool: "Bash", arg: "gh issue view 736"),
        ExecEvent(id: 3, at: 3, kind: "tool_end", callId: "a", tool: "Bash", status: "ok", durationMs: 1),
        ExecEvent(id: 4, at: 4, kind: "note", text: "created 736 (main)"),
        ExecEvent(id: 5, at: 5, kind: "tool_start", callId: "s", tool: "Skill", arg: "solve:ship"),
        ExecEvent(id: 6, at: 6, kind: "tool_end", callId: "s", tool: "Skill", status: "ok", durationMs: 1),
        ExecEvent(id: 7, at: 7, kind: "tool_start", callId: "b", tool: "Read", arg: "a.ts"),
        ExecEvent(id: 8, at: 8, kind: "tool_end", callId: "b", tool: "Read", summary: "40 lines", status: "ok", durationMs: 1),
        ExecEvent(id: 9, at: 9, kind: "error", text: "The agent process ended with an error."),
    ]
    let flow = flowItems(transcriptItems(events))
    #expect(flow.map { $0.id } == [1, 2, 4, 5, 7, 9])
    #expect(flow.map { item -> String in
        switch item {
        case .message: "message"
        case .tools(_, let group, _): "run of \(group.calls.count)"
        case .note: "note"
        case .skill: "skill"
        case .error: "error"
        case .slices: "slices"
        }
    } == ["message", "run of 1", "note", "skill", "run of 1", "error"])
    // the engine's own count stands for a read whose output is only its first and last lines
    #expect(run(flow, at: 1)?.calls.first?.result == "40 lines")
    // nothing is live while the session is not running, and a run of calls with no end was stopped
    #expect(flow.contains { if case .tools(_, _, true) = $0 { true } else { false } } == false)
}

@Test func aThoughtIsPlacedAmongTheCallsOfItsRunAsTheChatPlacesIt() {
    let epic = [
        ExecEvent(id: 1, at: 100, kind: "reasoning", text: "  Where is the floor compared?\n"),
        ExecEvent(id: 2, at: 200, kind: "tool_start", callId: "a", tool: "Grep", arg: "grossFloor"),
        ExecEvent(id: 3, at: 300, kind: "tool_end", callId: "a", tool: "Grep", status: "ok", output: ["a.ts:1"]),
        ExecEvent(id: 4, at: 400, kind: "reasoning", text: "It is not."),
    ]
    let chat = [
        ChatEvent(id: 1, at: 100, kind: "reasoning", text: "  Where is the floor compared?\n"),
        ChatEvent(id: 2, at: 200, kind: "tool_start", callId: "a", tool: "Grep", arg: "grossFloor"),
        ChatEvent(id: 3, at: 300, kind: "tool_end", callId: "a", tool: "Grep", output: ["a.ts:1"], status: "ok"),
        ChatEvent(id: 4, at: 400, kind: "reasoning", text: "It is not."),
    ]
    let group = run(flowItems(transcriptItems(epic)))
    #expect(group == chatGroup(chat))
    #expect(group?.thoughts.map(\.text) == ["Where is the floor compared?", "It is not."])
    #expect(group?.steps.count == 3)
}

@Test func aSessionWithNoThoughtsInventsNone() {
    let flow = flowItems(transcriptItems([
        ExecEvent(id: 1, at: 1, kind: "tool_start", callId: "a", tool: "Bash", arg: "ls"),
        ExecEvent(id: 2, at: 2, kind: "tool_end", callId: "a", tool: "Bash", status: "ok", durationMs: 1),
    ]))
    #expect(run(flow)?.thoughts.isEmpty == true)
}

@Test func aSlicePlacedByTheLanesSplitsTheRunsAroundIt() {
    func call(_ id: Int) -> [ExecEvent] {
        [ExecEvent(id: id, at: id, kind: "tool_start", callId: "c\(id)", tool: "Bash", arg: "ls"),
         ExecEvent(id: id + 1, at: id, kind: "tool_end", callId: "c\(id)", tool: "Bash", status: "ok", durationMs: 1)]
    }
    let lane = LaneSection(
        id: "A", startId: 5, title: "Build slice #1", sliceTitle: nil, state: .finished, duration: nil, startedAt: nil, endedAt: nil, resumes: 0,
        timeLabel: nil, counts: SessionCounts(), items: [], slice: 1, laneNumber: nil, pullRequest: "no PR yet"
    )
    let flow = flowItems(transcriptItems(call(1) + call(3) + call(6)), slices: [lane])
    #expect(flow.map(\.id) == [1, 5, 6])
    #expect(run(flow, at: 0)?.calls.count == 2 && run(flow, at: 1)?.calls.count == 1)
}
