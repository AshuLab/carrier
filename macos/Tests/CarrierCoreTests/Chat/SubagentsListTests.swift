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

@Test func allSubagentsFlattensEveryLaunchAndNestedSubagentInModelOrder() throws {
    let reply = try JSONDecoder().decode(
        ChatEvents.self,
        from: Data(contentsOf: URL(fileURLWithPath: fixtures + "/chat-events-subagents.json"))
    )
    let list = subagentsList(in: reply.events, working: true)
    #expect(list.allSubagents.map(\.id) == ["a3", "a1", "n1", "a2"])
    #expect(list.allSubagents.count == list.totalCount)
    #expect(SubagentsList.empty.allSubagents.isEmpty)
}

@Test func subagentSpokenReadsTypeTitleStepAndStepsInEveryState() {
    let en = (bundle: english.bundle, locale: english.locale)
    let events = [
        agentStart(1, 10, "r1"),
        task(2, 11, "r1", "started", text: "Search logs"),
        ChatEvent(id: 3, at: 12, kind: "tool_start", callId: "s1", tool: "Read", arg: "a.swift", parentCallId: "r1"),
        agentStart(4, 20, "c1"),
        task(5, 21, "c1", "started", text: "Check tests"),
        task(6, 30, "c1", "completed", ms: 9),
        agentStart(7, 40, "f1"),
        task(8, 41, "f1", "started", text: "Deploy"),
        task(9, 50, "f1", "failed", ms: 9),
        agentStart(10, 60, "p1"),
        task(11, 61, "p1", "started", text: "Wait"),
        task(12, 70, "p1", "stopped", ms: 9),
    ]
    let list = subagentsList(in: events)
    #expect(list.allSubagents.map { $0.spoken(bundle: en.bundle, locale: en.locale) } == [
        "Explore subagent, Search logs, Reading a.swift, 1 step",
        "Explore subagent, Deploy, Failed, 0 steps",
        "Explore subagent, Check tests, Finished, 0 steps",
        "Explore subagent, Wait, Stopped, 0 steps",
    ])
    #expect(Copy.chatSubagentsListSpoken(bundle: en.bundle, locale: en.locale) == "Subagents")
}

@Test func launchesGroupRunningFirstThenFinishedMostRecentFirstWithEmptyLaunchesIgnored() {
    // Launch 0 has only tool calls (empty launch) -> ignored
    let emptyLaunch = [
        ChatEvent(id: 1, at: 0, kind: "user", text: "read"),
        ChatEvent(id: 2, at: 5_000, kind: "tool_start", callId: "r1", tool: "Read", arg: "a.swift"),
        ChatEvent(id: 3, at: 10_000, kind: "tool_end", callId: "r1", tool: "Read", status: "ok"),
        ChatEvent(id: 4, at: 12_000, kind: "assistant", text: "read it"),
    ]
    // Launch 1 finished at 100_000
    let finishedOlder = [
        ChatEvent(id: 5, at: 20_000, kind: "user", text: "first"),
        agentStart(6, 30_000, "a1"), task(7, 30_000, "a1", "started", text: "Older"),
        task(8, 100_000, "a1", "completed", ms: 70_000),
        ChatEvent(id: 9, at: 105_000, kind: "assistant", text: "done 1"),
    ]
    // Launch 2 finished at 220_000
    let finishedNewer = [
        ChatEvent(id: 10, at: 150_000, kind: "user", text: "second"),
        agentStart(11, 160_000, "b1"), task(12, 160_000, "b1", "started", text: "Newer"),
        task(13, 220_000, "b1", "failed", ms: 60_000),
        ChatEvent(id: 14, at: 225_000, kind: "assistant", text: "done 2"),
    ]
    // Launch 3 is still running (started at 300_000)
    let running = [
        ChatEvent(id: 15, at: 290_000, kind: "user", text: "third"),
        agentStart(16, 300_000, "c1"), task(17, 300_000, "c1", "started", text: "Live"),
    ]

    let list = subagentsList(in: emptyLaunch + finishedOlder + finishedNewer + running)
    #expect(list.sessionStartedAt == 0)
    // running first, then finished most-recent-first
    #expect(list.launches.map { $0.items[0].id } == ["c1", "b1", "a1"])
    #expect(list.launches.map(\.isRunning) == [true, false, false])
    #expect(list.launches.allSatisfy { list.showsBar(for: $0) })

    // A lone running launch shows no bar; a lone finished launch (stored session) shows its bar
    let loneRunning = subagentsList(in: running)
    #expect(loneRunning.launches.count == 1)
    #expect(loneRunning.showsBar(for: loneRunning.launches[0]) == false)

    let loneFinished = subagentsList(in: finishedOlder)
    #expect(loneFinished.launches.count == 1)
    #expect(loneFinished.showsBar(for: loneFinished.launches[0]) == true)
}

