import Testing
@testable import CarrierCore

private func card(_ arg: String = "pnpm test", status: ToolStatus = .ok, ms: Int? = 80, tool: String = "Bash") -> TranscriptCard {
    TranscriptCard(tool: tool, kind: ToolKind(tool: tool), arg: arg, summary: "", status: status, duration: ms.map(formatCallDuration), durationMs: ms)
}

@Test func aDurationIsSpokenInWords() {
    #expect(spokenDuration(725) == "725 milliseconds")
    #expect(spokenDuration(1) == "1 millisecond")
    #expect(spokenDuration(2000) == "2 seconds")
    #expect(spokenDuration(1000) == "1 second")
    #expect(spokenDuration(5240) == "5.2 seconds")
    #expect(spokenDuration(125_000) == "2 minutes 5 seconds")
    #expect(spokenDuration(59_990) == "1 minute")
    #expect(spokenDuration(3_780_000) == "1 hour 3 minutes")
}

@Test func aCallLineSaysItsCommandItsOutcomeAndItsDuration() {
    #expect(callAccessibilityLabel(card(status: .error, ms: 725)) == "pnpm test, failed, 725 milliseconds")
    #expect(callAccessibilityLabel(card(ms: 2000)) == "pnpm test, succeeded, 2 seconds")
    #expect(callAccessibilityLabel(card(status: .pending, ms: nil)) == "pnpm test, running")
    #expect(callAccessibilityLabel(card("cd /w && git status && git diff && ls", ms: 40)) == "git status, 2 more commands, succeeded, 40 milliseconds")
    #expect(callAccessibilityLabel(card("solve:ship", ms: nil, tool: "Skill")) == "solve:ship, succeeded")
}

@Test func aGroupSaysItsCountItsDurationAndWhetherItIsOpenWithAHint() {
    let calls: [TranscriptItem] = (1...4).map { .tool(id: $0, card(ms: $0 == 1 ? 3200 : 667)) }
    #expect(callGroupAccessibilityLabel(calls, open: false) == "Ran 4 commands, 5.2 seconds, closed")
    #expect(callGroupAccessibilityLabel(calls + [.tool(id: 5, card("src/a.ts", tool: "Read"))], open: true) == "Ran 4 commands, read 1 file, 5.3 seconds, open")
    #expect(callGroupAccessibilityLabel([TranscriptItem.tool(id: 1, card(ms: nil)), .tool(id: 2, card(ms: nil))], open: false) == "Ran 2 commands, closed")
    #expect(callGroupAccessibilityHint(open: false) == "Shows the calls")
    #expect(callGroupAccessibilityHint(open: true) == "Hides the calls")
}

@Test func aSliceRowSaysItsSliceLaneStatePullRequestAndCounts() {
    var lane = LaneSection(
        id: "a", startId: 1, title: "The engine reads", sliceTitle: "The engine reads", state: .finished, duration: 1000, startedAt: 0, endedAt: 1000,
        resumes: 0, timeLabel: nil, counts: SessionCounts(calls: 17), items: [], slice: 246, laneNumber: 1, pullRequest: "PR #250 merged"
    )
    #expect(laneAccessibilityLabel(lane, open: false) == "Slice 246, The engine reads, lane 1, finished, pull request 250 merged, 17 tool calls, closed")
    (lane.slice, lane.laneNumber, lane.pullRequest, lane.state) = (nil, nil, "no PR yet", .failed)
    lane.counts = SessionCounts(calls: 3, edits: 1, added: 4, removed: 2, errors: 1)
    #expect(laneAccessibilityLabel(lane, open: true) == "The engine reads, failed, no PR yet, 3 tool calls, 1 edit +4 −2, 1 error, open")
    // just taken: nothing to count yet
    (lane.state, lane.counts) = (.running, SessionCounts())
    #expect(laneAccessibilityLabel(lane, open: false) == "The engine reads, running, no PR yet, closed")
}
