import Foundation

/// How a subagent stands: it runs from its start until an end arrives, and a start with no end keeps running.
public enum SubagentStatus: Equatable { case running, completed, failed, stopped }

/// One subagent the main agent launched, built from the `task` events that share its launching call's id and the events made inside it
/// (`parentCallId` is that call). It is a row under the run that launched it; the launching `Agent` call is not a call of the run.
public struct Subagent: Equatable, Identifiable {
    /// The launching call's id.
    public let id: String
    /// What stopping it takes; nil until a `task` event says it.
    public internal(set) var taskId: String?
    /// `Explore`, `general-purpose`: the type it was launched with, `Agent` when the events do not say.
    public internal(set) var type: String
    /// The description it was launched with.
    public internal(set) var title: String
    public internal(set) var status = SubagentStatus.running
    /// What it is doing now, nil until it does anything: its last event, or the last tool of its latest `progress` while it has no event of its own.
    public internal(set) var step: String?
    /// How many calls it made: the larger of what its own events show and what the provider reported.
    public var steps: Int { max(ownCalls, reported) }
    /// Milliseconds since the epoch.
    public let startedAt: Int
    public internal(set) var endedAt: Int?
    /// The time the provider reported for its whole life, once it ended.
    private var reportedMs: Int?
    private var ownCalls = 0
    private var reported = 0

    init(task event: ChatEvent) {
        id = event.callId ?? "e\(event.id)"
        taskId = event.taskId
        type = event.agentType ?? "Agent"
        title = event.state == "started" ? (event.text ?? "") : ""
        startedAt = event.at
        apply(task: event)
    }

    /// A `task` event of this subagent: its start gives the title and type, a progress its last tool and counts, an end its state.
    mutating func apply(task event: ChatEvent) {
        taskId = taskId ?? event.taskId
        if let type = event.agentType { self.type = type }
        if event.state == "started", let text = event.text, text.isEmpty == false { title = text }
        if let tools = event.tools { reported = max(reported, tools) }
        switch event.state {
        case "progress":
            if ownCalls == 0, let tool = event.lastTool { step = "Using \(tool)" }
        case "completed", "failed", "stopped":
            status = event.state == "completed" ? .completed : event.state == "failed" ? .failed : .stopped
            endedAt = event.at
            reportedMs = event.ms
        default: break
        }
    }

    /// It started and never ended while its session is not working: the host restarted or lost it, so it is shown stopped, at the time of the last event.
    mutating func stop(at time: Int) {
        status = .stopped
        endedAt = max(startedAt, time)
    }

    /// An event made inside the subagent: a call it starts, a thought or its text is what it is doing now.
    mutating func apply(inside event: ChatEvent) {
        switch event.kind {
        case "tool_start":
            ownCalls += 1
            step = ToolCall(start: event).doing
        case "reasoning": step = "Thinking"
        case "assistant": step = "Answering"
        default: break
        }
    }

    /// The row's name for it: the title, or the type while the events give none.
    public var name: String { title.isEmpty ? type : title }

    /// What the row says after the title: the step while it runs ("Starting" before the first), the way it ended otherwise.
    public var words: String {
        switch status {
        case .running: step ?? "Starting"
        case .completed: "Finished"
        case .failed: "Failed"
        case .stopped: "Stopped"
        }
    }

    /// How long it has run at `now`, or how long it ran: the provider's own count when it gave one.
    public func elapsedMs(now: Int) -> Int {
        if let endedAt { return max(0, reportedMs ?? endedAt - startedAt) }
        return max(0, now - startedAt)
    }
}
