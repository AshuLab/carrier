@testable import CarrierCore
import SwiftUI
import Testing
@testable import Carrier

private func skill(status: CallStatus = .ok, ms: Int? = 80) -> ToolCall {
    var call = ToolCall(start: ChatEvent(id: 1, at: 1000, kind: "tool_start", callId: "c", tool: "Skill", arg: "solve:ship"))
    call.status = status
    call.endedAt = ms.map { 1000 + $0 }
    return call
}

@MainActor private func height(_ view: some View, width: CGFloat = 480) throws -> Int {
    let renderer = ImageRenderer(content: view.frame(width: width))
    renderer.scale = 2
    return try #require(renderer.cgImage).height
}

// A skill is a row of 28 pt whether it is ok, failed or running, in the light and in the dark appearance.
@MainActor @Test func aSkillRowIs28Points() throws {
    for scheme in [ColorScheme.light, .dark] {
        for call in [skill(), skill(status: .failed), skill(status: .running, ms: nil), skill(ms: 12_000)] {
            #expect(try height(SkillRowView(call: call).environment(\.colorScheme, scheme)) == Int(LogMetrics.skillRow) * 2)
        }
    }
}

// The live line keeps its 30 pt height for every chip and for a 60-character MCP server name at widths 480, 560 and 900.
@MainActor @Test(arguments: [CGFloat(480), 560, 900])
func aLiveLineKeepsItsHeightForEveryChipAndLongMcpServer(width: CGFloat) throws {
    func running(_ tool: String, arg: String = "src/chat/claude.ts") -> ToolGroup {
        let rows = chatFeed([ChatEvent(id: 1, at: 1000, kind: "tool_start", callId: "c", tool: tool, arg: arg)])
        if case .tools(_, let group)? = rows.first { return group }
        return ToolGroup(calls: [])
    }
    let longServer = String(repeating: "very_long_mcp_server_", count: 3).prefix(60)
    let cases: [(ToolGroup, Bool)] = [
        (running("WebFetch", arg: "https://example.test"), false),
        (ToolGroup(calls: []), false),
        (running("Read"), false),
        (running("Grep", arg: "KindChip"), false),
        (running("Edit"), false),
        (running("Bash", arg: "pnpm test --run"), false),
        (running("mcp__linear__create_issue", arg: #"{"title":"Subagent"}"#), false),
        (running("mcp__\(longServer)__create_issue", arg: #"{"title":"Subagent"}"#), false),
        (running("Bash", arg: "git push origin main"), true),
    ]
    let baseline = try height(
        ChatToolGroupView(id: "base", group: cases[0].0, live: true, waiting: false, since: 1000, flipped: .constant([])),
        width: width
    )
    #expect(baseline == 60)
    for scheme in [ColorScheme.light, .dark] {
        for (index, item) in cases.enumerated() {
            let view = ChatToolGroupView(id: "g\(index)", group: item.0, live: true, waiting: item.1, since: 1000, flipped: .constant([]))
                .environment(\.colorScheme, scheme)
            #expect(try height(view, width: width) == baseline)
        }
        #expect(try height(KindChipView(chip: .subagents(3)).environment(\.colorScheme, scheme), width: width) < baseline)
    }
}

// The right side of the live line with both timers and with the amber one does not wrap or move the words: the line is as high as the plain one, at every width.
@MainActor @Test(arguments: [CGFloat(480), 560, 900])
func theLiveLineKeepsItsHeightWithBothTimersAndTheAmberOne(width: CGFloat) throws {
    let turnStart = 1_000_000
    func running(_ tool: String, startedAt: Int) -> ToolGroup {
        if case .tools(_, let group)? = chatFeed([ChatEvent(id: 1, at: startedAt, kind: "tool_start", callId: "c", tool: tool, arg: "pnpm test")]).first { return group }
        return ToolGroup(calls: [])
    }
    func line(_ group: ToolGroup, now: Int, scheme: ColorScheme) -> some View {
        ChatToolGroupView(id: "g", group: group, live: true, since: turnStart, clock: Date(timeIntervalSince1970: Double(now) / 1000), flipped: .constant([]))
            .environment(\.colorScheme, scheme)
    }
    for scheme in [ColorScheme.light, .dark] {
        let plain = line(ToolGroup(calls: []), now: turnStart + 2_000, scheme: scheme)
        let baseline = try height(plain, width: width)
        #expect(baseline == 60)
        // both timers: the call is 5 s old inside a turn of 125 s
        let both = running("Bash", startedAt: turnStart + 120_000)
        #expect(both.liveTimer(now: turnStart + 125_000, turnStart: turnStart).turnMs == 125_000)
        #expect(try height(line(both, now: turnStart + 125_000, scheme: scheme), width: width) == baseline)
        // the amber one: a shell call of 3 minutes 20 s inside a turn of 3 minutes 25 s, and an MCP one of 31 s
        let slow = running("Bash", startedAt: turnStart + 5_000)
        #expect(slow.liveTimer(now: turnStart + 205_000, turnStart: turnStart).slow)
        #expect(try height(line(slow, now: turnStart + 205_000, scheme: scheme), width: width) == baseline)
        let mcp = running("mcp__\(String(repeating: "very_long_mcp_server_", count: 3))__create_issue", startedAt: turnStart)
        #expect(try height(line(mcp, now: turnStart + 31_000, scheme: scheme), width: width) == baseline)
    }
}
