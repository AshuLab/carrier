import Foundation

// The subagent view (docs/glossary.md): what replaces the conversation when a subagent's row is opened. The view takes `SubagentWork`: the
// header's description, the brief and the flow items the epic's Agent output tab draws too. The chat's events become them in `subagentWork`.

/// What the window's header says of a subagent: its title, its type, how it stands and for how long.
public struct SubagentHeader: Equatable {
    public let title: String
    public let type: String
    public let state: SubagentStatus
    /// Milliseconds since the epoch.
    public let startedAt: Int
    /// How long it ran; nil while it runs.
    public let durationMs: Int?
    /// The epic's title when the subagent is a slice card's (its subtitle names the epic, and Stop is not offered); nil in a conversation.
    public let epic: String?
    /// What stopping it takes, from its `task` events; nil until one names it.
    public let taskId: String?
    /// Whether the host lists `stopTask`: set by the model, which knows the hello; an older host cannot stop a subagent.
    public var hostStops: Bool

    public init(title: String, type: String, state: SubagentStatus, startedAt: Int, durationMs: Int?, epic: String? = nil, taskId: String? = nil, hostStops: Bool = false) {
        (self.title, self.type, self.state, self.startedAt, self.durationMs, self.epic, self.taskId, self.hostStops) = (title, type, state, startedAt, durationMs, epic, taskId, hostStops)
    }

    /// A slice card's subagent: the slice's title, the role of the session it ran in (Builder, Reviewer) and the lane's own state.
    init(lane: LaneSection, role: String, epic: String) {
        let state: SubagentStatus = switch lane.state { case .running: .running; case .finished: .completed; case .failed: .failed }
        self.init(title: lane.title, type: role, state: state, startedAt: lane.startedAt ?? 0, durationMs: state == .running ? nil : lane.duration, epic: epic)
    }

    init(_ subagent: Subagent) {
        self.init(
            title: subagent.name, type: subagent.type, state: subagent.status, startedAt: subagent.startedAt,
            durationMs: subagent.status == .running ? nil : subagent.elapsedMs(now: 0), taskId: subagent.taskId
        )
    }

    /// Whether the header offers Stop: only while it runs, only to a host that can, only when its task is known, and never for a slice card's.
    public var canStop: Bool { state == .running && hostStops && taskId != nil && epic == nil }

    /// The line under the title: "Explore · Subagent of Fix the login", or "Builder · <the epic's title>" for a slice card's.
    public func subtitle(of session: String) -> String { "\(type) · \(epic ?? "Subagent of \(session)")" }

    /// The state pill: "Running 1m 11s" with the timer at `now`, "Finished · 42 s" with how long it took, "Failed" and "Stopped".
    public func stateWords(now: Int) -> String {
        switch state {
        case .running: "Running \(formatCallDuration(max(0, now - startedAt)))"
        case .completed: "Finished · \(formatCallDuration(durationMs ?? 0))"
        case .failed: "Failed"
        case .stopped: "Stopped"
        }
    }
}

/// A subagent as its view draws it: the header's description, the brief it was given (nil when the events do not carry it) and its own work.
public struct SubagentWork: Equatable {
    public internal(set) var header: SubagentHeader
    public let brief: String?
    public let items: [FlowItem]
}

/// The subagent launched by `call`, from the events of the session: its own calls, thoughts and messages as flow items (the rows of any
/// subagent it launched in turn are in its groups), drawn as the main agent's are. A run still going while the subagent runs is live; once
/// it ended, a call that never ended was stopped. Nil when no `task` event names the call.
public func subagentWork(in events: [ChatEvent], call: String) -> SubagentWork? {
    var subagent: Subagent?
    for event in events where event.kind == "task" && event.callId == call {
        if subagent == nil { subagent = Subagent(task: event) } else { subagent?.apply(task: event) }
    }
    guard var subagent else { return nil }
    // the subagent's own events and those of the subagents it launched, which `chatFeed` joins to their rows as it does for the main agent's
    var calls: Set<String> = [call]
    var grew = true
    while grew {
        grew = false
        for event in events where event.kind == "task" {
            if let parent = event.parentCallId, calls.contains(parent), let launched = event.callId, calls.insert(launched).inserted { grew = true }
        }
    }
    let own = events.compactMap { event -> ChatEvent? in
        guard let parent = event.parentCallId, calls.contains(parent) else { return nil }
        var event = event
        if parent == call { event.parentCallId = nil }
        return event
    }
    for event in own where event.kind != "task" && event.parentCallId == nil { subagent.apply(inside: event) }
    let running = subagent.status == .running
    let rows = chatFeed(own)
    let working = running ? workInProgress(in: rows) : nil
    let items = rows.compactMap { row -> FlowItem? in
        switch row {
        case .agent(let id, let text, _): return FlowItem.message(id: number(id), text: text)
        case .error(let id, let text): return FlowItem.error(id: number(id), text: text)
        case .tools(let id, var group):
            if running == false { group.calls = group.calls.map { var call = $0; if call.status == .running { call.stop() }; return call } }
            return FlowItem.tools(id: number(id), group, live: id == working || group.runningSubagents > 0)
        default: return nil
        }
    }
    let launch = events.first { $0.kind == "tool_start" && $0.callId == call }
    return SubagentWork(header: SubagentHeader(subagent), brief: launch?.arg.flatMap(brief(of:)), items: items)
}

/// The subagent of the slice card `id` in the epic's sessions, as its view draws it: the lane's own flow items, all its runs in one view (a
/// resumed subagent is still one lane). The role is that of the session the card sits in. Nil when no card has that id.
public func subagentWork(lane id: String, in sessions: SessionList, epic: String) -> SubagentWork? {
    for section in sessions.sections {
        guard case .items(let items) = section.body else { continue }
        for case .slice(let lane) in items where lane.id == id {
            return SubagentWork(header: SubagentHeader(lane: lane, role: section.role, epic: epic), brief: nil, items: flowItems(lane.items, running: lane.state == .running))
        }
    }
    return nil
}

/// A row's id is `e` and its event's id.
private func number(_ id: String) -> Int { Int(id.dropFirst()) ?? 0 }

/// The `prompt` of an `Agent` call's input, as the host stored it: its JSON, cut at 1,024 characters, so a long brief arrives with no closing
/// quote. What is there is the brief, with the escapes of JSON read; nil when the input has no prompt.
func brief(of arg: String) -> String? {
    guard let key = arg.range(of: #""prompt"\s*:\s*""#, options: .regularExpression) else { return nil }
    var raw = ""
    var escaped = false
    for character in arg[key.upperBound...] {
        if escaped {
            raw += "\\\(character)"
            escaped = false
        } else if character == "\\" {
            escaped = true
        } else if character == "\"" {
            break
        } else {
            raw.append(character)
        }
    }
    let decoded = (try? JSONDecoder().decode(String.self, from: Data("\"\(raw)\"".utf8))) ?? raw
    let text = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? nil : text
}
