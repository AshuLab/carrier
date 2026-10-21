import Foundation
import Testing
@testable import CarrierCore

// The sanitised stream of the third spike (docs/research/claude-subagent-attribution.md): two build subagents on lanes 1 and 2 and one
// review subagent. The engine's parser is not in this package, so the stream is read here the way it reads it: a `task_started`
// line is a `task` event, a message line is a `say`, a tool call a `tool_start`, its result a `tool_end`.
private let streamURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("src/harnesses/claude-subagents.fixture.jsonl")

private func streamEvents() throws -> [ExecEvent] {
    var events: [ExecEvent] = []
    func add(_ kind: String, _ agent: String?, text: String? = nil, call: String? = nil, tool: String? = nil, arg: String? = nil) {
        events.append(ExecEvent(id: events.count + 1, at: events.count, kind: kind, text: text, callId: call, agentId: agent, tool: tool, arg: arg))
    }
    for line in try String(contentsOf: streamURL, encoding: .utf8).split(separator: "\n") {
        let json = try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        let agent = json["agent_id"] as? String
        if json["subtype"] as? String == "task_started" {
            add("task", json["task_id"] as? String, text: json["description"] as? String)
        }
        let content = (json["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
        for block in content {
            let input = block["input"] as? [String: Any]
            switch block["type"] as? String {
            case "text": add("say", agent, text: block["text"] as? String)
            case "tool_use": add("tool_start", agent, call: block["id"] as? String, tool: block["name"] as? String, arg: (input?["command"] ?? input?["file_path"]) as? String)
            case "tool_result": add("tool_end", agent, call: block["tool_use_id"] as? String)
            default: break
            }
        }
    }
    return events
}

private func transcript(_ events: [ExecEvent]) -> Transcript {
    var transcript = Transcript()
    transcript.apply(EventsReply(events: events, next: events.last?.id ?? 0, running: true, structured: true))
    return transcript
}

private func event(_ id: Int, _ kind: String, agent: String? = nil, text: String? = nil, arg: String? = nil) -> ExecEvent {
    ExecEvent(id: id, at: id, kind: kind, text: text, callId: arg.map { _ in "c\(id)" }, agentId: agent, tool: arg == nil ? nil : "Bash", arg: arg)
}

@Test func theStreamIsGroupedBySubagentAndTheMainSessionKeepsTheRest() throws {
    let events = try streamEvents()
    let result = transcript(events)
    #expect(result.laneSections.map(\.id) == ["af4e38341539ac2cf", "a97cac545564d0d61", "a72f07f44125066b2"])
    // the three Agent calls of the main thread are its only calls
    #expect(result.items.count == 3)
    #expect(result.items.allSatisfy { if case .tool(_, let card) = $0 { card.tool == "Agent" } else { false } })
    // every event is in exactly one place
    let inLanes = result.lanes.reduce(0) { $0 + $1.events.count }
    #expect(inLanes + events.filter { $0.agentId == nil }.count == events.count)
    #expect(result.laneSections.allSatisfy { $0.items.isEmpty == false })
}

@Test func theLaneAndTheSliceComeFromTheRuleAndAreMarkedAsHints() throws {
    let lanes = transcript(try streamEvents()).laneSections
    #expect(lanes[0].title == "Lane 1 · #653")
    #expect(lanes[1].title == "Lane 2 · #654")
    #expect(lanes[0].hint && lanes[1].hint)
    // a review subagent is a real subagent with neither: its description, no hint mark
    #expect(lanes[2].title == "Experience pass review PR 673")
    #expect(lanes[2].hint == false)
}

@Test func aLaneCountsItsOwnCallsOnly() throws {
    let lanes = transcript(try streamEvents()).laneSections
    // the first lane's trimmed stream also has one result whose call is not in it, which counts as a call of its own
    #expect(lanes.map(\.counts) == ["5 tool calls", "3 tool calls", "2 tool calls"])
}

@Test func aLaneWithNoSliceIsNamedByItsLaneAndStillAHint() {
    let lane = transcript([event(1, "task", agent: "a", text: "Tidy the docs"), event(2, "tool_start", agent: "a", arg: "cd /w/epic--lane-3 && ls")]).laneSections[0]
    #expect(lane.title == "Lane 3")
    #expect(lane.hint)
}

@Test func aSliceWithNoLaneIsNamedBySliceAndNoSliceNoLaneKeepsTheDescription() {
    let sequential = transcript([event(1, "task", agent: "a", text: "Build slice #12"), event(2, "tool_start", agent: "a", arg: "pnpm test")]).laneSections[0]
    #expect(sequential.title == "#12" && sequential.hint)
    let plain = transcript([event(1, "task", agent: "a", text: "Fix the build")]).laneSections[0]
    #expect(plain.title == "Fix the build" && plain.hint == false)
    // the task event has not arrived yet
    let early = transcript([event(1, "say", agent: "a", text: "hi")]).laneSections[0]
    #expect(early.title == "Subagent" && early.hint == false)
}

@Test func aStreamWithNoSubagentsHasNoLanes() {
    let result = transcript([event(1, "say", text: "hello"), event(2, "tool_start", arg: "ls"), event(3, "say", text: "done")])
    #expect(result.laneSections.isEmpty)
    #expect(result.items.count == 3)
}

@Test func anOlderEventArrivingLateRebuildsTheLanesToTheSameSections() {
    let events = [event(1, "task", agent: "a", text: "Build slice #5"), event(2, "tool_start", agent: "a", arg: "cd w--lane-2"), event(3, "say", text: "main")]
    var late = Transcript()
    late.apply(EventsReply(events: [events[2]], next: 3, running: true, structured: true))
    late.apply(EventsReply(events: Array(events[0...1]), next: 3, running: true, structured: true))
    #expect(late.laneSections == transcript(events).laneSections)
    #expect(late.items == transcript(events).items)
    #expect(late.laneSections[0].title == "Lane 2 · #5")
}

@Test func aSessionCarriesItsLanesOnlyWhenTheHarnessIsStructured() {
    let sessions = SessionsReply(sessions: [SessionsReply.Session(
        executionId: "x", stage: "ship", role: "author", round: nil, agent: .init(harness: "claude", model: "m", provider: nil),
        status: "finished", startedAt: 0, finishedAt: 5, resume: nil)])
    let events = [event(1, "task", agent: "a", text: "Build slice #5"), event(2, "say", agent: "a", text: "hi")]
    #expect(sessionList(sessions, transcripts: ["x": transcript(events)]).sections[0].lanes.map(\.title) == ["#5"])
    var plain = Transcript()
    plain.apply(EventsReply(events: events, next: 2, running: true, structured: false))
    #expect(sessionList(sessions, transcripts: ["x": plain]).sections[0].lanes.isEmpty)
    #expect(sessionList(sessions).sections[0].lanes.isEmpty)
}
