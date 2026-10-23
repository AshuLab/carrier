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
    #expect(result.laneSections().map(\.id) == ["af4e38341539ac2cf", "a97cac545564d0d61", "a72f07f44125066b2"])
    // the three Agent calls of the main thread are its only calls
    #expect(result.items.count == 3)
    #expect(result.items.allSatisfy { if case .tool(_, let card) = $0 { card.tool == "Agent" } else { false } })
    // every event is in exactly one place
    let inLanes = result.lanes.reduce(0) { $0 + $1.events.count }
    #expect(inLanes + events.filter { $0.agentId == nil }.count == events.count)
    #expect(result.laneSections().allSatisfy { $0.items.isEmpty == false })
}

@Test func theLaneAndTheSliceComeFromTheRule() throws {
    let lanes = transcript(try streamEvents()).laneSections()
    #expect(lanes.map(\.slice) == [653, 654, nil])
    #expect(lanes.map(\.laneNumber) == [1, 2, nil])
    // a review subagent is a real subagent with neither: its description is its title
    #expect(lanes[2].title == "Experience pass review PR 673")
}

@Test func aLaneCountsItsOwnCallsOnly() throws {
    let lanes = transcript(try streamEvents()).laneSections()
    // the first lane's trimmed stream also has one result whose call is not in it, which counts as a call of its own
    #expect(lanes.map(\.counts) == ["5 tool calls", "3 tool calls", "2 tool calls"])
}

private func slice(_ number: Int, _ title: String) -> EpicReply.Slice {
    EpicReply.Slice(number: number, title: title, state: "open", blockedBy: [], prNumber: nil, closedAt: nil, readAt: 0)
}

@Test func aLaneWithNoSliceKeepsItsLaneAndTheDescription() {
    let lane = transcript([event(1, "task", agent: "a", text: "Tidy the docs"), event(2, "tool_start", agent: "a", arg: "cd /w/epic--lane-3 && ls")]).laneSections()[0]
    #expect(lane.title == "Tidy the docs" && lane.slice == nil && lane.sliceTitle == nil && lane.laneNumber == 3)
    // the task event has not arrived yet
    #expect(transcript([event(1, "say", agent: "a", text: "hi")]).laneSections()[0].title == "Subagent")
}

@Test func aSliceTakesItsTitleFromTheEpicsListAndKeepsTheDescriptionWithNoMatch() {
    let events = [event(1, "task", agent: "a", text: "Build slice #5"), event(2, "tool_start", agent: "a", arg: "pnpm test")]
    let matched = transcript(events).laneSections(slices: [slice(4, "Other"), slice(5, "Socket client")])[0]
    #expect(matched.slice == 5 && matched.sliceTitle == "Socket client" && matched.title == "Socket client")
    let missing = transcript(events).laneSections(slices: [slice(4, "Other")])[0]
    #expect(missing.slice == 5 && missing.sliceTitle == nil && missing.title == "Build slice #5")
    #expect(transcript(events).laneSections()[0].sliceTitle == nil)
}

private func end(_ id: Int, _ status: String) -> ExecEvent {
    ExecEvent(id: id, at: id * 1000, kind: "task", text: "Build slice #5", agentId: "a", status: status)
}

@Test func aSubagentIsRunningUntilItsEndEventAndFinishedOrFailedByItsStatus() {
    let start = ExecEvent(id: 1, at: 1000, kind: "task", text: "Build slice #5", agentId: "a")
    let work = event(2, "say", agent: "a", text: "hi")
    func lane(_ events: [ExecEvent], running: Bool = true) -> LaneSection { transcript(events).laneSections(running: running)[0] }
    #expect(lane([start, work]).state == .running && lane([start, work]).duration == nil)
    // a start with no end in a session that is no longer running did not complete
    #expect(lane([start, work], running: false).state == .failed && lane([start, work], running: false).duration == nil)
    #expect(lane([start, work, end(3, "ok")]).state == .finished)
    #expect(lane([start, work, end(3, "ok")], running: false).state == .finished)
    #expect(lane([start, work, end(3, "err")]).state == .failed)
    // the first start to the end of the first run; a run after it changes neither
    let again = ExecEvent(id: 4, at: 9000, kind: "task", text: "Build slice #5", agentId: "a")
    let resumed = lane([start, work, end(3, "ok"), again, end(5, "err")])
    #expect(resumed.state == .finished && resumed.duration == 2000)
}

@Test func aStreamWithNoSubagentsHasNoLanes() {
    let result = transcript([event(1, "say", text: "hello"), event(2, "tool_start", arg: "ls"), event(3, "say", text: "done")])
    #expect(result.laneSections().isEmpty)
    #expect(result.items.count == 3)
}

@Test func anOlderEventArrivingLateRebuildsTheLanesToTheSameSections() {
    let events = [event(1, "task", agent: "a", text: "Build slice #5"), event(2, "tool_start", agent: "a", arg: "cd w--lane-2"), event(3, "say", text: "main")]
    var late = Transcript()
    late.apply(EventsReply(events: [events[2]], next: 3, running: true, structured: true))
    late.apply(EventsReply(events: Array(events[0...1]), next: 3, running: true, structured: true))
    #expect(late.laneSections() == transcript(events).laneSections())
    #expect(late.items == transcript(events).items)
    #expect(late.laneSections()[0].laneNumber == 2 && late.laneSections()[0].slice == 5)
}

@Test func aSessionCarriesItsLanesOnlyWhenTheHarnessIsStructured() {
    let sessions = SessionsReply(sessions: [SessionsReply.Session(
        executionId: "x", stage: "ship", role: "author", round: nil, agent: .init(harness: "claude", model: "m", provider: nil),
        status: "finished", startedAt: 0, finishedAt: 5, resume: nil)])
    let events = [event(1, "task", agent: "a", text: "Build slice #5"), event(2, "say", agent: "a", text: "hi")]
    #expect(sessionList(sessions, transcripts: ["x": transcript(events)]).sections[0].lanes.map(\.title) == ["Build slice #5"])
    var plain = Transcript()
    plain.apply(EventsReply(events: events, next: 2, running: true, structured: false))
    #expect(sessionList(sessions, transcripts: ["x": plain]).sections[0].lanes.isEmpty)
    #expect(sessionList(sessions).sections[0].lanes.isEmpty)
}

@Test func theListJoinsTheEpicsSlicesAndTellsARunningSessionFromAStoppedOne() {
    func list(_ status: String) -> [LaneSection] {
        let sessions = SessionsReply(sessions: [SessionsReply.Session(
            executionId: "x", stage: "ship", role: "author", round: nil, agent: .init(harness: "claude", model: "m", provider: nil),
            status: status, startedAt: 0, finishedAt: nil, resume: nil)])
        let events = [event(1, "task", agent: "a", text: "Build slice #5"), event(2, "say", agent: "a", text: "hi")]
        return sessionList(sessions, transcripts: ["x": transcript(events)], slices: [slice(5, "Socket client")]).sections[0].lanes
    }
    #expect(list("running").map(\.title) == ["Socket client"])
    #expect(list("running").map(\.state) == [.running])
    #expect(list("interrupted").map(\.state) == [.failed])
}
