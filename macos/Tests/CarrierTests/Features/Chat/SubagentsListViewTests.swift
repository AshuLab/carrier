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
    guard case .tools(_, let group)? = chatFeed(events).first else { return Subagent(task: events[1]) }
    return group.subagents[0]
}

@MainActor private func render(_ view: some View, width: CGFloat, dark: Bool = false, statesByShape: Bool = false) throws -> (height: Int, bytes: [UInt8]) {
    var theme = PieceTheme.standard
    theme.statesByShape = statesByShape
    let renderer = ImageRenderer(
        content: view
            .frame(width: width)
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.pieceTheme, theme)
    )
    renderer.scale = 2
    let image = try #require(renderer.cgImage)
    let data = try #require(image.dataProvider?.data)
    let length = CFDataGetLength(data)
    var bytes = [UInt8](repeating: 0, count: length)
    CFDataGetBytes(data, CFRange(location: 0, length: length), &bytes)
    return (image.height, bytes)
}

// Every row of the Subagents list is one 30 pt line (60 px at @2x) at 480, 560 and 900 pt of width, in every state and with a long title and step.
@MainActor @Test(arguments: [CGFloat(480), 560, 900])
func subagentsListRowKeepsOneHeightInEveryStateAndWidth(width: CGFloat) throws {
    let long = String(repeating: "a very long title or step that has to be cut and not wrapped ", count: 4)
    let states: [String?] = [nil, "completed", "failed", "stopped"]
    var seen: [SubagentStatus] = []
    for end in states {
        for (title, step) in [("Find the adapter", "src/chat/claude.ts"), (long, long)] {
            let item = subagent(end, title: title, step: step)
            seen.append(item.status)
            let row = SubagentsListRow(subagent: item, clock: Date(timeIntervalSince1970: 31), action: {})
            #expect(try render(row, width: width).height == 60)
            #expect(try render(row, width: width, dark: true).height == 60)
        }
    }
    #expect(Set(seen) == [.running, .completed, .failed, .stopped])
}

@MainActor @Test func subagentsListRowDistinguishesStatesWithoutColourAlone() throws {
    let clock = Date(timeIntervalSince1970: 31)
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

@MainActor @Test func subagentsListPopoverFitsRowsAndCapsHeightWhenLong() throws {
    let clock = Date(timeIntervalSince1970: 31)
    let oneItem = [SubagentItem(subagent: subagent(nil, id: "a1", title: "One", step: "a.swift"))]
    let threeItems = (1...3).map { SubagentItem(subagent: subagent("completed", id: "a\($0)", title: "Item \($0)", step: "a.swift")) }
    let twentyItems = (1...20).map { SubagentItem(subagent: subagent("completed", id: "b\($0)", title: "Item \($0)", step: "a.swift")) }

    let h1 = try render(SubagentsListPopover(list: SubagentsList(launches: [SubagentLaunch(id: "l1", items: oneItem, startedAt: 0, endedAt: nil)]), clock: clock, select: { _ in }), width: SubagentsListPopover.width).height
    let h3 = try render(SubagentsListPopover(list: SubagentsList(launches: [SubagentLaunch(id: "l1", items: threeItems, startedAt: 0, endedAt: 10)]), clock: clock, select: { _ in }), width: SubagentsListPopover.width).height
    let h20 = try render(SubagentsListPopover(list: SubagentsList(launches: [SubagentLaunch(id: "l1", items: twentyItems, startedAt: 0, endedAt: 10)]), clock: clock, select: { _ in }), width: SubagentsListPopover.width).height

    #expect(h1 < h3)
    #expect(h3 < h20)
    #expect(h20 == Int(SubagentsListPopover.maxHeight) * 2)
}
