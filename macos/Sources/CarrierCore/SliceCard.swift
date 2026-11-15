import Foundation

// The epic's slices as one card in the builder's session: a line with how many are merged and a row per slice (docs/macos-ui.md, "The slices
// card"). A pure function of what a session already has, its subagents (`LaneSection`) and, for the slices that have not started, the
// epic reply; a number that is missing is left out of the line, never made up.

public enum SliceMark: Equatable {
    /// The subagent finished.
    case done
    case working
    /// Not started: ready, or waiting for the slices that block it.
    case waiting
    /// The subagent did not complete.
    case failed
}

/// What the PR chip's dot says; the word is on the chip.
public enum SlicePRState: Equatable {
    case merged, open, draft, closed
    /// A pull request from an engine that predates the state.
    case unknown

    init(_ state: String?) {
        switch state {
        case "merged": self = .merged
        case "open": self = .open
        case "draft": self = .draft
        case "closed": self = .closed
        default: self = .unknown
        }
    }
}

/// One part of a row's quiet line.
public struct SliceQuiet: Equatable {
    public enum Kind: Equatable { case plain, error, lane }

    public var text: String
    public var kind: Kind
}

public struct SliceCardRow: Equatable, Identifiable {
    /// The subagent's id; `slice-N` for a slice that has not started.
    public var id: String
    /// nil for a subagent whose description names no slice.
    public var number: Int?
    public var title: String
    public var mark: SliceMark
    /// Calls, edits, test runs, errors, the lane when slices run in parallel and the time range, in this order, those that are known.
    public var quiet: [SliceQuiet]
    public var prNumber: Int?
    public var prState: SlicePRState
    /// What opens under the row; nil for a slice that has not started: nothing to open.
    public var lane: LaneSection?
    /// Only the first slice, and only while it works.
    public var openByDefault: Bool
    /// What VoiceOver reads, without open or closed.
    public var spoken: String

    public var canOpen: Bool { lane != nil }
}

public enum SliceLead: Equatable { case done, working, waiting, failed }

public struct SliceCard: Equatable {
    public var rows: [SliceCardRow]
    /// "3 of 3 merged", "1 of 3 merged · 2 working", "1 of 3 merged · 1 failed".
    public var summary: String
    public var lead: SliceLead
    /// One short bar per row, in order, for the mini progress.
    public var segments: [SliceMark]
    /// "since 14:02" while anything is not done; how long it took (the first start to the last end) once all are; nil with no start.
    public var time: String?
}

private func plural(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }

/// Whether two subagents ran at the same time, by their times; one still running has no end yet.
private func overlap(_ a: LaneSection, _ b: LaneSection) -> Bool {
    guard let a0 = a.startedAt, let b0 = b.startedAt else { return false }
    return a0 < (b.endedAt ?? Int.max) && b0 < (a.endedAt ?? Int.max)
}

private func mark(_ state: SubagentState) -> SliceMark {
    switch state {
    case .running: .working
    case .finished: .done
    case .failed: .failed
    }
}

/// `lanes` are the session's subagents in order; `waiting` the epic's slices that have not started (the caller passes them while the
/// builder runs, none once it ended). Skipped slices are not rows.
public func sliceCard(lanes: [LaneSection], waiting: [EpicReply.Slice] = [], time format: TimeFormat = .stored()) -> SliceCard {
    let parallel = lanes.indices.contains { i in lanes.indices.contains { $0 != i && overlap(lanes[$0], lanes[i]) } }
    var rows: [SliceCardRow] = lanes.enumerated().map { index, lane in
        let mark = mark(lane.state)
        var quiet: [SliceQuiet] = []
        if lane.isStarting {
            quiet.append(SliceQuiet(text: "starting…", kind: .plain))
        } else {
            if lane.counts.calls > 0 { quiet.append(SliceQuiet(text: plural(lane.counts.calls, "call") + (mark == .working ? " so far" : ""), kind: .plain)) }
            if lane.counts.edits > 0 { quiet.append(SliceQuiet(text: plural(lane.counts.edits, "edit"), kind: .plain)) }
            if lane.counts.tests > 0 { quiet.append(SliceQuiet(text: plural(lane.counts.tests, "test run"), kind: .plain)) }
            if lane.counts.errors > 0 { quiet.append(SliceQuiet(text: plural(lane.counts.errors, "error"), kind: .error)) }
            if mark == .failed { quiet.append(SliceQuiet(text: "did not complete", kind: .error)) }
            if parallel, let number = lane.laneNumber { quiet.append(SliceQuiet(text: "Lane \(number)", kind: .lane)) }
            if mark != .working, let range = lane.timeLabel { quiet.append(SliceQuiet(text: range, kind: .plain)) }
        }
        let prState = SlicePRState(lane.prState)
        let state = switch mark { case .done: "finished"; case .working: "working"; case .waiting: "waiting"; case .failed: "failed" }
        return SliceCardRow(
            id: lane.id, number: lane.slice, title: lane.title, mark: mark, quiet: quiet, prNumber: lane.prNumber, prState: prState, lane: lane,
            openByDefault: index == 0 && mark == .working,
            spoken: ([lane.slice.map { "Slice \($0), \(lane.title)" } ?? lane.title, state] + quiet.map(\.text)
                + [lane.prNumber.map { "pull request \($0)" + (prState == .unknown ? "" : " \(prState)") }].compactMap { $0 }).joined(separator: ", ")
        )
    }
    rows += waiting.filter { $0.state != "skipped" }.sorted { $0.number < $1.number }.map { slice in
        let line = slice.blockedBy.isEmpty ? "Ready to start" : "Waits for " + slice.blockedBy.map { "#\($0)" }.joined(separator: ", ")
        return SliceCardRow(
            id: "slice-\(slice.number)", number: slice.number, title: slice.title, mark: .waiting, quiet: [SliceQuiet(text: line, kind: .plain)],
            prNumber: slice.prNumber, prState: SlicePRState(slice.prState), lane: nil, openByDefault: false,
            spoken: "Slice \(slice.number), \(slice.title), waiting, \(line)"
        )
    }

    let count = { (mark: SliceMark) in rows.filter { $0.mark == mark }.count }
    let merged = rows.filter { $0.prState == .merged }.count
    var summary = "\(merged) of \(rows.count) merged"
    if count(.working) > 0 { summary += " · \(count(.working)) working" }
    if count(.failed) > 0 { summary += " · \(count(.failed)) failed" }
    let lead: SliceLead = count(.failed) > 0 ? .failed : count(.working) > 0 ? .working : count(.waiting) > 0 || rows.isEmpty ? .waiting : .done

    var time: String?
    if let start = lanes.compactMap(\.startedAt).min() {
        if lead == .done, let end = lanes.compactMap(\.endedAt).max() {
            time = formatDuration(end - start)
        } else {
            time = "since " + clockTime(start, time: format)
        }
    }
    return SliceCard(rows: rows, summary: summary, lead: lead, segments: rows.map(\.mark), time: time)
}
