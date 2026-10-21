@testable import CarrierCore
import SwiftUI
import Testing
@testable import Carrier

private func section(_ state: SessionSection.State, counts: String? = "8 tool calls · 2 edits +42 −8 · 1 test run · 2 errors") -> SessionSection {
    SessionSection(
        id: "a", state: state, agent: "Claude", initial: "C", role: "Fixer", place: "Round 2", counts: counts,
        timeLabel: state == .stopped ? nil : "3m 05s", openByDefault: true
    )
}

@MainActor private func size(_ section: SessionSection, open: Bool = true, width: CGFloat) throws -> CGSize {
    let renderer = ImageRenderer(content: SessionHeaderView(section: section, open: open).frame(width: width))
    renderer.scale = 2
    let image = try #require(renderer.cgImage)
    return CGSize(width: image.width, height: image.height)
}

// A header is one row whatever the session's state or the width of the centre column, with or without a counts line.
@MainActor @Test(arguments: [CGFloat(340), 560, 900])
func aHeaderKeepsItsHeightInEveryStateAndFolded(width: CGFloat) throws {
    let height = try size(section(.done), width: width).height
    for state in [SessionSection.State.running, .stopped, .done] {
        #expect(try size(section(state), width: width).height == height)
        #expect(try size(section(state), open: false, width: width).height == height)
    }
    #expect(try size(section(.done, counts: nil), width: width).height == height)
}
