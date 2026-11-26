@testable import CarrierCore
import SwiftUI
import Testing
@testable import Carrier

private func row(_ end: String?, title: String, step: String) -> Subagent {
    var events = [
        ChatEvent(id: 1, at: 1_000, kind: "tool_start", callId: "a1", tool: "Agent"),
        ChatEvent(id: 2, at: 1_100, kind: "task", text: title, callId: "a1", taskId: "t1", state: "started", agentType: "general-purpose"),
        ChatEvent(id: 3, at: 1_200, kind: "tool_start", callId: "s1", tool: "Read", arg: step, parentCallId: "a1"),
    ]
    if let end { events.append(ChatEvent(id: 4, at: 61_000, kind: "task", callId: "a1", taskId: "t1", state: end, tools: 12, ms: 60_000)) }
    guard case .tools(_, let group)? = chatFeed(events).first else { return Subagent(task: events[1]) }
    return group.subagents[0]
}

@MainActor private func height(_ view: some View, width: CGFloat) throws -> Int {
    let renderer = ImageRenderer(content: view.frame(width: width))
    renderer.scale = 2
    return try #require(renderer.cgImage).height
}

@MainActor private func headerBytes(_ view: some View, width: CGFloat) throws -> [UInt8] {
    let suite = UserDefaults(suiteName: "SubagentRowTests.flat")!
    suite.set("flat", forKey: AppPreferences.chatSurfaceKey)
    let renderer = ImageRenderer(content: view.defaultAppStorage(suite).frame(width: width))
    renderer.scale = 2
    let image = try #require(renderer.cgImage)
    let crop = try #require(image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: 60)))
    let data = try #require(crop.dataProvider?.data)
    let length = CFDataGetLength(data)
    var bytes = [UInt8](repeating: 0, count: length)
    CFDataGetBytes(data, CFRange(location: 0, length: length), &bytes)
    return bytes
}

// A subagent's row is one height, that of a "Worked" card's line (30 pt), in each of its four states and at every width, with a short or a very
// long title and step: what does not fit is cut, never wrapped.
@MainActor @Test(arguments: [CGFloat(480), 560, 900])
func aSubagentRowKeepsOneHeightInEveryStateAndWidth(width: CGFloat) throws {
    let long = String(repeating: "a very long title or step that has to be cut and not wrapped ", count: 4)
    let states: [String?] = [nil, "completed", "failed", "stopped"]
    let worked = try height(ChatToolGroupView(id: "g", group: ToolGroup(calls: []), live: true, since: 1000, flipped: .constant([])), width: width)
    #expect(worked == 60)
    var seen: [SubagentStatus] = []
    for end in states {
        for (title, step) in [("Find the adapter", "src/chat/claude.ts"), (long, long)] {
            let subagent = row(end, title: title, step: step)
            seen.append(subagent.status)
            let view = SubagentRowView(subagent: subagent, clock: Date(timeIntervalSince1970: 31))
            #expect(try height(view, width: width) == worked)
            #expect(try height(view.environment(\.colorScheme, .dark), width: width) == worked)
            // where a tap opens it, the chevron is there and the row is no taller
            #expect(try height(view.environment(\.openSubagent) { _ in }, width: width) == worked)
        }
    }
    #expect(Set(seen) == [.running, .completed, .failed, .stopped])
}

@MainActor @Test(arguments: [CGFloat(480), 560, 900])
func aSubagentResultBlockFoldsSummariesLongerThanSixLinesToOneHeight(width: CGFloat) throws {
    let oneLine = SubagentResultCard(result: SubagentResult(text: "Found the adapter in src/chat/claude.ts.", failed: false))
    let sixLines = SubagentResultCard(result: SubagentResult(text: (1...6).map { "Line \($0)" }.joined(separator: "\n"), failed: false))
    let sevenLines = SubagentResultCard(result: SubagentResult(text: (1...7).map { "Line \($0)" }.joined(separator: "\n"), failed: false))
    let twentyLines = SubagentResultCard(result: SubagentResult(text: (1...20).map { "Line \($0)" }.joined(separator: "\n"), failed: false))
    let expandedTwenty = SubagentResultCard(result: SubagentResult(text: (1...20).map { "Line \($0)" }.joined(separator: "\n"), failed: false), startsExpanded: true)
    let failedOnly = SubagentResultCard(result: SubagentResult(text: nil, failed: true))

    let h1 = try height(oneLine, width: width)
    let h6 = try height(sixLines, width: width)
    let h7 = try height(sevenLines, width: width)
    let h20 = try height(twentyLines, width: width)
    let h20Expanded = try height(expandedTwenty, width: width)
    let hFailed = try height(failedOnly, width: width)

    #expect(hFailed == 60)
    #expect(h1 < h6)
    #expect(h6 < h7)
    #expect(h7 == h20)
    #expect(h20 < h20Expanded)
    #expect(try height(sevenLines.environment(\.colorScheme, .dark), width: width) == h7)
}

