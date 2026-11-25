import Foundation
import Testing
@testable import CarrierCore

// The sanitised stream of the third spike (docs/research/claude-subagent-attribution.md): two build subagents on lanes 1 and 2 and one
// review subagent. The engine's parser is not in this package, so the stream is read here the way it reads it: a `task_started`
// line is a `task` event, a message line is a `say`, a tool call a `tool_start`, its result a `tool_end`.
private let streamURL = testPaths().root.appendingPathComponent("src/harnesses/claude-subagents.fixture.jsonl")

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

extension SessionSection {
    /// The subagents in the section's list, in its order.
    var slices: [LaneSection] {
        guard case .items(let flow) = body else { return [] }
        return flow.compactMap { if case .slice(let lane) = $0 { lane } else { nil } }
    }
}

private func event(_ id: Int, _ kind: String, agent: String? = nil, text: String? = nil, arg: String? = nil) -> ExecEvent {
    ExecEvent(id: id, at: id, kind: kind, text: text, callId: arg.map { _ in "c\(id)" }, agentId: agent, tool: arg == nil ? nil : "Bash", arg: arg)
}

@Test func theStreamIsGroupedBySubagentAndTheMainSessionKeepsTheRest() throws {
    let events = try streamEvents()
    let result = transcript(events)
    #expect(result.laneSections(bundle: english.bundle, locale: english.locale).map(\.id) == ["af4e38341539ac2cf", "a97cac545564d0d61", "a72f07f44125066b2"])
    // the three Agent calls of the main thread are its only calls
    #expect(result.items.count == 3)
    #expect(result.items.allSatisfy { if case .tool(_, let card) = $0 { card.tool == "Agent" } else { false } })
    // every event is in exactly one place
    let inLanes = result.lanes.reduce(0) { $0 + $1.events.count }
    #expect(inLanes + events.filter { $0.agentId == nil }.count == events.count)
    #expect(result.laneSections(bundle: english.bundle, locale: english.locale).allSatisfy { $0.items.isEmpty == false })
}

@Test func theLaneAndTheSliceComeFromTheRule() throws {
    let lanes = transcript(try streamEvents()).laneSections(bundle: english.bundle, locale: english.locale)
    #expect(lanes.map(\.slice) == [653, 654, nil])
    #expect(lanes.map(\.laneNumber) == [1, 2, nil])
    // a review subagent is a real subagent with neither: its description is its title
    #expect(lanes[2].title == "Experience pass review PR 673")
}

@Test func aLaneCountsItsOwnCallsOnly() throws {
    let lanes = transcript(try streamEvents()).laneSections(bundle: english.bundle, locale: english.locale)
    // the first lane's trimmed stream also has one result whose call is not in it, which counts as a call of its own
    #expect(lanes.map(\.counts.calls) == [5, 3, 2])
}

private func slice(_ number: Int, _ title: String) -> EpicReply.Slice {
    EpicReply.Slice(number: number, title: title, state: "open", blockedBy: [], prNumber: nil, closedAt: nil, readAt: 0)
}

@Test func aLaneWithNoSliceKeepsItsLaneAndTheDescription() {
    let lane = transcript([event(1, "task", agent: "a", text: "Tidy the docs"), event(2, "tool_start", agent: "a", arg: "cd /w/epic--lane-3 && ls")]).laneSections(bundle: english.bundle, locale: english.locale)[0]
    #expect(lane.title == "Tidy the docs" && lane.slice == nil && lane.sliceTitle == nil && lane.laneNumber == 3)
    // the task event has not arrived yet
    #expect(transcript([event(1, "say", agent: "a", text: "hi")]).laneSections(bundle: english.bundle, locale: english.locale)[0].title == "Subagent")
}

@Test func aSliceTakesItsTitleFromTheEpicsListAndKeepsTheDescriptionWithNoMatch() {
    let events = [event(1, "task", agent: "a", text: "Build slice #5"), event(2, "tool_start", agent: "a", arg: "pnpm test")]
    let matched = transcript(events).laneSections(slices: [slice(4, "Other"), slice(5, "Socket client")], bundle: english.bundle, locale: english.locale)[0]
    #expect(matched.slice == 5 && matched.sliceTitle == "Socket client" && matched.title == "Socket client")
    let missing = transcript(events).laneSections(slices: [slice(4, "Other")], bundle: english.bundle, locale: english.locale)[0]
    #expect(missing.slice == 5 && missing.sliceTitle == nil && missing.title == "Build slice #5")
    #expect(transcript(events).laneSections(bundle: english.bundle, locale: english.locale)[0].sliceTitle == nil)
}

