import Foundation
import Testing
@testable import CarrierCore

private let fixtures = testPaths().fixtures.path

private func agentStart(_ id: Int, _ at: Int, _ call: String) -> ChatEvent {
    ChatEvent(id: id, at: at, kind: "tool_start", callId: call, tool: "Agent", arg: "{}")
}

private func task(
    _ id: Int, _ at: Int, _ call: String, _ state: String, text: String? = nil,
    type: String? = "Explore", parentCallId: String? = nil, ms: Int? = nil
) -> ChatEvent {
    ChatEvent(
        id: id, at: at, kind: "task", text: text, callId: call, parentCallId: parentCallId,
        taskId: "t-\(call)", state: state, agentType: type, ms: ms
    )
}

@Test func aSessionWithNoSubagentsOrStoredBeforeTaskLinksHasAHiddenButton() throws {
    #expect(subagentsList(in: []).buttonState == .hidden)
    #expect(subagentsList(in: []).launches.isEmpty)
    #expect(subagentsList(in: []).buttonSpoken(bundle: english.bundle, locale: english.locale) == "")

    let preLink = [
        ChatEvent(id: 1, at: 0, kind: "user", text: "look"),
        ChatEvent(id: 2, at: 10, kind: "tool_start", callId: "a1", tool: "Agent", arg: "{}"),
        ChatEvent(id: 3, at: 20, kind: "tool_end", callId: "a1", tool: "Agent", output: ["done"], status: "ok"),
        ChatEvent(id: 4, at: 30, kind: "assistant", text: "finished"),
    ]
    #expect(subagentsList(in: preLink).buttonState == .hidden)

    let toolsGolden = try JSONDecoder().decode(
        ChatEvents.self,
        from: Data(contentsOf: URL(fileURLWithPath: fixtures + "/chat-events-tools.json"))
    )
    #expect(subagentsList(in: toolsGolden.events).buttonState == .hidden)
}

@Test func anEmptyLaunchProducesNoLaunchAndDoesNotAffectCounts() {
    let events = [
        ChatEvent(id: 1, at: 0, kind: "user", text: "go"),
        ChatEvent(id: 2, at: 10, kind: "reasoning", text: "thinking"),
        ChatEvent(id: 3, at: 20, kind: "tool_start", callId: "r1", tool: "Read", arg: "a.swift"),
        ChatEvent(id: 4, at: 30, kind: "tool_end", callId: "r1", tool: "Read", status: "ok"),
        ChatEvent(id: 5, at: 40, kind: "assistant", text: "read it"),
    ]
    let onlyCalls = subagentsList(in: events)
    #expect(onlyCalls.launches.isEmpty && onlyCalls.buttonState == .hidden)

    let withSubagent = events + [
        agentStart(6, 50, "a1"),
        task(7, 51, "a1", "started", text: "Check tests"),
    ]
    let list = subagentsList(in: withSubagent)
    #expect(list.launches.count == 1)
    #expect(list.buttonState == .running(count: 1))
}

@Test func theButtonEntersRunningWhenTheFirstSubagentStartsAndCountsActiveLaunchesOnly() {
    let launch1 = [
        ChatEvent(id: 1, at: 0, kind: "user", text: "first"),
        agentStart(2, 10, "a1"), task(3, 11, "a1", "started", text: "One"),
        agentStart(4, 12, "a2"), task(5, 13, "a2", "started", text: "Two"),
        task(6, 20, "a1", "completed", ms: 9),
        task(7, 30, "a2", "failed", ms: 17),
        ChatEvent(id: 8, at: 40, kind: "assistant", text: "done 1"),
    ]
    // while launch 1 ran, both were counted
    let duringFirst = subagentsList(in: Array(launch1.prefix(6)))
    #expect(duringFirst.buttonState == .running(count: 2))
    #expect(duringFirst.buttonSpoken(bundle: english.bundle, locale: english.locale) == "2 subagents, 1 running")

    // launch 1 ended with a failure, then launch 2 starts: finished launch leaves the header and leaves no red mark while launch 2 runs
    let launch2 = [
        ChatEvent(id: 9, at: 100, kind: "user", text: "second"),
        agentStart(10, 110, "b1"), task(11, 111, "b1", "started", text: "Three"),
        agentStart(12, 112, "b2"), task(13, 113, "b2", "started", text: "Four"),
        agentStart(14, 114, "b3"), task(15, 115, "b3", "started", text: "Five"),
        task(16, 120, "b2", "completed", ms: 7),
    ]
    let duringSecond = subagentsList(in: launch1 + launch2)
    #expect(duringSecond.launches.count == 2)
    #expect(duringSecond.launches.map(\.isRunning) == [true, false])
    #expect(duringSecond.buttonState == .running(count: 3))
    #expect(duringSecond.buttonSpoken(bundle: english.bundle, locale: english.locale) == "3 subagents, 2 running")
}

