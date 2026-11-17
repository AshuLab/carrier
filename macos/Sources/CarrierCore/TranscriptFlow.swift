import Foundation

// The rows of the Agent output tab as the view draws them: the transcript's items with each run of calls and thoughts as one `ToolGroup`,
// the chat's own (`chatFeed` builds the same from a session's events), so a run reads and looks the same in an epic and in a session.
// A pure step over `Transcript.items`, so an append never rebuilds the transcript.

public enum FlowItem: Equatable, Identifiable {
    /// What the agent said, as markdown.
    case message(id: Int, text: String)
    case note(id: Int, text: String)
    case error(id: Int, text: String)
    /// A call to the `Skill` tool: a milestone of its own, which ends a run.
    case skill(id: Int, ToolCall)
    /// A run of the agent's calls and thoughts, at the id of the first. `live` is whether the agent is working in it now.
    case tools(id: Int, ToolGroup, live: Bool)
    /// A subagent, at the id of its first `task` start.
    case slice(LaneSection)

    public var id: Int {
        switch self {
        case .message(let id, _), .note(let id, _), .error(let id, _), .skill(let id, _), .tools(let id, _, _): id
        case .slice(let lane): lane.startId
        }
    }
}

/// Runs of calls and thoughts become one group each, like the chat's: a thought is placed among the calls of the run it comes in, and a run
/// ends at anything else: a message, a note, an error, a skill or a slice (a slice sits before the first item with a higher id). `running`
/// is whether the agent is working: the last run is then live when nothing comes after it, and a call that never ended in a run that is
/// over was stopped, not going on: over is the agent having spoken or failed after it, or the session having ended.
public func flowItems(_ items: [TranscriptItem], slices: [LaneSection] = [], running: Bool = false) -> [FlowItem] {
    var later = slices.sorted { $0.startId < $1.startId }[...]
    var flow: [FlowItem] = []
    var first: Int?
    var calls: [ToolCall] = []
    var thoughts: [Thought] = []
    func close(agentMovedOn: Bool = false) {
        guard let id = first else { return }
        if agentMovedOn { calls = calls.map { var call = $0; if call.status == .running { call.stop() }; return call } }
        flow.append(.tools(id: id, ToolGroup(calls: calls, thoughts: thoughts), live: false))
        (first, calls, thoughts) = (nil, [], [])
    }
    func settled(_ call: ToolCall) -> ToolCall {
        var call = call
        if running == false, call.status == .running { call.stop() }
        return call
    }
    for item in items {
        while let slice = later.first, slice.startId < item.id {
            close()
            flow.append(.slice(slice))
            later = later.dropFirst()
        }
        switch item {
        case .tool(let id, let call) where call.tool == "Skill":
            close()
            flow.append(.skill(id: id, settled(call)))
        case .tool(let id, let call):
            first = first ?? id
            calls.append(settled(call))
        case .thought(let id, let text, let at):
            first = first ?? id
            thoughts.append(Thought(id: "e\(id)", text: text, at: at, before: calls.count))
        case .message(let id, let text):
            close(agentMovedOn: true)
            flow.append(.message(id: id, text: text))
        case .note(let id, let text):
            close()
            flow.append(.note(id: id, text: text))
        case .error(let id, let text):
            close(agentMovedOn: true)
            flow.append(.error(id: id, text: text))
        }
    }
    close()
    flow += later.map(FlowItem.slice)
    if running, case .tools(let id, let group, _)? = flow.last { flow[flow.count - 1] = .tools(id: id, group, live: true) }
    return flow
}

/// The flow without its calls when the tools are hidden, and without their thoughts when the person does not want the reasoning; a run left
/// with nothing goes (the same as `visibleFeed` does for a session).
public func visibleFlow(_ flow: [FlowItem], mode: ToolOutputMode, showsReasoning: Bool = true) -> [FlowItem] {
    flow.compactMap { item in
        switch item {
        case .skill: return mode == .hidden ? nil : item
        case .tools(let id, var group, let live):
            if mode == .hidden { group.calls = [] }
            if showsReasoning == false { group.thoughts = [] }
            return group.calls.isEmpty && group.thoughts.isEmpty && group.subagents.isEmpty ? nil : .tools(id: id, group, live: live)
        default: return item
        }
    }
}

/// Which slice rows the user opened, by the subagent's id; a row nobody touched is closed, whatever its state.
public struct SliceFolds: Equatable {
    private var open: Set<String> = []

    public init() {}

    public func isOpen(_ id: String) -> Bool { open.contains(id) }

    public mutating func toggle(_ id: String) {
        if open.insert(id).inserted == false { open.remove(id) }
    }
}
