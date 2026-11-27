@testable import CarrierCore
import CarrierUI
import SwiftUI
import Testing
@testable import Carrier

private func subagent(_ end: String?, id: String = "a1", title: String, step: String) -> Subagent {
    var events = [
        ChatEvent(id: 1, at: 1_000, kind: "tool_start", callId: id, tool: "Agent"),
        ChatEvent(id: 2, at: 1_100, kind: "task", text: title, callId: id, taskId: "t-\(id)", state: "started", agentType: "general-purpose"),
        ChatEvent(id: 3, at: 1_200, kind: "tool_start", callId: "s-\(id)", tool: "Read", arg: step, parentCallId: id),
    ]
    if let end {
        events.append(ChatEvent(id: 4, at: 61_000, kind: "task", callId: id, taskId: "t-\(id)", state: end, tools: 12, ms: 60_000))
    }
    return subagentsList(in: events).allSubagents.first ?? Subagent(task: events[1])
}

@MainActor private func render(_ view: some View, width: CGFloat, dark: Bool = false, statesByShape: Bool = false, windowSize: CGSize = CGSize(width: 1100, height: 700)) throws -> (height: Int, bytes: [UInt8]) {
    var theme = PieceTheme.standard
    theme.statesByShape = statesByShape
    let renderer = ImageRenderer(
        content: view
            .frame(width: width)
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.pieceTheme, theme)
            .environment(\.windowSize, windowSize)
    )
    renderer.scale = 2
    let image = try #require(renderer.cgImage)
    let data = try #require(image.dataProvider?.data)
    let length = CFDataGetLength(data)
    var bytes = [UInt8](repeating: 0, count: length)
    CFDataGetBytes(data, CFRange(location: 0, length: length), &bytes)
    return (image.height, bytes)
}

// Every row of the Subagents list is one 30 pt line, the height of a "Worked" card's line (60 px at @2x), at 480, 560 and 900 pt of width,
// in every state and with a long title and step, including nested rows with guides and indents.
@MainActor @Test(arguments: [CGFloat(480), 560, 900])
func subagentsListRowKeepsOneHeightInEveryStateAndWidth(width: CGFloat) throws {
    let long = String(repeating: "a very long title or step that has to be cut and not wrapped ", count: 4)
    let states: [String?] = [nil, "completed", "failed", "stopped"]
    let worked = try render(ChatToolGroupView(id: "g", group: ToolGroup(calls: []), live: true, since: 1000, flipped: .constant([])), width: width).height
    #expect(worked == 60)
    var seen: [SubagentStatus] = []
    for end in states {
        for (title, step) in [("Find the adapter", "src/chat/claude.ts"), (long, long)] {
            let item = subagent(end, title: title, step: step)
            seen.append(item.status)
            let row = SubagentsListRow(subagent: item, clock: Date(timeIntervalSince1970: 31), action: {})
            #expect(try render(row, width: width).height == worked)
            #expect(try render(row, width: width, dark: true).height == worked)
            let nested = SubagentsListRow(subagent: item, guides: [true, false], clock: Date(timeIntervalSince1970: 31), action: {})
            #expect(try render(nested, width: width).height == worked)
            #expect(try render(nested, width: width, dark: true).height == worked)
        }
    }
    #expect(Set(seen) == [.running, .completed, .failed, .stopped])
}

@MainActor @Test func subagentsListRowDistinguishesStatesWithoutColourAlone() throws {
    // the clock is the end of the finished runs, so every row reads the same timer and what differs is the lead mark and the dimming
    let clock = Date(timeIntervalSince1970: 61)
    let running = SubagentsListRow(subagent: subagent(nil, title: "Find adapter", step: "src/chat/claude.ts"), clock: clock, action: {})
    let finished = SubagentsListRow(subagent: subagent("completed", title: "Find adapter", step: "src/chat/claude.ts"), clock: clock, action: {})
    let failed = SubagentsListRow(subagent: subagent("failed", title: "Find adapter", step: "src/chat/claude.ts"), clock: clock, action: {})
    let stopped = SubagentsListRow(subagent: subagent("stopped", title: "Find adapter", step: "src/chat/claude.ts"), clock: clock, action: {})

    for dark in [false, true] {
        let runningShot = try render(running, width: 520, dark: dark)
        let finishedShot = try render(finished, width: 520, dark: dark)
        let failedDot = try render(failed, width: 520, dark: dark, statesByShape: false)
        let failedShape = try render(failed, width: 520, dark: dark, statesByShape: true)
        let stoppedShot = try render(stopped, width: 520, dark: dark)

        #expect(runningShot.bytes != finishedShot.bytes)
        #expect(finishedShot.bytes != stoppedShot.bytes)
        #expect(failedDot.bytes != finishedShot.bytes)
        // enabling statesByShape swaps the red dot for the warning glyph so failure does not depend on colour alone
        #expect(failedDot.bytes != failedShape.bytes)
    }
}

