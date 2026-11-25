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

// The two lines of the title fit the 34 pt of the round buttons at every text size Settings offers: they were 39 pt tall at 130 %.
@MainActor @Test(arguments: [90, 100, 110, 115, 120, 130])
func theTitleLinesFitTheHeaderAtEveryTextSize(percent: Int) throws {
    let scale = TypeScale(percent: percent)
    let bases = SubagentTitle.bases(percent: percent)
    let lines = VStack(alignment: .leading, spacing: 1) {
        Text("Find the adapter").font(.system(size: scale.size(bases.title), weight: .semibold)).lineLimit(1)
        Text("Explore · Subagent of Fix the login").font(.system(size: scale.size(bases.subtitle))).lineLimit(1)
    }
    let renderer = ImageRenderer(content: lines)
    renderer.scale = 2
    let image = try #require(renderer.cgImage)
    #expect(Double(image.height) / 2 <= SubagentTitle.height)
    // up to its cap the title still follows the text size, and at 100 % it is the 13 and 11 pt it was
    if percent == 100 { #expect(scale.size(bases.title) == 13 && scale.size(bases.subtitle) == 11) }
    #expect(scale.size(bases.title) <= 14 && scale.size(bases.subtitle) <= 12)
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

// A slice card's header (the epic's title in the subtitle) is as high as the conversation's for Builder and Reviewer, running, finished and
// failed, at every width, with a short slice title or a long one.
@MainActor @Test(arguments: [CGFloat(480), 560, 900])
func aSliceCardsHeaderKeepsTheConversationHeadersHeightForEveryRoleAndState(width: CGFloat) throws {
    func lane(_ state: SubagentState, title: String) -> LaneSection {
        LaneSection(
            id: "a", startId: 1, title: title, sliceTitle: title, state: state, duration: 180_000, startedAt: 0, endedAt: state == .running ? nil : 180_000,
            resumes: 0, timeLabel: nil, counts: SessionCounts(calls: 4), items: [], slice: 653, laneNumber: 1, pullRequest: "no PR yet"
        )
    }
    let epic = String(repeating: "Rotate the keys of every environment and say so ", count: 3)
    for role in ["Builder", "Reviewer"] {
        for state in [SubagentState.running, .finished, .failed] {
            for title in ["Socket client", String(repeating: "a slice title that is far too long ", count: 4)] {
                let header = SubagentHeader(lane: lane(state, title: title), role: role, epic: epic)
                #expect(header.subtitle(of: "unused").hasPrefix("\(role) · Rotate"))
                let drawn = try size(header, width: width)
                #expect(drawn.width == width * 2)
                #expect(drawn.height == SubagentTitle.height * 2)
            }
        }
    }
}

// A running lane whose start has not arrived (an agent id event before `task_started`) has no timer to show: not the time since 1970.
@Test func aRunningSliceCardWithNoStartSaysRunningWithoutATimer() {
    let lane = LaneSection(
        id: "a", startId: 1, title: "Socket client", sliceTitle: "Socket client", state: .running, duration: nil, startedAt: nil, endedAt: nil,
        resumes: 0, timeLabel: nil, counts: SessionCounts(calls: 1), items: [], slice: 653, laneNumber: 1, pullRequest: "no PR yet"
    )
    let header = SubagentHeader(lane: lane, role: "Builder", epic: "The epic")
    #expect(header.startedAt == nil)
    #expect(header.stateWords(now: 1_800_000_000_000, bundle: Copy.bundle("en"), locale: Locale(identifier: "en_US")) == "Running")
}