private func end(_ id: Int, _ status: String) -> ExecEvent {
    ExecEvent(id: id, at: id * 1000, kind: "task", text: "Build slice #5", agentId: "a", status: status)
}

@Test func aSubagentIsRunningUntilItsEndEventAndFinishedOrFailedByItsStatus() {
    let start = ExecEvent(id: 1, at: 1000, kind: "task", text: "Build slice #5", agentId: "a")
    let work = event(2, "say", agent: "a", text: "hi")
    func lane(_ events: [ExecEvent], running: Bool = true) -> LaneSection { transcript(events).laneSections(running: running, now: 4000, bundle: english.bundle, locale: english.locale)[0] }
    #expect(lane([start, work]).state == .running)
    // a start with no end in a session that is no longer running did not complete
    #expect(lane([start, work], running: false).state == .failed && lane([start, work], running: false).duration == nil)
    #expect(lane([start, work], running: false).timeLabel == nil)
    #expect(lane([start, work, end(3, "ok")]).state == .finished)
    #expect(lane([start, work, end(3, "ok")], running: false).state == .finished)
    #expect(lane([start, work, end(3, "err")]).state == .failed)
    // the first start to the end of the first run; a run after it changes neither, only the state
    let again = ExecEvent(id: 4, at: 9000, kind: "task", text: "Build slice #5", agentId: "a")
    let resumed = lane([start, work, end(3, "ok"), again, end(5, "err")])
    #expect(resumed.state == .failed && resumed.duration == 2000)
    #expect(lane([start, work, end(3, "ok"), again, end(5, "ok")]).state == .finished)
    // running again: the last event is a start and the session is running; in a stopped session it did not complete
    #expect(lane([start, work, end(3, "ok"), again]).state == .running)
    #expect(lane([start, work, end(3, "ok"), again]).duration == 2000 && lane([start, work, end(3, "ok"), again]).resumedLabel(bundle: english.bundle, locale: english.locale) == "resumed once")
    #expect(lane([start, work, end(3, "ok"), again], running: false).state == .failed)
    #expect(lane([start, work, end(3, "err")]).state == .failed)
}

@Test func aStreamWithNoSubagentsHasNoLanes() {
    let result = transcript([event(1, "say", text: "hello"), event(2, "tool_start", arg: "ls"), event(3, "say", text: "done")])
    #expect(result.laneSections(bundle: english.bundle, locale: english.locale).isEmpty)
    #expect(result.items.count == 3)
}

@Test func anOlderEventArrivingLateRebuildsTheLanesToTheSameSections() {
    let events = [event(1, "task", agent: "a", text: "Build slice #5"), event(2, "tool_start", agent: "a", arg: "cd w--lane-2"), event(3, "say", text: "main")]
    var late = Transcript()
    late.apply(EventsReply(events: [events[2]], next: 3, running: true, structured: true))
    late.apply(EventsReply(events: Array(events[0...1]), next: 3, running: true, structured: true))
    #expect(late.laneSections(bundle: english.bundle, locale: english.locale) == transcript(events).laneSections(bundle: english.bundle, locale: english.locale))
    #expect(late.items == transcript(events).items)
    #expect(late.laneSections(bundle: english.bundle, locale: english.locale)[0].laneNumber == 2 && late.laneSections(bundle: english.bundle, locale: english.locale)[0].slice == 5)
}

@Test func aSessionCarriesItsLanesOnlyWhenTheHarnessIsStructured() {
    let sessions = SessionsReply(sessions: [SessionsReply.Session(
        executionId: "x", stage: "ship", role: "author", round: nil, agent: .init(harness: "claude", model: "m", provider: nil),
        status: "finished", startedAt: 0, finishedAt: 5, resume: nil)])
    let events = [event(1, "task", agent: "a", text: "Build slice #5"), event(2, "say", agent: "a", text: "hi")]
    #expect(sessionList(sessions, transcripts: ["x": transcript(events)], bundle: english.bundle, locale: english.locale).sections[0].slices.map(\.title) == ["Build slice #5"])
    var plain = Transcript()
    plain.apply(EventsReply(events: events, next: 2, running: true, structured: false))
    #expect(sessionList(sessions, transcripts: ["x": plain], bundle: english.bundle, locale: english.locale).sections[0].slices.isEmpty)
    #expect(sessionList(sessions, bundle: english.bundle, locale: english.locale).sections[0].slices.isEmpty)
}

