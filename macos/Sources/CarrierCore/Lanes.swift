import Foundation

// The subagents of a session as sections of their own (docs/specs/macos-app-redesign.md, story 21). A lane is a Claude subagent
// inside the ship execution: it has no session, so the sections are read-only. The agent is exact (the `agentId` of its events);
// the lane number and the slice are hints read from the model's own wording (docs/research/claude-subagent-attribution.md).

public struct LaneSection: Equatable, Identifiable {
    /// The agent id: the key, never the lane or the slice (a lane is reused).
    public var id: String
    /// The slice's title in the epic's list; else the subagent's own description ("Subagent" before it arrives).
    public var title: String
    /// The epic's title for `slice`; nil with no slice or no match in the list.
    public var sliceTitle: String?
    public var state: SubagentState
    /// Ms from its first start to the end of its first run; nil while it runs.
    public var duration: Int?
    public var counts: SessionCounts
    public var items: [TranscriptItem]
    /// The slice the subagent builds, when its description says so (a hint, like the title).
    public var slice: Int?
    /// The lane it works in, when its worktree says so (a hint).
    public var laneNumber: Int?
}

/// A subagent's first run: running (a start with no end), finished (the end event completed) or failed (it did not complete).
public enum SubagentState: Equatable { case running, finished, failed }

/// The digits right after `marker`, ignoring case: `number(after: "slice #", in: "Build slice #653")` is 653.
func number(after marker: String, in text: String) -> Int? {
    guard let range = text.range(of: marker, options: .caseInsensitive) else { return nil }
    return Int(text[range.upperBound...].prefix(while: { $0.isASCII && $0.isNumber }))
}

/// What the events of one subagent say so far.
struct LaneState: Equatable {
    var agentId: String
    /// The text of its first `task` event ("Build slice #653").
    var description: String?
    /// `--lane-N` in the first argument that has one (a worktree path of Solve's naming).
    var lane: Int?
    var events: [ExecEvent] = []
    var builder = TranscriptBuilder()

    mutating func add(_ event: ExecEvent) {
        events.append(event)
        if event.kind == "task", description == nil { description = event.text }
        if lane == nil, let arg = event.arg { lane = number(after: "--lane-", in: arg) }
        builder.add(event)
    }

    mutating func reset() {
        events = []
        description = nil
        lane = nil
        builder.reset()
    }

    /// `running` is whether the session is: a start with no end in one that is not did not complete.
    func section(slices: [EpicReply.Slice], running: Bool) -> LaneSection {
        let slice = description.flatMap { number(after: "slice #", in: $0) }
        let sliceTitle = slice.flatMap { number in slices.first { $0.number == number }?.title }
        let tasks = events.filter { $0.kind == "task" }
        let start = tasks.first { $0.status == nil }
        let end = tasks.first { $0.status != nil }
        return LaneSection(
            id: agentId, title: sliceTitle ?? description ?? "Subagent", sliceTitle: sliceTitle,
            state: end.map { $0.status == "ok" ? .finished : .failed } ?? (running ? .running : .failed),
            duration: start.flatMap { start in end.map { $0.at - start.at } },
            counts: sessionCounts(events), items: builder.items, slice: slice, laneNumber: lane
        )
    }
}

extension Transcript {
    /// The subagents with events, in order of appearance. Events with no agent id are in `items`.
    public func laneSections(slices: [EpicReply.Slice] = [], running: Bool = false) -> [LaneSection] {
        lanes.map { $0.section(slices: slices, running: running) }
    }
}
