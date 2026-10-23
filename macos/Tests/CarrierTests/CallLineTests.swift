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