@Test func theListJoinsTheEpicsSlicesAndTellsARunningSessionFromAStoppedOne() {
    func list(_ status: String) -> [LaneSection] {
        let sessions = SessionsReply(sessions: [SessionsReply.Session(
            executionId: "x", stage: "ship", role: "author", round: nil, agent: .init(harness: "claude", model: "m", provider: nil),
            status: status, startedAt: 0, finishedAt: nil, resume: nil)])
        let events = [event(1, "task", agent: "a", text: "Build slice #5"), event(2, "say", agent: "a", text: "hi")]
        return sessionList(sessions, transcripts: ["x": transcript(events)], slices: [slice(5, "Socket client")], bundle: english.bundle, locale: english.locale).sections[0].slices
    }
    #expect(list("running").map(\.title) == ["Socket client"])
    #expect(list("running").map(\.state) == [.running])
    #expect(list("interrupted").map(\.state) == [.failed])
}

@Test func theListGivesEachSubagentTheCountsOfItsOwnEvents() {
    func tool(_ id: Int, _ agent: String, _ name: String, arg: String, status: String = "ok", diff: [ExecEvent.DiffLine] = []) -> [ExecEvent] {
        [
            ExecEvent(id: id, at: id, kind: "tool_start", callId: "c\(id)", agentId: agent, tool: name, arg: arg),
            ExecEvent(id: id + 1, at: id, kind: "tool_end", callId: "c\(id)", agentId: agent, tool: name, status: status, diff: diff),
        ]
    }
    let first = [event(1, "task", agent: "a", text: "Build slice #5")]
        + tool(2, "a", "Read", arg: "/w/a.swift")
        + tool(4, "a", "Edit", arg: "/w/a.swift", diff: [.init(sign: "+", text: "x"), .init(sign: "+", text: "y"), .init(sign: "-", text: "z")])
        + tool(6, "a", "Bash", arg: "swift test")
        + tool(8, "a", "Bash", arg: "false", status: "err")
    let second = [event(20, "task", agent: "b", text: "Build slice #6")] + tool(21, "b", "Read", arg: "/w/b.swift")
    let sessions = SessionsReply(sessions: [SessionsReply.Session(
        executionId: "x", stage: "ship", role: "author", round: nil, agent: .init(harness: "claude", model: "m", provider: nil),
        status: "running", startedAt: 0, finishedAt: nil, resume: nil)])
    let lanes = sessionList(sessions, transcripts: ["x": transcript(first + second)], bundle: english.bundle, locale: english.locale).sections[0].slices
    #expect(lanes[0].counts == sessionCounts(first))
    #expect(lanes[0].counts == SessionCounts(calls: 4, edits: 1, added: 2, removed: 1, tests: 1, errors: 1))
    #expect(lanes[1].counts == SessionCounts(calls: 1))
}

@Test func aRowReadsItsSlicesPullRequestAndItsState() {
    func pr(_ number: Int, _ pr: Int?, _ state: String?) -> EpicReply.Slice {
        EpicReply.Slice(number: number, title: "S\(number)", state: "open", blockedBy: [], prNumber: pr, closedAt: nil, readAt: 0, prState: state)
    }
    let slices = [pr(1, 11, "merged"), pr(2, 12, "open"), pr(3, 13, "draft"), pr(4, 14, "closed"), pr(5, nil, nil), pr(6, 16, nil)]
    // slice 7 is not in the epic's list, and the last subagent names no slice
    let events = (1...7).map { event($0, "task", agent: "a\($0)", text: "Build slice #\($0)") } + [event(8, "task", agent: "z", text: "Tidy the docs")]
    let sessions = SessionsReply(sessions: [SessionsReply.Session(
        executionId: "x", stage: "ship", role: "author", round: nil, agent: .init(harness: "claude", model: "m", provider: nil),
        status: "running", startedAt: 0, finishedAt: nil, resume: nil)])
    let lanes = sessionList(sessions, transcripts: ["x": transcript(events)], slices: slices, bundle: english.bundle, locale: english.locale).sections[0].slices
    #expect(lanes.map(\.pullRequest) == ["PR #11 merged", "PR #12 open", "PR #13 draft", "PR #14 closed", "no PR yet", "PR #16", "no PR yet", "no PR yet"])
}

