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
