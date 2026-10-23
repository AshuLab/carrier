@testable import CarrierCore
import SwiftUI
import Testing
@testable import Carrier

private func lane(_ state: SubagentState = .finished, lane: Int? = 1) -> LaneSection {
    LaneSection(
        id: "a", title: "Socket client", sliceTitle: "Socket client", state: state, duration: state == .running ? nil : 180_000,
        counts: "4 tool calls", items: [], slice: 653, laneNumber: lane
    )
}

@MainActor private func height(_ lane: LaneSection, open: Bool) throws -> Int {
    let renderer = ImageRenderer(content: LaneHeaderView(lane: lane, open: open).frame(width: 480))
    renderer.scale = 2
    return try #require(renderer.cgImage).height
}

// A slice's row is the same height folded or open, running, finished or failed, with or without a lane.
@MainActor @Test func aLaneHeaderKeepsItsHeight() throws {
    let base = try height(lane(), open: true)
    #expect(try height(lane(), open: false) == base)
    for state in [SubagentState.running, .failed] { #expect(try height(lane(state), open: true) == base) }
    #expect(try height(lane(lane: nil), open: true) == base)
}