@Test func theButtonIsQuietWithTotalAndRedDotOnlyWhenNothingRunsAndAnyFailed() {
    let launch1 = [
        ChatEvent(id: 1, at: 0, kind: "user", text: "first"),
        agentStart(2, 10, "a1"), task(3, 11, "a1", "started", text: "One"),
        task(4, 20, "a1", "failed", ms: 9),
        ChatEvent(id: 5, at: 30, kind: "assistant", text: "one failed"),
    ]
    let launch2Clean = [
        ChatEvent(id: 6, at: 100, kind: "user", text: "second"),
        agentStart(7, 110, "b1"), task(8, 111, "b1", "started", text: "Two"),
        agentStart(9, 112, "b2"), task(10, 113, "b2", "started", text: "Three"),
        task(11, 120, "b1", "completed", ms: 9),
        task(12, 130, "b2", "stopped", ms: 17),
    ]
    // finished cleanly in launch 2, but launch 1 failed earlier -> total 3, failed true
    let quietWithEarlierFailure = subagentsList(in: launch1 + launch2Clean)
    #expect(quietWithEarlierFailure.buttonState == .quiet(total: 3, failed: true))
    #expect(quietWithEarlierFailure.buttonSpoken(bundle: english.bundle, locale: english.locale) == "3 subagents, 1 failed")

    // no failures in the session -> quiet with failed false
    let cleanOnly = subagentsList(in: launch2Clean)
    #expect(cleanOnly.buttonState == .quiet(total: 2, failed: false))
    #expect(cleanOnly.buttonSpoken(bundle: english.bundle, locale: english.locale) == "2 subagents")

    // a single subagent uses singular words
    let singleClean = subagentsList(in: [
        agentStart(1, 10, "s1"),
        task(2, 11, "s1", "started", text: "Solo"),
        task(3, 20, "s1", "completed", ms: 9),
    ])
    #expect(singleClean.buttonState == .quiet(total: 1, failed: false))
    #expect(singleClean.buttonSpoken(bundle: english.bundle, locale: english.locale) == "1 subagent")
}

@Test func nestedSubagentsCountInTheirLaunchersLaunchAndStayUnderTheirLauncher() {
    let events = [
        ChatEvent(id: 1, at: 0, kind: "user", text: "go"),
        agentStart(2, 10, "a1"), task(3, 11, "a1", "started", text: "Parent finished"),
        agentStart(4, 12, "a2"), task(5, 13, "a2", "started", text: "Parent running"),
        task(6, 20, "n1", "started", text: "Child running", parentCallId: "a1"),
        task(7, 22, "n2", "started", text: "Child completed", parentCallId: "a1"),
        task(8, 24, "n3", "started", text: "Child failed", parentCallId: "a1"),
        task(9, 25, "d1", "started", text: "Grandchild", parentCallId: "n2"),
        task(10, 30, "d1", "completed", ms: 5),
        task(11, 35, "n2", "completed", ms: 13),
        task(12, 40, "n3", "failed", ms: 16),
        task(13, 50, "a1", "completed", ms: 39),
    ]
    let list = subagentsList(in: events)
    #expect(list.launches.count == 1)
    let launch = list.launches[0]
    // top-level: a2 (running) comes before a1 (completed)
    #expect(launch.items.map(\.id) == ["a2", "a1"])
    // nested under a1 regardless of state, ordered running, failed, finished
    #expect(launch.items[1].children.map(\.id) == ["n1", "n3", "n2"])
    #expect(launch.items[1].children[2].children.map(\.id) == ["d1"])
    // count includes a1, a2, n1, n2, n3, d1 = 6; running are a2 and n1 = 2
    #expect(list.buttonState == .running(count: 6))
    #expect(list.buttonSpoken(bundle: english.bundle, locale: english.locale) == "6 subagents, 2 running")

    // if session is no longer working, unfinished subagents (top-level and nested) stop
    let stopped = subagentsList(in: events, working: false)
    #expect(stopped.buttonState == .quiet(total: 6, failed: true))
    #expect(stopped.buttonSpoken(bundle: english.bundle, locale: english.locale) == "6 subagents, 1 failed")
}

@Test func orderInsideALaunchIsRunningThenFailedThenFinishedAndPreservesStartOrder() {
    let events = [
        ChatEvent(id: 1, at: 0, kind: "user", text: "go"),
        agentStart(2, 10, "c1"), task(3, 11, "c1", "started", text: "Finished 1"),
        agentStart(4, 12, "f1"), task(5, 13, "f1", "started", text: "Failed 1"),
        agentStart(6, 14, "r1"), task(7, 15, "r1", "started", text: "Running 1"),
        agentStart(8, 16, "s1"), task(9, 17, "s1", "started", text: "Stopped 1"),
        agentStart(10, 18, "f2"), task(11, 19, "f2", "started", text: "Failed 2"),
        agentStart(12, 20, "r2"), task(13, 21, "r2", "started", text: "Running 2"),
        task(14, 30, "c1", "completed", ms: 19),
        task(15, 31, "f1", "failed", ms: 18),
        task(16, 32, "s1", "stopped", ms: 15),
        task(17, 33, "f2", "failed", ms: 14),
    ]
    let list = subagentsList(in: events)
    #expect(list.launches[0].items.map(\.id) == ["r1", "r2", "f1", "f2", "c1", "s1"])
}

@Test func theSubagentsFixtureProducesRunningWhileWorkingAndQuietWhenIdle() throws {
    let reply = try JSONDecoder().decode(
        ChatEvents.self,
        from: Data(contentsOf: URL(fileURLWithPath: fixtures + "/chat-events-subagents.json"))
    )
    let running = subagentsList(in: reply.events, working: true)
    #expect(running.launches.count == 1)
    #expect(running.buttonState == .running(count: 4))
    #expect(running.buttonSpoken(bundle: english.bundle, locale: english.locale) == "4 subagents, 1 running")
    // a3 (running) is first, then a1 and a2 (completed), with n1 nested under a1
    #expect(running.launches[0].items.map(\.id) == ["a3", "a1", "a2"])
    #expect(running.launches[0].items[1].children.map(\.id) == ["n1"])

    let idle = subagentsList(in: reply.events, working: false)
    #expect(idle.buttonState == .quiet(total: 4, failed: false))
    #expect(idle.buttonSpoken(bundle: english.bundle, locale: english.locale) == "4 subagents")
}
