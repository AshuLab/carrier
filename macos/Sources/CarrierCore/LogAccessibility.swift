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

/// A call line: its command, how it ended and how long it took, whether or not the duration is drawn.
/// "git status, 7 more commands, failed, 725 milliseconds"; a running call has no duration yet. Given `open`, a call that has
/// details (it opens) also says "open" or "closed".
public func callAccessibilityLabel(_ card: TranscriptCard, open: Bool? = nil) -> String {
    var parts = [card.title]
    if card.moreCommands > 0 { parts.append("\(card.moreCommands) more commands") }
    switch card.status {
    case .error: parts.append("failed")
    case .pending: parts.append("running")
    case .ok: parts.append("succeeded")
    }
    if card.status != .pending, let ms = card.durationMs { parts.append(spokenDuration(ms)) }
    if let open, card.hasDetails { parts.append(open ? "open" : "closed") }
    return parts.joined(separator: ", ")
}

/// A group: "Ran 4 commands, 5.2 seconds, closed".
public func callGroupAccessibilityLabel(_ calls: [TranscriptItem], open: Bool) -> String {
    let ms = calls.compactMap { item -> Int? in if case .tool(_, let card) = item { card.durationMs } else { nil } }
    let spoken = ms.isEmpty ? nil : spokenDuration(ms.reduce(0, +))
    return [callGroupLabel(calls).replacingOccurrences(of: " · ", with: ", "), spoken, open ? "open" : "closed"]
        .compactMap { $0 }.joined(separator: ", ")
}

public func callGroupAccessibilityHint(open: Bool) -> String { open ? "Hides the calls" : "Shows the calls" }

/// A slice row: "Slice 246, The engine reads…, lane 1, finished, pull request 250 merged, 17 tool calls, closed".
public func laneAccessibilityLabel(_ lane: LaneSection, open: Bool) -> String {
    let name = lane.slice.map { "Slice \($0), \(lane.title)" } ?? lane.title
    let state = switch lane.state { case .running: "running"; case .finished: "finished"; case .failed: "failed" }
    return [
        name, lane.laneNumber.map { "lane \($0)" }, state, lane.pullRequest.replacingOccurrences(of: "PR #", with: "pull request "),
        lane.isStarting ? nil : countsLine(lane.counts).replacingOccurrences(of: " · ", with: ", "), open ? "open" : "closed",
    ].compactMap { $0 }.joined(separator: ", ")
}
