import Testing
@testable import CarrierCore

private func call(_ arg: String = "solve:ship", status: CallStatus = .ok, ms: Int? = 80) -> ToolCall {
    var call = ToolCall(start: ChatEvent(id: 1, at: 1000, kind: "tool_start", callId: "c", tool: "Skill", arg: arg))
    call.status = status
    call.endedAt = ms.map { 1000 + $0 }
    return call
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

@Test func aSkillRowSaysItsNameItsOutcomeAndItsDuration() {
    #expect(callAccessibilityLabel(call(status: .failed, ms: 725)) == "solve:ship, failed, 725 milliseconds")
    #expect(callAccessibilityLabel(call(ms: 2000)) == "solve:ship, succeeded, 2 seconds")
    #expect(callAccessibilityLabel(call(status: .running, ms: nil)) == "solve:ship, running")
    #expect(callAccessibilityLabel(call(status: .stopped, ms: nil)) == "solve:ship, stopped")
    #expect(callAccessibilityLabel(call(ms: nil)) == "solve:ship, succeeded")
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