// 2026-01-01 14:02:00 UTC, in ms.
private let at1402 = 1_767_276_120_000

private func run(_ id: Int, _ seconds: Int, _ status: String? = nil) -> ExecEvent {
    ExecEvent(id: id, at: at1402 + seconds * 1000, kind: "task", text: "Build slice #5", agentId: "a", status: status)
}

private func lane(_ events: [ExecEvent], running: Bool = true, now: Int = at1402 + 600_000, timeZone: String = "UTC") -> LaneSection {
    let sessions = SessionsReply(sessions: [SessionsReply.Session(
        executionId: "x", stage: "ship", role: "author", round: nil, agent: .init(harness: "claude", model: "m", provider: nil),
        status: running ? "running" : "finished", startedAt: 0, finishedAt: nil, resume: nil)])
    return sessionList(sessions, transcripts: ["x": transcript(events)], now: now, time: TimeFormat(hours: .h24, timeZone: TimeZone(identifier: timeZone)!), bundle: english.bundle, locale: english.locale).sections[0].slices[0]
}

@Test func aFinishedSubagentCarriesItsTimesAndReadsThemInTheGivenTimeZone() {
    let finished = lane([run(1, 0), run(2, 187, "ok")])
    #expect(finished.startedAt == at1402 && finished.endedAt == at1402 + 187_000 && finished.duration == 187_000)
    #expect(finished.timeLabel == "14:02–14:05")
    #expect(lane([run(1, 0), run(2, 187, "ok")], timeZone: "Asia/Tokyo").timeLabel == "23:02–23:05")
}

@Test func aRunningSubagentReadsSinceItsStartAndHowLongItHasRun() {
    let running = lane([run(1, 0)], now: at1402 + 95_000)
    #expect(running.timeLabel == "since 14:02" && running.duration == 95_000 && running.endedAt == nil)
    // a start with no end in a stopped session ran for no known time
    #expect(lane([run(1, 0)], running: false, now: at1402 + 95_000).timeLabel == nil)
}

@Test func aSubagentThatRanAgainIsOneSectionWithItsFirstTimesAndSaysHowManyTimes() {
    let once = lane([run(1, 0), run(2, 60, "ok"), run(3, 300), run(4, 360, "ok")])
    #expect(once.timeLabel == "14:02–14:03" && once.duration == 60_000 && once.resumedLabel(bundle: english.bundle, locale: english.locale) == "resumed once")
    let twice = lane([run(1, 0), run(2, 60, "ok"), run(3, 300), run(4, 360, "ok"), run(5, 500), run(6, 520, "ok")])
    #expect(twice.timeLabel == "14:02–14:03" && twice.resumedLabel(bundle: english.bundle, locale: english.locale) == "resumed 2 times")
    // a second run still going changes nothing about the first
    #expect(lane([run(1, 0), run(2, 60, "ok"), run(3, 300)]).resumes == 1)
    let never = lane([run(1, 0), run(2, 60, "ok")])
    #expect(never.resumes == 0 && never.resumedLabel(bundle: english.bundle, locale: english.locale) == nil)
}

@Test func aResumedSubagentRunningAgainSaysRunningWithTheTimesOfItsFirstRun() {
    let events = [run(1, 0), run(2, 60, "ok"), run(3, 300)]
    let again = lane(events)
    #expect(again.state == .running && again.timeLabel == "14:02–14:03" && again.duration == 60_000 && again.resumedLabel(bundle: english.bundle, locale: english.locale) == "resumed once")
    #expect(lane(events, running: false).state == .failed)
    #expect(lane(events + [run(4, 360, "err")]).state == .failed)
    #expect(lane(events + [run(4, 360, "ok")]).state == .finished)
}

// MARK: the list in event order

private func running(_ events: [ExecEvent]) -> [FlowItem] {
    let sessions = SessionsReply(sessions: [SessionsReply.Session(
        executionId: "x", stage: "ship", role: "author", round: nil, agent: .init(harness: "claude", model: "m", provider: nil),
        status: "running", startedAt: 0, finishedAt: nil, resume: nil)])
    guard case .items(let flow) = sessionList(sessions, transcripts: ["x": transcript(events)], bundle: english.bundle, locale: english.locale).sections[0].body else { return [] }
    return flow
}