@MainActor @Test func subagentsListPopoverFitsRowsAndCapsHeightToWindowWhenLong() throws {
    let clock = Date(timeIntervalSince1970: 31)
    let oneRunning = [SubagentItem(subagent: subagent(nil, id: "a1", title: "One", step: "a.swift"))]
    let oneFinished = [SubagentItem(subagent: subagent("completed", id: "f1", title: "One", step: "a.swift"))]
    let threeItems = (1...3).map { SubagentItem(subagent: subagent("completed", id: "a\($0)", title: "Item \($0)", step: "a.swift")) }
    let twentyItems = (1...20).map { SubagentItem(subagent: subagent("completed", id: "b\($0)", title: "Item \($0)", step: "a.swift")) }

    let hRunningAlone = try render(SubagentsListPopover(list: SubagentsList(launches: [SubagentLaunch(id: "l1", items: oneRunning, startedAt: 0, endedAt: nil)]), clock: clock, select: { _ in }), width: SubagentsListPopover.width).height
    let hFinishedAlone = try render(SubagentsListPopover(list: SubagentsList(launches: [SubagentLaunch(id: "l1", items: oneFinished, startedAt: 0, endedAt: 10)]), clock: clock, select: { _ in }), width: SubagentsListPopover.width).height
    let h3 = try render(SubagentsListPopover(list: SubagentsList(launches: [SubagentLaunch(id: "l1", items: threeItems, startedAt: 0, endedAt: 10)]), clock: clock, select: { _ in }), width: SubagentsListPopover.width).height
    let h20 = try render(SubagentsListPopover(list: SubagentsList(launches: [SubagentLaunch(id: "l1", items: twentyItems, startedAt: 0, endedAt: 10)]), clock: clock, select: { _ in }), width: SubagentsListPopover.width).height
    let hShortWindow = try render(
        SubagentsListPopover(list: SubagentsList(launches: [SubagentLaunch(id: "l1", items: twentyItems, startedAt: 0, endedAt: 10)]), clock: clock, select: { _ in }),
        width: SubagentsListPopover.width,
        windowSize: CGSize(width: 1100, height: 340)
    ).height

    // A single running launch alone shows no bar above it; a finished launch shows its bar above its rows
    #expect(hRunningAlone < hFinishedAlone)
    #expect(hFinishedAlone < h3)
    #expect(h3 < h20)
    #expect(h20 == Int(SubagentsListPopover.maxHeight) * 2)
    #expect(hShortWindow == Int(SubagentsListPopover.allowedHeight(windowHeight: 340)) * 2)
    #expect(hShortWindow < 340 * 2)
}

@MainActor @Test func launchTimeBarDrawsOpenVsFinishedAndUpdatesWithClock() throws {
    let runningLaunch = SubagentLaunch(
        id: "l-run",
        items: [SubagentItem(subagent: subagent(nil, id: "r1", title: "Live", step: "a.swift"))],
        startedAt: 100_000,
        endedAt: nil
    )
    let finishedLaunch = SubagentLaunch(
        id: "l-done",
        items: [SubagentItem(subagent: subagent("completed", id: "d1", title: "Done", step: "a.swift"))],
        startedAt: 10_000,
        endedAt: 60_000
    )
    let t1 = Date(timeIntervalSince1970: 300) // 4 minutes after finishedLaunch ended
    let t2 = Date(timeIntervalSince1970: 360) // 5 minutes after finishedLaunch ended

    for dark in [false, true] {
        let runningShot = try render(LaunchTimeBar(launch: runningLaunch, sessionStart: 0, clock: t1), width: SubagentsListPopover.width, dark: dark)
        let finishedAt4m = try render(LaunchTimeBar(launch: finishedLaunch, sessionStart: 0, clock: t1), width: SubagentsListPopover.width, dark: dark)
        let finishedAt5m = try render(LaunchTimeBar(launch: finishedLaunch, sessionStart: 0, clock: t2), width: SubagentsListPopover.width, dark: dark)
        #expect(runningShot.bytes != finishedAt4m.bytes)
        #expect(finishedAt4m.bytes != finishedAt5m.bytes)
    }
}
