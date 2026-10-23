@testable import CarrierCore
import SwiftUI
import Testing
@testable import Carrier

private func card(_ tool: String = "Bash", status: ToolStatus = .ok, ms: Int? = 80, arg: String = "pnpm test") -> TranscriptCard {
    TranscriptCard(tool: tool, kind: ToolKind(tool: tool), arg: arg, summary: "", status: status, duration: ms.map(formatCallDuration), durationMs: ms)
}

@MainActor private func height(_ view: some View, width: CGFloat = 480) throws -> Int {
    let renderer = ImageRenderer(content: view.frame(width: width))
    renderer.scale = 2
    return try #require(renderer.cgImage).height
}

// A call line is 26 pt whether it is ok, failed, pending, hovered, slow or open, so the log does not jump.
@MainActor @Test func aCallLineKeepsItsHeight() throws {
    let long = String(repeating: "a very long command ", count: 20)
    let cases: [(TranscriptCard, Bool, Bool)] = [
        (card(), false, false), (card(), true, false), (card(ms: 12_000), false, false), (card(status: .error), false, false),
        (card(status: .error), false, true), (card(status: .pending, ms: nil), false, false), (card("Read", arg: "src/a.ts"), true, true),
        (card(arg: long), false, false),
    ]
    for (call, active, open) in cases {
        #expect(try height(CallLineView(card: call, open: open, active: active)) == 52)
    }
}

// A skill is a row of 28 pt.
@MainActor @Test func aSkillRowIs28Points() throws {
    #expect(try height(SkillRowView(card: card("Skill", arg: "solve:ship"))) == 56)
}

// The four rows keep the spec's heights in the light and in the dark appearance.
@MainActor @Test func theRowsKeepTheirHeightsInLightAndDark() throws {
    let slice = LaneSection(
        id: "a", startId: 1, title: "Socket client", sliceTitle: "Socket client", state: .finished, duration: 1000, startedAt: 0, endedAt: 1000,
        resumes: 0, timeLabel: "14:02–14:03", counts: SessionCounts(calls: 4), items: [], slice: 653, laneNumber: 1, pullRequest: "PR #670 merged"
    )
    let calls = [TranscriptItem.tool(id: 1, card()), .tool(id: 2, card())]
    for scheme in [ColorScheme.light, .dark] {
        func rendered(_ view: some View) throws -> CGFloat {
            CGFloat(try height(view.environment(\.colorScheme, scheme))) / 2
        }
        #expect(try rendered(CallLineView(card: card(), open: false, active: false)) == LogMetrics.callLine)
        #expect(try rendered(ToolGroupHeader(calls: calls, open: false)) == LogMetrics.groupLine)
        #expect(try rendered(SkillRowView(card: card("Skill", arg: "solve:ship"))) == LogMetrics.skillRow)
        // line one 28, line two at least 18, 6 below
        #expect(try rendered(LaneHeaderView(lane: slice, open: false)) == LogMetrics.sliceLine + 18 + 6)
    }
}