/// `m4` a main row with id 4, `sA` the slice of agent A.
private func order(_ flow: [FlowItem]) -> [String] {
    flow.map {
        switch $0 {
        case .tools(let id, _, _): "g\(id)"
        case .slice(let lane): "s" + lane.id
        default: "m\($0.id)"
        }
    }
}

private func say(_ id: Int) -> ExecEvent { event(id, "say", text: "m") }

@Test func eachSubagentSitsWhereItWasTakenAndWhatTheMainAgentDidMeanwhileFollowsIt() {
    let events = [say(1), say(2), say(3), event(4, "task", agent: "A", text: "Build slice #1"), event(5, "task", agent: "B", text: "Build slice #2")]
        + (6...10).map(say)
    #expect(order(running(events)) == ["m1", "m2", "m3", "sA", "sB", "m6", "m7", "m8", "m9", "m10"])
}

@Test func aSubagentWithNoTaskStartSitsAtItsFirstEventAndAResumeDoesNotMoveIt() {
    let events = [say(1), event(2, "say", agent: "A", text: "hi"), say(3), event(4, "task", agent: "B", text: "Build slice #2"), say(5),
                  ExecEvent(id: 6, at: 6, kind: "task", text: "Build slice #2", agentId: "B", status: "ok"), event(7, "task", agent: "B", text: "Build slice #2")]
    #expect(order(running(events)) == ["m1", "sA", "m3", "sB", "m5"])
}

@Test func aLateEventWithALowerIdRebuildsTheSameList() {
    let events = [say(1), event(2, "task", agent: "A", text: "Build slice #1"), say(3), event(4, "say", agent: "A", text: "in")]
    var late = Transcript()
    late.apply(EventsReply(events: [events[2], events[3]], next: 4, running: true, structured: true))
    late.apply(EventsReply(events: [events[0], events[1]], next: 4, running: true, structured: true))
    #expect(late.flow(bundle: english.bundle, locale: english.locale) == transcript(events).flow(bundle: english.bundle, locale: english.locale))
    #expect(order(late.flow(bundle: english.bundle, locale: english.locale)) == ["m1", "sA", "m3"])
}

@Test func aSliceEndsARunOfCallsSoAGroupNeverSpansIt() {
    func call(_ id: Int) -> [ExecEvent] {
        [ExecEvent(id: id, at: id, kind: "tool_start", callId: "c\(id)", tool: "Bash", arg: "ls"),
         ExecEvent(id: id + 1, at: id, kind: "tool_end", callId: "c\(id)", tool: "Bash", status: "ok", durationMs: 1)]
    }
    let events = call(1) + call(3) + [event(5, "task", agent: "A", text: "Build slice #1")] + call(6) + call(8)
    #expect(order(running(events)) == ["g1", "sA", "g6"])
}

@Test func theMainAgentCallThatLaunchedASubagentIsLeftOutAndOneWithNoSubagentStaysACall() {
    func agentCall(_ id: Int, _ callId: String) -> [ExecEvent] {
        [ExecEvent(id: id, at: id, kind: "tool_start", callId: callId, tool: "Agent", arg: "launch"),
         ExecEvent(id: id + 1, at: id, kind: "tool_end", callId: callId, tool: "Agent", status: "ok")]
    }
    let launch = ExecEvent(id: 3, at: 3, kind: "task", text: "Build slice #1", callId: "launch-1", agentId: "A")
    // the Agent call (events 1-2) is matched to the subagent's start by callId; the one for "later" has no subagent yet
    let events = agentCall(1, "launch-1") + [launch] + agentCall(4, "later")
    #expect(order(running(events)) == ["sA", "g4"])
    // its end can arrive first; the item is still left out
    let endFirst = [ExecEvent(id: 1, at: 1, kind: "tool_end", callId: "launch-1", tool: "Agent", status: "ok"), launch]
    #expect(order(running(endFirst)) == ["sA"])
    #expect(order(running(agentCall(1, "later"))) == ["g1"])
}

@Test func anAppendedEventProcessesOnlyItself() {
    var result = transcript([say(1), event(2, "task", agent: "A", text: "Build slice #1"), say(3)])
    let before = result.work
    result.apply(EventsReply(events: [say(4)], next: 4, running: true, structured: true))
    #expect(result.work == before + 1)
}

