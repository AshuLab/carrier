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
