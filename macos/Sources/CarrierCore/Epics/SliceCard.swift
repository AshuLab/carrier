import Foundation

// A slice of the epic as a card in the builder's session, where it was taken (docs/ui.md, "The slice card"): its mark, `#730` and the
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

    /// The kind of the spoken sentence of a pull request, which names its state when it has one.
    var spoken: Copy.EpicsSlicePrSpoken {
        switch self {
        case .merged: .merged
        case .open: .open
        case .draft: .draft
        case .closed: .closed
        case .unknown: .unknown
        }
    }

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
    public enum Kind: Equatable { case plain, error, lane, step }

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
    /// The step it is on while working, then calls, edits, test runs, errors, the lane when slices run in parallel and the time range, those that are known.
    public var quiet: [SliceQuiet]
    public var prNumber: Int?
    public var prState: SlicePRState
    /// What the card opens: the subagent's view of the slice's own steps.
    public var lane: LaneSection
    /// What VoiceOver reads, without open or closed.
    public var spoken: String

}

private func mark(_ state: SubagentState) -> SliceMark {
    switch state {
    case .running: .working
    case .finished: .done
    case .failed: .failed
    }
}

public func sliceCard(lane: LaneSection, bundle: Bundle? = nil, locale: Locale = .current) -> SliceCardRow {
    let mark = mark(lane.state)
    var quiet: [SliceQuiet] = []
    if lane.isStarting, lane.lastStep == nil {
        quiet.append(SliceQuiet(text: Copy.epicsSliceStarting(bundle: bundle, locale: locale), kind: .plain))
    } else {
        if mark == .working, let step = lane.lastStep { quiet.append(SliceQuiet(text: step, kind: .step)) }
        if lane.counts.calls > 0 {
            let calls = mark == .working
                ? Copy.epicsSliceCallsSoFar(count: lane.counts.calls, bundle: bundle, locale: locale)
                : Copy.epicsSliceCalls(count: lane.counts.calls, bundle: bundle, locale: locale)
            quiet.append(SliceQuiet(text: calls, kind: .plain))
        }
        if lane.counts.edits > 0 { quiet.append(SliceQuiet(text: Copy.epicsSliceEdits(count: lane.counts.edits, bundle: bundle, locale: locale), kind: .plain)) }
        if lane.counts.tests > 0 { quiet.append(SliceQuiet(text: Copy.epicsSliceTests(count: lane.counts.tests, bundle: bundle, locale: locale), kind: .plain)) }
        if lane.counts.errors > 0 { quiet.append(SliceQuiet(text: Copy.epicsSliceErrors(count: lane.counts.errors, bundle: bundle, locale: locale), kind: .error)) }
        if mark == .failed { quiet.append(SliceQuiet(text: Copy.epicsSliceIncomplete(bundle: bundle, locale: locale), kind: .error)) }
        if let number = lane.laneNumber { quiet.append(SliceQuiet(text: Copy.epicsSliceLane(number: number, bundle: bundle, locale: locale), kind: .lane)) }
        if mark != .working, let range = lane.timeLabel { quiet.append(SliceQuiet(text: range, kind: .plain)) }
    }
    let prState = SlicePRState(lane.prState)
    let state = switch mark {
    case .done: Copy.epicsSliceStateDone(bundle: bundle, locale: locale)
    case .working: Copy.epicsWorking(bundle: bundle, locale: locale)
    case .failed: Copy.epicsSliceStateFailed(bundle: bundle, locale: locale)
    }
    let pullRequest = lane.prNumber.map { Copy.epicsSlicePrSpoken(state: prState.spoken, number: String($0), bundle: bundle, locale: locale) }
    let slice = lane.slice.map { Copy.epicsSliceSpoken(number: String($0), title: lane.title, bundle: bundle, locale: locale) } ?? lane.title
    return SliceCardRow(
        id: lane.id, number: lane.slice, title: lane.title, mark: mark, quiet: quiet, prNumber: lane.prNumber, prState: prState, lane: lane,
        spoken: ([slice, state] + quiet.map(\.text) + [pullRequest].compactMap { $0 }).joined(separator: ", ")
    )
}
