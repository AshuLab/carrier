import Foundation

// The subagents of a session as sections of their own (docs/specs/macos-app-redesign.md, story 21). A lane is a Claude subagent
// inside the ship execution: it has no session, so the sections are read-only. The agent is exact (the `agentId` of its events);
// the lane number and the slice are hints read from the model's own wording (docs/research/claude-subagent-attribution.md).

public struct LaneSection: Equatable, Identifiable {
    /// The agent id: the key, never the lane or the slice (a lane is reused).
    public var id: String
    /// "Lane 1 · #653", "#653", "Lane 3"; the subagent's own description when neither was found.
    public var title: String
    /// The lane number or the slice was inferred, so the section says so.
    public var hint: Bool
    public var counts: String
    public var items: [TranscriptItem]
}

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

    var section: LaneSection {
        let slice = description.flatMap { number(after: "slice #", in: $0) }
        let parts = [lane.map { "Lane \($0)" }, slice.map { "#\($0)" }].compactMap { $0 }
        return LaneSection(
            id: agentId, title: parts.isEmpty ? description ?? "Subagent" : parts.joined(separator: " · "), hint: parts.isEmpty == false,
            counts: countsLine(sessionCounts(events)), items: builder.items
        )
    }
}

extension Transcript {
    /// The subagents with events, in order of appearance. Events with no agent id are in `items`.
    public var laneSections: [LaneSection] { lanes.map(\.section) }
}