@Test func launchTimelineSpanAndLabelsAndSpokenFollowTheSessionTimelineAndClock() {
    let en = (bundle: english.bundle, locale: english.locale)
    let events = [
        ChatEvent(id: 1, at: 0, kind: "user", text: "start"),
        agentStart(2, 60_000, "a1"), task(3, 60_000, "a1", "started", text: "One"),
        agentStart(4, 60_000, "a2"), task(5, 60_000, "a2", "started", text: "Two"),
        agentStart(6, 60_000, "a3"), task(7, 60_000, "a3", "started", text: "Three"),
        task(8, 60_000, "a4", "started", text: "Nested", parentCallId: "a1"),
        task(9, 120_000, "a1", "completed", ms: 60_000),
        task(10, 140_000, "a2", "completed", ms: 80_000),
        task(11, 150_000, "a3", "completed", ms: 90_000),
        task(12, 160_000, "a4", "completed", ms: 100_000),
        ChatEvent(id: 13, at: 200_000, kind: "user", text: "next"),
        agentStart(14, 300_000, "b1"), task(15, 300_000, "b1", "started", text: "Live"),
    ]
    let list = subagentsList(in: events)
    // now = 400_000 (4 minutes after launch 1 ended at 160_000)
    let now = 400_000
    let runningLaunch = list.launches[0]
    let finishedLaunch = list.launches[1]

    let runningSpan = runningLaunch.timelineSpan(sessionStart: list.sessionStartedAt, now: now)
    #expect(runningSpan == LaunchTimelineSpan(start: 0.75, end: 1.0, isOpen: true))
    #expect(runningLaunch.barLabel(now: now, bundle: en.bundle, locale: en.locale) == "running · 1 subagent")
    #expect(runningLaunch.barSpoken(now: now, bundle: en.bundle, locale: en.locale) == "running, 1 subagent")

    let finishedSpan = finishedLaunch.timelineSpan(sessionStart: list.sessionStartedAt, now: now)
    #expect(finishedSpan == LaunchTimelineSpan(start: 0.15, end: 0.4, isOpen: false))
    #expect(finishedLaunch.barLabel(now: now, bundle: en.bundle, locale: en.locale) == "finished 4 min ago · 4 subagents")
    #expect(finishedLaunch.barSpoken(now: now, bundle: en.bundle, locale: en.locale) == "finished 4 minutes ago, 4 subagents")

    // Advancing one minute updates the label
    #expect(finishedLaunch.barLabel(now: now + 60_000, bundle: en.bundle, locale: en.locale) == "finished 5 min ago · 4 subagents")
    #expect(finishedLaunch.barSpoken(now: now + 60_000, bundle: en.bundle, locale: en.locale) == "finished 5 minutes ago, 4 subagents")
    // Under a minute, hours and days
    #expect(finishedLaunch.barLabel(now: 180_000, bundle: en.bundle, locale: en.locale) == "finished just now · 4 subagents")
    #expect(finishedLaunch.barSpoken(now: 180_000, bundle: en.bundle, locale: en.locale) == "finished just now, 4 subagents")
    #expect(finishedLaunch.barLabel(now: 160_000 + 2 * 3_600_000, bundle: en.bundle, locale: en.locale) == "finished 2 h ago · 4 subagents")
    #expect(finishedLaunch.barSpoken(now: 160_000 + 2 * 3_600_000, bundle: en.bundle, locale: en.locale) == "finished 2 hours ago, 4 subagents")
    #expect(finishedLaunch.barLabel(now: 160_000 + 2 * 86_400_000, bundle: en.bundle, locale: en.locale) == "finished 2 d ago · 4 subagents")
    #expect(finishedLaunch.barSpoken(now: 160_000 + 2 * 86_400_000, bundle: en.bundle, locale: en.locale) == "finished 2 days ago, 4 subagents")
}

@Test func displayRowsKeepFinishedLauncherAboveRunningChildAndComputeGuideRails() {
    let events = [
        ChatEvent(id: 1, at: 0, kind: "user", text: "go"),
        agentStart(2, 10, "p1"), task(3, 11, "p1", "started", text: "Finished parent"),
        task(4, 20, "c1", "started", text: "Child running", parentCallId: "p1"),
        task(5, 22, "c2", "started", text: "Child done", parentCallId: "p1"),
        task(6, 25, "g1", "started", text: "Grandchild", parentCallId: "c1"),
        task(7, 30, "g1", "completed", ms: 5),
        task(8, 35, "c2", "completed", ms: 13),
        task(9, 40, "p1", "completed", ms: 29),
    ]
    let list = subagentsList(in: events)
    #expect(list.launches.count == 1)
    let launch = list.launches[0]
    // p1 finished while child c1 still runs -> launch is still running and p1 stays above c1
    #expect(launch.isRunning)
    #expect(launch.displayRows.map(\.id) == ["p1", "c1", "g1", "c2"])
    #expect(launch.displayRows.map(\.depth) == [0, 1, 2, 1])
    #expect(launch.displayRows.map(\.guides) == [[], [true], [true, false], [false]])
}
