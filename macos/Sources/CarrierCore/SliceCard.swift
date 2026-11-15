import Foundation

// A slice of the epic as a card in the builder's session, where it was taken (docs/macos-ui.md, "The slice card"): its mark, `#730` and the
// title, a quiet line of what it cost and its pull request. A pure function of what a session already has, its subagent (`LaneSection`); a
// number that is missing is left out of the line, never made up.

public enum SliceMark: Equatable {
    /// The subagent finished.
    case done
    case working
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
    /// The subagent's id.
    public var id: String
    /// nil for a subagent whose description names no slice.
    public var number: Int?
    public var title: String
    public var mark: SliceMark
    /// Calls, edits, test runs, errors, the lane when slices run in parallel and the time range, in this order, those that are known.
    public var quiet: [SliceQuiet]
    public var prNumber: Int?
    public var prState: SlicePRState
    /// What opens under the row: the slice's own steps.
    public var lane: LaneSection
    /// Open while the slice works.
    public var openByDefault: Bool
    /// What VoiceOver reads, without open or closed.
    public var spoken: String

}

private func plural(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }

private func mark(_ state: SubagentState) -> SliceMark {
    switch state {
    case .running: .working
    case .finished: .done
    case .failed: .failed
    }
}

public func sliceCard(lane: LaneSection) -> SliceCardRow {
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
        if let number = lane.laneNumber { quiet.append(SliceQuiet(text: "Lane \(number)", kind: .lane)) }
        if mark != .working, let range = lane.timeLabel { quiet.append(SliceQuiet(text: range, kind: .plain)) }
    }
    let prState = SlicePRState(lane.prState)
    let state = switch mark { case .done: "finished"; case .working: "working"; case .failed: "failed" }
    return SliceCardRow(
        id: lane.id, number: lane.slice, title: lane.title, mark: mark, quiet: quiet, prNumber: lane.prNumber, prState: prState, lane: lane,
        openByDefault: mark == .working,
        spoken: ([lane.slice.map { "Slice \($0), \(lane.title)" } ?? lane.title, state] + quiet.map(\.text)
            + [lane.prNumber.map { "pull request \($0)" + (prState == .unknown ? "" : " \(prState)") }].compactMap { $0 }).joined(separator: ", ")
    )
}
