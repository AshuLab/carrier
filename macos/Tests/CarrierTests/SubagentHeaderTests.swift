@testable import CarrierCore
import SwiftUI
import Testing
@testable import Carrier

private func header(_ state: SubagentStatus, title: String) -> SubagentHeader {
    SubagentHeader(title: title, type: "general-purpose", state: state, startedAt: 0, durationMs: state == .running ? nil : 125_000)
}

/// The title and the state as the toolbar lays them out beside the round buttons, at a width of the centre column.
@MainActor private func size(_ header: SubagentHeader, width: CGFloat, dark: Bool = false) throws -> CGSize {
    let row = HStack(spacing: 10) {
        SubagentTitle(title: header.title, subtitle: header.subtitle(of: "Fix the login that fails when the token is old and the clock is wrong"))
        Spacer(minLength: 0)
        SubagentStatePill(header: header, clock: Date(timeIntervalSince1970: 71))
    }
    let renderer = ImageRenderer(content: row.environment(\.colorScheme, dark ? .dark : .light).frame(width: width))
    renderer.scale = 2
    let image = try #require(renderer.cgImage)
    return CGSize(width: image.width, height: image.height)
}

// The header is as high as the conversation's (the round glass buttons, 34 pt) in each of the four states and at every width, with a short
// title or one of 120 characters: what does not fit is cut, never wrapped.
@MainActor @Test(arguments: [CGFloat(480), 560, 900])
func theSubagentHeaderKeepsTheConversationHeadersHeightInEveryStateAndWidth(width: CGFloat) throws {
    let long = String(repeating: "a title of the subagent that is far too long ", count: 3).prefix(120)
    #expect(long.count == 120)
    var seen: [SubagentStatus] = []
    for state in [SubagentStatus.running, .completed, .failed, .stopped] {
        for title in ["Find the adapter", String(long)] {
            seen.append(state)
            for dark in [false, true] {
                let drawn = try size(header(state, title: title), width: width, dark: dark)
                #expect(drawn.width == width * 2)
                #expect(drawn.height == SubagentTitle.height * 2)
            }
        }
    }
    #expect(Set(seen).count == 4)
}

// The pill is one line of the same height whatever it says, and the timer of a running one does not change it.
@MainActor @Test func theStatePillIsOneHeightInEveryState() throws {
    func height(_ state: SubagentStatus) throws -> Int {
        let renderer = ImageRenderer(content: SubagentStatePill(header: header(state, title: "T"), clock: Date(timeIntervalSince1970: 3_725)))
        renderer.scale = 2
        return try #require(renderer.cgImage).height
    }
    let running = try height(.running)
    #expect(running == 48)
    for state in [SubagentStatus.completed, .failed, .stopped] { #expect(try height(state) == running) }
}
