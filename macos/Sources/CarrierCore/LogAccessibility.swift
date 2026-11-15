import Foundation

// What VoiceOver says for the rows of the log, built here so it is tested (spec section 4, "Accessibility").

/// A duration in words: "725 milliseconds", "2 seconds", "5.2 seconds", "2 minutes 5 seconds", "1 hour 3 minutes".
public func spokenDuration(_ ms: Int) -> String {
    func unit(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
    if ms < 1000 { return unit(max(0, ms), "millisecond") }
    let tenths = (ms + 50) / 100
    if tenths < 600 { return tenths % 10 == 0 ? unit(tenths / 10, "second") : "\(tenths / 10).\(tenths % 10) seconds" }
    let seconds = max(ms, 60_000) / 1000
    let (hours, minutes) = (seconds / 3600, seconds % 3600 / 60)
    return [hours > 0 ? unit(hours, "hour") : nil, minutes > 0 ? unit(minutes, "minute") : nil, hours == 0 && seconds % 60 > 0 ? unit(seconds % 60, "second") : nil]
        .compactMap { $0 }.joined(separator: " ")
}

/// A call that is a row of its own (a skill): its name, how it ended and how long it took, whether or not the duration is drawn.
/// "solve:ship, succeeded, 725 milliseconds"; a running call has no duration yet.
public func callAccessibilityLabel(_ call: ToolCall) -> String {
    var parts = [call.arg]
    switch call.status {
    case .failed: parts.append("failed")
    case .running: parts.append("running")
    case .stopped: parts.append("stopped")
    case .ok: parts.append("succeeded")
    }
    if call.status != .running, let ms = call.durationMs { parts.append(spokenDuration(ms)) }
    return parts.joined(separator: ", ")
}

/// A slice row: "Slice 246, The engine reads…, lane 1, finished, pull request 250 merged, 17 tool calls, closed".
public func laneAccessibilityLabel(_ lane: LaneSection, open: Bool) -> String {
    let name = lane.slice.map { "Slice \($0), \(lane.title)" } ?? lane.title
    let state = switch lane.state { case .running: "running"; case .finished: "finished"; case .failed: "failed" }
    return [
        name, lane.laneNumber.map { "lane \($0)" }, state, lane.pullRequest.replacingOccurrences(of: "PR #", with: "pull request "),
        lane.isStarting ? nil : countsLine(lane.counts).replacingOccurrences(of: " · ", with: ", "), open ? "open" : "closed",
    ].compactMap { $0 }.joined(separator: ", ")
}

/// The closing row of a session: "Completed, CI passed, closed"; "Needs a human" says nothing of open or closed, there is nothing behind it.
public func resultAccessibilityLabel(_ card: ResultCard, open: Bool) -> String {
    let verdict = card.ci.map { $0.verdict == "passed" ? "CI passed" : $0.verdict == "absent" ? "No CI" : "CI \($0.verdict)" }
    return [card.outcome, verdict, card.hasDetails ? (open ? "open" : "closed") : nil].compactMap { $0 }.joined(separator: ", ")
}
