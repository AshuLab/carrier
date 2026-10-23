import Foundation

// The subagents of a session as sections of their own (docs/specs/macos-app-redesign.md, story 21). A lane is a Claude subagent
// inside the ship execution: it has no session, so the sections are read-only. The agent is exact (the `agentId` of its events);
// the lane number and the slice are hints read from the model's own wording (docs/research/claude-subagent-attribution.md).

public struct LaneSection: Equatable, Identifiable {
    /// The agent id: the key, never the lane or the slice (a lane is reused).
    public var id: String
    /// Where it sits in the session's list: the id of its first `task` start, or of its first event when it has none.
    public var startId: Int
    /// The slice's title in the epic's list; else the subagent's own description ("Subagent" before it arrives).
    public var title: String
    /// The epic's title for `slice`; nil with no slice or no match in the list.
    public var sliceTitle: String?
    public var state: SubagentState
    /// Ms from its first start to the end of its first run, or to `now` while it runs; nil with no start.
    public var duration: Int?
    /// The first start and the end of the first run, in ms (the engine's arrival time of those lines); nil until they arrive.
    public var startedAt: Int?
    public var endedAt: Int?
    /// How many times it started again after its first end (a follow-up message with the same agent id).
    public var resumes: Int
    /// When it ran, as the row's right side reads it: "14:02–14:09", "since 14:02" while it runs, nil otherwise.
    public var timeLabel: String?
    public var counts: SessionCounts
    public var items: [TranscriptItem]
    /// The slice the subagent builds, when its description says so (a hint, like the title).
    public var slice: Int?
    /// The lane it works in, when its worktree says so (a hint).
    public var laneNumber: Int?
    /// The slice's pull request as the row reads it: "PR #5 merged", "PR #5" (an older engine sends no state), or "no PR yet".
    public var pullRequest: String

    /// "resumed once", "resumed 2 times"; nil for one that never ran again.
    public var resumedLabel: String? { resumes > 0 ? "resumed " + (resumes == 1 ? "once" : "\(resumes) times") : nil }
}

/// A subagent's latest run: running (a start with no end), finished (the end event completed) or failed (it did not complete).
public enum SubagentState: Equatable { case running, finished, failed }

/// The digits right after `marker`, ignoring case: `number(after: "slice #", in: "Build slice #653")` is 653.
func number(after marker: String, in text: String) -> Int? {
    guard let range = text.range(of: marker, options: .caseInsensitive) else { return nil }
    return Int(text[range.upperBound...].prefix(while: { $0.isASCII && $0.isNumber }))
}

/// "14:02" in `timeZone`.
func clock(_ ms: Int, timeZone: TimeZone) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    formatter.timeZone = timeZone
    return formatter.string(from: Date(timeIntervalSince1970: Double(ms) / 1000))
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
    func section(slices: [EpicReply.Slice], running: Bool, now: Int, timeZone: TimeZone) -> LaneSection {
        let slice = description.flatMap { number(after: "slice #", in: $0) }
        let match = slice.flatMap { number in slices.first { $0.number == number } }
        let sliceTitle = match?.title
        let pullRequest = match?.prNumber.map { "PR #\($0)" + (match?.prState.map { " \($0)" } ?? "") } ?? "no PR yet"
        let tasks = events.filter { $0.kind == "task" }
        let start = tasks.first { $0.status == nil }
        let end = tasks.first { $0.status != nil }
        // The latest run decides: a last start is running while the session is, else it did not complete.
        let state: SubagentState = switch tasks.last?.status {
        case nil: running ? .running : .failed
        case "ok": .finished
        default: .failed
        }
        let timeLabel = start.flatMap { start in
            end.map { "\(clock(start.at, timeZone: timeZone))–\(clock($0.at, timeZone: timeZone))" }
                ?? (state == .running ? "since \(clock(start.at, timeZone: timeZone))" : nil)
        }
        return LaneSection(
            id: agentId, startId: (start ?? events[0]).id, title: sliceTitle ?? description ?? "Subagent", sliceTitle: sliceTitle,
            state: state,
            duration: start.flatMap { start in (end?.at ?? (state == .running ? now : nil)).map { $0 - start.at } },
            startedAt: start?.at, endedAt: end?.at,
            resumes: tasks.drop { $0.status == nil }.dropFirst().filter { $0.status == nil }.count, timeLabel: timeLabel,
            counts: sessionCounts(events), items: builder.items, slice: slice, laneNumber: lane, pullRequest: pullRequest
        )
    }
}

extension Transcript {
    /// The session's list in event order: the main rows with the subagents at the place they were taken (`flowItems`). The main
    /// thread's call that launched a subagent shares its `callId` with the subagent's `task` start and is left out: the slice stands for it.
    public func flow(
        slices: [EpicReply.Slice] = [], running: Bool = false, now: Int = Int(Date().timeIntervalSince1970 * 1000), timeZone: TimeZone = .current
    ) -> [FlowItem] {
        let launches = Set(lanes.flatMap { $0.events.filter { $0.kind == "task" && $0.status == nil }.compactMap(\.callId) })
        let launched = Set(events.filter { $0.agentId == nil && $0.callId.map(launches.contains) == true }.map(\.id))
        return flowItems(items.filter { launched.contains($0.id) == false }, slices: laneSections(slices: slices, running: running, now: now, timeZone: timeZone))
    }

    /// The subagents with events, in order of appearance. Events with no agent id are in `items`.
    public func laneSections(
        slices: [EpicReply.Slice] = [], running: Bool = false, now: Int = Int(Date().timeIntervalSince1970 * 1000), timeZone: TimeZone = .current
    ) -> [LaneSection] {
        lanes.map { $0.section(slices: slices, running: running, now: now, timeZone: timeZone) }
    }
}
