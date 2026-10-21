@testable import CarrierCore
import SwiftUI
import Testing
@testable import Carrier

private func lane(hint: Bool) -> LaneSection { LaneSection(id: "a", title: "Lane 1 · #653", hint: hint, counts: "4 tool calls", items: []) }

@MainActor private func height(_ lane: LaneSection, open: Bool) throws -> Int {
    let renderer = ImageRenderer(content: LaneHeaderView(lane: lane, open: open).frame(width: 480))
    renderer.scale = 2
    return try #require(renderer.cgImage).height
}

// A lane header is one row, folded or open, with or without the hint mark.
@MainActor @Test func aLaneHeaderKeepsItsHeight() throws {
    let base = try height(lane(hint: true), open: true)
    #expect(try height(lane(hint: true), open: false) == base)
    #expect(try height(lane(hint: false), open: true) == base)
}