// The Brief card is capped at two lines when folded, hides its header control for one or two lines, and expands to the full text when opened.
@MainActor @Test(arguments: [CGFloat(480), 560, 900])
func aSubagentBriefCardFoldsLongBriefsToTwoLinesAndHidesItsControlForOneOrTwoLines(width: CGFloat) throws {
    let oneLine = SubagentBriefCard(text: "Find the adapter in src/chat/claude.ts.")
    let twoLines = SubagentBriefCard(text: "Line 1\nLine 2")
    let threeLines = SubagentBriefCard(text: (1...3).map { "Line \($0)" }.joined(separator: "\n"))
    let twentyLines = SubagentBriefCard(text: (1...20).map { "Line \($0)" }.joined(separator: "\n"))
    let expandedTwenty = SubagentBriefCard(text: (1...20).map { "Line \($0)" }.joined(separator: "\n"), startsExpanded: true)

    let h1 = try height(oneLine, width: width)
    let h2 = try height(twoLines, width: width)
    let h3 = try height(threeLines, width: width)
    let h20 = try height(twentyLines, width: width)
    let h20Expanded = try height(expandedTwenty, width: width)

    #expect(h1 < h2)
    #expect(h2 == h3)
    #expect(h3 == h20)
    #expect(h20 < h20Expanded)
    #expect(try height(threeLines.environment(\.colorScheme, .dark), width: width) == h3)
    #expect(try headerBytes(oneLine, width: width) == headerBytes(twoLines, width: width))
    #expect(try headerBytes(threeLines, width: width) != headerBytes(twoLines, width: width))
}

@MainActor @Test func aSubagentBriefCardsWordsAreEnglishAndReadAloudWhatTheControlDoes() {
    let en = Copy.bundle("en")
    let enLocale = Locale(identifier: "en_US")
    #expect(Copy.chatSubagentBrief(bundle: en, locale: enLocale) == "Brief")
    #expect(Copy.chatSubagentBriefShowMore(bundle: en, locale: enLocale) == "Show more")
    #expect(Copy.chatSubagentBriefShowLess(bundle: en, locale: enLocale) == "Show less")
    #expect(Copy.chatSubagentBriefExpandSpoken(bundle: en, locale: enLocale) == "Show full brief")
    #expect(Copy.chatSubagentBriefCollapseSpoken(bundle: en, locale: enLocale) == "Fold brief")
}

@MainActor @Test(arguments: [CGFloat(480), 560, 900])
func aSubagentViewRendersWithAndWithoutABriefInConversationAndSliceViews(width: CGFloat) throws {
    let header = SubagentHeader(title: "Find adapter", type: "Explore", state: .completed, startedAt: 1_000, durationMs: 4_000)
    let sliceHeader = SubagentHeader(title: "Slice #1", type: "Builder", state: .completed, startedAt: 1_000, durationMs: 4_000, epic: "Epic")
    let withBrief = SubagentView(work: SubagentWork(header: header, brief: "Line 1\nLine 2\nLine 3", items: []), backToChat: {}).frame(width: width, height: 600)
    let withoutBrief = SubagentView(work: SubagentWork(header: header, brief: nil, items: []), backToChat: {}).frame(width: width, height: 600)
    let sliceView = SubagentView(work: SubagentWork(header: sliceHeader, brief: nil, items: []), backToChat: {}).frame(width: width, height: 600)

    for view in [AnyView(withBrief), AnyView(withoutBrief), AnyView(sliceView)] {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        #expect(try #require(renderer.cgImage).height == 1200)
    }
}