@Test func aRunningSubagentShowsTheStepItIsOnAndNothingExtraOnceItEnded() {
    func progress(_ id: Int, _ tool: String, tools: Int? = nil, tokens: Int? = nil, ms: Int? = nil) -> ExecEvent {
        ExecEvent(id: id, at: at1402 + id * 1000, kind: "task", agentId: "a", tool: tool, durationMs: ms, tools: tools, tokens: tokens)
    }
    let start = run(1, 0)
    #expect(lane([start]).lastStep == nil)
    let first = lane([start, progress(2, "Read", tools: 2, tokens: 900, ms: 4000)])
    #expect(first.lastStep == "Read" && first.state == .running && first.resumes == 0 && first.timeLabel == "since 14:02")
    let second = lane([start, progress(2, "Read"), progress(3, "Bash", tools: 3, tokens: 1500, ms: 6500)])
    #expect(second.lastStep == "Bash" && second.state == .running && second.resumes == 0)
    // once it ended (ok, failed or session stopped) no current step stays
    #expect(lane([start, progress(2, "Read"), progress(3, "Bash"), run(4, 60, "ok")]).lastStep == nil)
    #expect(lane([start, progress(2, "Read"), run(4, 60, "err")]).lastStep == nil)
    #expect(lane([start, progress(2, "Read")], running: false).lastStep == nil)
    // a resumed subagent starts with no step from its earlier run and tracks the new run's step
    let resumed = [start, progress(2, "Read"), run(3, 60, "ok"), run(4, 300)]
    #expect(lane(resumed).lastStep == nil && lane(resumed).resumes == 1)
    #expect(lane(resumed + [progress(5, "Edit")]).lastStep == "Edit" && lane(resumed + [progress(5, "Edit")]).resumes == 1)
    #expect(lane(resumed + [progress(5, "Edit"), run(6, 360, "ok")]).lastStep == nil)
}

// A slice card opens the subagent's view: the header says the slice, the role of the session it sits in and the epic, and the items are the
// lane's own, every run of a resumed subagent in one view.
@Test func aSliceCardsViewIsTheLanesOwnItemsWithTheSlicesHeader() {
    func session(_ id: String, _ stage: String, _ status: String) -> SessionsReply.Session {
        SessionsReply.Session(
            executionId: id, stage: stage, role: stage == "review" ? "reviewer" : "author", round: nil,
            agent: .init(harness: "claude", model: "m", provider: nil), status: status, startedAt: 0, finishedAt: status == "running" ? nil : 9, resume: nil)
    }
    let built = [
        event(1, "task", agent: "a", text: "Build slice #5"), event(2, "say", agent: "a", text: "first run"),
        end(3, "ok"), ExecEvent(id: 4, at: 4_000, kind: "task", text: "Build slice #5", agentId: "a"), event(5, "say", agent: "a", text: "second run"), end(6, "ok"),
        event(10, "task", agent: "f", text: "Tidy the docs"),
        ExecEvent(id: 11, at: 11_000, kind: "task", text: "Tidy the docs", agentId: "f", status: "err"),
    ]
    let review = [event(1, "task", agent: "r", text: "Review slice #5"), event(2, "say", agent: "r", text: "looking")]
    let list = sessionList(
        SessionsReply(sessions: [session("x", "ship", "finished"), session("y", "review", "running")]),
        transcripts: ["x": transcript(built), "y": transcript(review)], slices: [slice(5, "Socket client")], now: 20_000
    , bundle: english.bundle, locale: english.locale)
    // a builder's slice, finished, with both runs in one view
    let done = subagentWork(lane: "a", in: list, epic: "Rotate the keys")
    #expect(done?.header.title == "Socket client" && done?.header.type == "Builder" && done?.header.state == .completed)
    #expect(done?.header.subtitle(of: "ignored") == "Builder · Rotate the keys")
    #expect(done?.header.epic == "Rotate the keys")
    #expect(done?.items.compactMap { if case .message(_, let text) = $0 { text } else { nil } } == ["first run", "second run"])
    // not in the epic's list: the subagent's own description; failed
    let failed = subagentWork(lane: "f", in: list, epic: "Rotate the keys")
    #expect(failed?.header.title == "Tidy the docs" && failed?.header.state == .failed)
    // a reviewer's, running: no duration yet, a timer from its start
    let running = subagentWork(lane: "r", in: list, epic: "Rotate the keys")
    #expect(running?.header.type == "Reviewer" && running?.header.state == .running && running?.header.durationMs == nil)
    #expect(running?.header.subtitle(of: "") == "Reviewer · Rotate the keys")
    #expect(subagentWork(lane: "nope", in: list, epic: "E") == nil)
}
