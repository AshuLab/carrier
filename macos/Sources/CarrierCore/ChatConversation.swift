import Foundation
import Observation

// An open session's conversation (docs/specs/sessions-in-the-app.md, "The conversation"): the events of the host's `events` reply,
// the feed of rows they make (a pure function) and the model that polls by cursor and keeps the feed current.

/// One of the provider's choices on an approval.
public struct ChatChoice: Codable, Equatable {
    public let id: String
    public let label: String
    public let allow: Bool

    public init(id: String, label: String, allow: Bool) {
        self.id = id
        self.label = label
        self.allow = allow
    }
}

/// One question of an `AskUserQuestion` approval: a short header, the question, the options the provider lists (the person may also
/// write their own) and whether more than one can be picked.
public struct ChatQuestion: Codable, Equatable {
    public struct Option: Codable, Equatable {
        public let label: String
        public let description: String
        /// Optional text (a mockup, a snippet) to show while the option is focused.
        public let preview: String?

        public init(label: String, description: String, preview: String? = nil) {
            self.label = label
            self.description = description
            self.preview = preview
        }
    }

    public let question: String
    public let header: String
    public let options: [Option]
    public let multiSelect: Bool

    public init(question: String, header: String, options: [Option], multiSelect: Bool = false) {
        self.question = question
        self.header = header
        self.options = options
        self.multiSelect = multiSelect
    }
}

/// An event of the conversation as the host stores it (docs/specs/chat-host.md, Decisions): `kind` says which of the fields are there.
public struct ChatEvent: Codable, Equatable {
    public let id: Int
    /// Milliseconds since the epoch.
    public let at: Int
    public let kind: String
    public var text: String?
    public var callId: String?
    public var tool: String?
    public var arg: String?
    public var output: [String]?
    public var status: String?
    public var approvalId: String?
    public var choices: [ChatChoice]?
    public var choiceId: String?
    /// An approval that asks questions (`AskUserQuestion`) lists them here; `arg` is absent then.
    public var questions: [ChatQuestion]?
    /// What the person answered to those, by question text (more than one pick comma-separated); on an `approval_answered`.
    public var answers: [String: String]?
    public var outcome: String?
    public var model: String?
    /// As the provider reported it: its keys differ (`input_tokens` or `inputTokens`), and any of them can be missing.
    public var usage: [String: Double]?
    /// A `step` event of a session's preparation: which step, and (in `status`, `running`, `done` or `failed`) how it stands; `detail` is the reason a step failed.
    public var step: String?
    public var detail: String?
    /// The call that launched the subagent this event was made in; nil for the main agent's own. The main conversation does not draw an event that has one.
    public var parentCallId: String?
    /// A `task` event, the life of a subagent joined to its launching call by `callId`: `taskId` is what stopping it takes, `state` is
    /// `started`, `progress`, `completed`, `failed` or `stopped`. Its title and step are in `text` and `lastTool`; `parentCallId` is the
    /// call of the subagent that launched this one.
    public var taskId: String?
    public var state: String?
    public var agentType: String?
    public var lastTool: String?
    public var tools: Int?
    public var tokens: Int?
    public var ms: Int?
    public var background: Bool?
    /// A `notice` that says the session changed agent: the agents as the host's config names them. Nil for any other event, and from a host that does not switch.
    public var switched: Switched?
    /// An `error` the provider says is an account out of usage: `usage_limit`. Nil for any other error, and from a host that does not say.
    public var reason: String?
    /// When that limit resets, in milliseconds since the epoch, when the provider gives a timestamp; never set with `resetText`.
    public var resetsAt: Int?
    /// When that limit resets, in the provider's own words, when it gives only those.
    public var resetText: String?

    /// The agents of a switch, as `chat.json` names them.
    public struct Switched: Codable, Equatable {
        public let from: String
        public let to: String

        public init(from: String, to: String) {
            self.from = from
            self.to = to
        }
    }

    public init(
        id: Int, at: Int, kind: String, text: String? = nil, callId: String? = nil, tool: String? = nil, arg: String? = nil, output: [String]? = nil,
        status: String? = nil, approvalId: String? = nil, choices: [ChatChoice]? = nil, choiceId: String? = nil, outcome: String? = nil,
        model: String? = nil, usage: [String: Double]? = nil, step: String? = nil, detail: String? = nil, questions: [ChatQuestion]? = nil,
        answers: [String: String]? = nil, parentCallId: String? = nil, taskId: String? = nil, state: String? = nil, agentType: String? = nil,
        lastTool: String? = nil, tools: Int? = nil, tokens: Int? = nil, ms: Int? = nil, background: Bool? = nil, switched: Switched? = nil, reason: String? = nil, resetsAt: Int? = nil, resetText: String? = nil
    ) {
        self.id = id
        self.at = at
        self.kind = kind
        self.text = text
        self.callId = callId
        self.tool = tool
        self.arg = arg
        self.output = output
        self.status = status
        self.approvalId = approvalId
        self.choices = choices
        self.choiceId = choiceId
        self.questions = questions
        self.answers = answers
        self.outcome = outcome
        self.model = model
        self.usage = usage
        self.step = step
        self.detail = detail
        self.parentCallId = parentCallId
        self.taskId = taskId
        self.state = state
        self.agentType = agentType
        self.lastTool = lastTool
        self.tools = tools
        self.tokens = tokens
        self.ms = ms
        self.background = background
        self.switched = switched
        self.reason = reason
        self.resetsAt = resetsAt
        self.resetText = resetText
    }
}

/// The reply of `events`: the page after the cursor, the cursor to ask from next and the text of the message being written.
/// The session's state (from its summary) comes with it, as the model needs to know whether the agent is answering; so do the ids
/// of the approvals still pending (the ones the person can answer) and the options, which the slice that draws them reads.
public struct ChatEvents: Decodable, Equatable {
    public let events: [ChatEvent]
    public let cursor: Int
    public let streaming: String
    public let state: ChatSession.State?
    public let pending: Set<String>
    /// What the provider offers for this session, with the current values; empty for a closed session.
    public let options: [ChatOption]
    /// What the provider lets the person invoke; empty for a closed session.
    public let commands: [ChatCommand]
    /// How the session's preparation stands (from its summary), nil when it is not being prepared or the host does not say.
    public let preparation: ChatSession.Preparation?
    /// The latest line of git's own progress while a clone runs; nil when there is none or the host leaves it out.
    public let progress: String?
    /// The host's name for this version of `options` and `commands`; nil from a host that does not say. Sent back in the next request, it makes
    /// the host leave both out while they stay as they are.
    public let listsRev: String?
    /// The host left `options` and `commands` out because they are the ones of `listsRev`, which the caller sent: they are empty here, not gone.
    public let listsUnchanged: Bool

    public init(
        events: [ChatEvent], cursor: Int, streaming: String = "", state: ChatSession.State? = nil, pending: Set<String> = [], options: [ChatOption] = [],
        commands: [ChatCommand] = [], preparation: ChatSession.Preparation? = nil, progress: String? = nil, listsRev: String? = nil, listsUnchanged: Bool = false
    ) {
        self.events = events
        self.cursor = cursor
        self.streaming = streaming
        self.state = state
        self.pending = pending
        self.options = options
        self.commands = commands
        self.preparation = preparation
        self.progress = progress
        self.listsRev = listsRev
        self.listsUnchanged = listsUnchanged
    }

    /// The same reply with the lists the caller kept for `listsRev`, when the host left them out.
    func with(options: [ChatOption], commands: [ChatCommand]) -> ChatEvents {
        ChatEvents(
            events: events, cursor: cursor, streaming: streaming, state: state, pending: pending, options: options, commands: commands,
            preparation: preparation, progress: progress, listsRev: listsRev, listsUnchanged: false
        )
    }

    private enum CodingKeys: String, CodingKey { case events, cursor, streaming, session, approvals, options, commands, progress, listsRev, listsUnchanged }
    private struct Summary: Decodable {
        let state: ChatSession.State
        let preparation: ChatSession.Preparation?

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            state = try values.decode(ChatSession.State.self, forKey: .state)
            preparation = (try? values.decodeIfPresent(ChatSession.Preparation.self, forKey: .preparation)) ?? nil
        }

        private enum CodingKeys: String, CodingKey { case state, preparation }
    }
    private struct Approval: Decodable { let approvalId: String }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        events = try values.decode([ChatEvent].self, forKey: .events)
        cursor = try values.decode(Int.self, forKey: .cursor)
        streaming = try values.decode(String.self, forKey: .streaming)
        let summary = try values.decodeIfPresent(Summary.self, forKey: .session)
        state = summary?.state
        preparation = summary?.preparation
        progress = try values.decodeIfPresent(String.self, forKey: .progress)
        pending = Set(try values.decodeIfPresent([Approval].self, forKey: .approvals)?.map(\.approvalId) ?? [])
        options = try values.decodeIfPresent([ChatOption].self, forKey: .options) ?? []
        commands = try values.decodeIfPresent([ChatCommand].self, forKey: .commands) ?? []
        listsRev = try values.decodeIfPresent(String.self, forKey: .listsRev)
        listsUnchanged = try values.decodeIfPresent(Bool.self, forKey: .listsUnchanged) ?? false
    }
}

/// A row of the feed.
public enum FeedRow: Equatable, Identifiable {
    /// What the person wrote: a bubble on the right.
    case user(id: String, text: String)
    /// What the agent wrote, as markdown; `inProgress` is the text still being written, which is not stored yet.
    case agent(id: String, text: String, inProgress: Bool)
    /// The line that closes a turn: the model, how long it took and the usage the provider reported.
    case turnEnd(id: String, TurnSummary)
    /// A run of the agent's work, its reasoning and its calls: one row that opens to its steps.
    case tools(id: String, ToolGroup)
    /// An approval waiting for the person: a card with the provider's choices.
    case approval(id: String, ApprovalCard)
    /// An approval that was answered: one line, green when the choice allowed and red when it did not.
    case decided(id: String, text: String, allow: Bool)
    /// An approval that is not waiting any more and was not answered (its turn ended): one plain line.
    case line(id: String, text: String)
    /// An error event: the provider's text, in the banner of a failed turn.
    case error(id: String, text: String)
    /// A turn the person stopped: the mark with Continue.
    case stopped(id: String)

    public var id: String {
        switch self {
        case .user(let id, _), .agent(let id, _, _), .turnEnd(let id, _), .tools(let id, _), .approval(let id, _), .decided(let id, _, _),
            .line(let id, _), .error(let id, _), .stopped(let id): id
        }
    }
}

/// The row of the mark or banner that offers a way out (Continue, Try again): the last stopped or failed turn, and only while the
/// person has not written since. Earlier ones are only a record.
public func openOutcome(_ rows: [FeedRow]) -> String? {
    for row in rows.reversed() {
        switch row {
        case .user: return nil
        case .error(let id, _), .stopped(let id): return id
        default: continue
        }
    }
    return nil
}

/// A banner over the feed or the box: what the provider said (or the host's reason), and the hint under it when there is one.
public struct FailureBanner: Equatable {
    public let title: String
    public let detail: String
    public let hint: String?
}

/// A key like `claude` starts a sentence as `Claude`; a name that already has a capital in it (a label like `iOS`) is the person's own and stays.
private func capitalized(_ agent: String) -> String {
    if agent.isEmpty { return "The agent" }
    return agent.contains(where: \.isUppercase) ? agent : agent.prefix(1).uppercased() + agent.dropFirst()
}

/// The banner of a turn that failed: "<Agent> couldn't continue" and the error's text.
public func failedTurnBanner(agent: String, error: String) -> FailureBanner {
    FailureBanner(title: "\(capitalized(agent)) couldn't continue", detail: error, hint: nil)
}

/// The banner of a refusal from `open`, `resume` or `send`: the host's own sentence, and for a provider that is not signed in the
/// line that says where to sign in.
public func refusalBanner(agent: String, reason: String) -> FailureBanner {
    if let hint = signInLine(refusal: reason) { return FailureBanner(title: "\(capitalized(agent)) isn't signed in", detail: reason, hint: hint) }
    return FailureBanner(title: "\(capitalized(agent)) couldn't continue", detail: reason, hint: nil)
}

/// Above the box of a session that is not live: sending to it resumes it.
public let closedSessionNotice = (
    title: "This session is asleep",
    detail: "Its agent is napping. Send a message and it wakes up right where it left off.",
    chosen: "Its agent is napping. What you chose applies as soon as a message wakes it up."
)

/// The line under a refusal when the provider is not signed in, nil for any other. The adapters say "<Agent> is not logged in; run … once to log in".
public func signInLine(refusal reason: String) -> String? {
    reason.localizedCaseInsensitiveContains("is not logged in") ? "Sign in from a terminal; Carrier never asks for your password" : nil
}

/// An approval as the card draws it: the question, the tool and its argument, and the provider's choices in its own order.
public struct ApprovalCard: Equatable {
    public let approvalId: String
    public let question: String
    public let tool: String
    public let arg: String?
    public let choices: [ChatChoice]
    /// The questions of an `AskUserQuestion` approval; empty for any other, which is drawn as the generic card.
    public let questions: [ChatQuestion]
}

/// The rows the events make, in order, and then the message in progress when `streaming` has text. Consecutive calls are one row
/// at the place where the first started, each completed by its end (a turn that ends first stops the calls still going); an
/// approval is one row at the place where it was asked: a card while its id is in `pending` (what the host still waits for),
/// a line once answered, and a plain line when it is neither (the turn ended without it).
/// A `reasoning` event is a thought of the run of calls it comes in (the host stores each block where the agent had it); one that comes
/// before the first call of a run waits for it, and one with no call after it is a run of its own, before the message or the end of its
/// turn: the agent's work is always above its answer. A subagent is a row of the run that launched it, built from the `task` events that share its
/// launching call's id and the events made inside it (`parentCallId`); the launching call is not one of the run's calls, and a subagent goes on
/// from events that come after the turn ended. What a nested subagent does is not drawn here. A subagent that started and never ended, in a
/// session that is not `working`, is shown stopped: the host that ran it is gone.
/// Anything else the host may add is not drawn.
public func chatFeed(_ events: [ChatEvent], streaming: String = "", pending: Set<String> = [], working: Bool = true) -> [FeedRow] {
    var rows: [FeedRow] = []
    // where each call still going is: its row and its place in it
    var going: [String: (row: Int, call: Int)] = [:]
    var asked: [String: (row: Int, event: ChatEvent)] = [:]
    var turnStart: Int?
    var held: [Thought] = []
    // the calls that launched a subagent of the main agent (a `task` event names its call), and where each subagent is: its row and its place in it
    let launching = Set(events.compactMap { $0.kind == "task" && $0.parentCallId == nil ? $0.callId : nil })
    var subagents: [String: (row: Int, index: Int)] = [:]
    // thoughts no call came to take: a run of their own, where the piece that ends them begins
    func release() {
        guard let first = held.first else { return }
        rows.append(.tools(id: first.id, ToolGroup(calls: [], thoughts: held, since: turnStart)))
        held = []
    }
    for event in events {
        // made inside a subagent: the main conversation does not draw it, it is what its row says it is doing
        if let parent = event.parentCallId {
            if let spot = subagents[parent], case .tools(let group, var run) = rows[spot.row] {
                run.subagents[spot.index].apply(inside: event)
                rows[spot.row] = .tools(id: group, run)
            }
            continue
        }
        let id = "e\(event.id)"
        switch event.kind {
        case "task":
            guard let call = event.callId, launching.contains(call) else { continue }
            if let spot = subagents[call], case .tools(let group, var run) = rows[spot.row] {
                run.subagents[spot.index].apply(task: event)
                rows[spot.row] = .tools(id: group, run)
            } else {
                subagents[call] = place(Subagent(task: event), in: &rows, id: id, held: &held)
            }
        case "tool_start" where event.callId.map(launching.contains) == true, "tool_end" where event.callId.map(launching.contains) == true:
            continue
        case "reasoning":
            // trimmed: the provider's blocks start and end with blank lines, and the card shows two lines of a thought
            guard let text = event.text?.trimmingCharacters(in: .whitespacesAndNewlines), text.isEmpty == false else { continue }
            if case .tools(let group, var run)? = rows.last {
                run.thoughts.append(Thought(id: id, text: text, at: event.at, before: run.calls.count))
                rows[rows.count - 1] = .tools(id: group, run)
            } else {
                held.append(Thought(id: id, text: text, at: event.at, before: 0))
            }
        case "user":
            release()
            turnStart = event.at
            rows.append(.user(id: id, text: event.text ?? ""))
        case "assistant":
            release()
            rows.append(.agent(id: id, text: event.text ?? "", inProgress: false))
        case "tool_start":
            let call = ToolCall(start: event)
            going[call.id] = place(call, in: &rows, id: id, held: &held)
        case "tool_end":
            if let call = event.callId, let spot = going.removeValue(forKey: call), case .tools(let group, var calls) = rows[spot.row] {
                calls.calls[spot.call].finish(event)
                rows[spot.row] = .tools(id: group, calls)
            } else {
                _ = place(ToolCall(orphanEnd: event), in: &rows, id: id, held: &held)
            }
        case "approval":
            if let approval = event.approvalId { asked[approval] = (rows.count, event) }
            if let approval = event.approvalId, pending.contains(approval) {
                let tool = event.tool ?? "the tool"
                rows.append(.approval(id: id, ApprovalCard(approvalId: approval, question: "Allow \(tool)?", tool: tool, arg: event.arg, choices: event.choices ?? [], questions: event.questions ?? [])))
            } else {
                rows.append(.line(id: id, text: "\(what(event)) · no longer waiting for an answer"))
            }
        case "approval_answered":
            guard let approval = event.approvalId, let question = asked[approval] else { continue }
            rows[question.row] = decided(question.event, choice: event.choiceId, answers: event.answers, id: rows[question.row].id)
        case "turn_end":
            release()
            for spot in going.values {
                guard case .tools(let group, var calls) = rows[spot.row] else { continue }
                calls.calls[spot.call].stop()
                rows[spot.row] = .tools(id: group, calls)
            }
            going = [:]
            if event.outcome == "error" { markLastRunErred(in: &rows) }
            if let summary = TurnSummary(event, turnStart: turnStart) { rows.append(.turnEnd(id: id, summary)) }
            if event.outcome == "interrupted" { rows.append(.stopped(id: "\(id)-stopped")) }
            turnStart = nil
        case "error":
            release()
            rows.append(.error(id: id, text: event.text ?? "Something went wrong"))
        case "notice":
            // said by the host (a resume that began a new conversation): a plain line, never the banner of a failed turn
            release()
            if let text = event.text { rows.append(.line(id: id, text: text)) }
        default:
            continue
        }
    }
    release()
    if working == false, let last = events.last?.at {
        for index in rows.indices {
            guard case .tools(let id, var run) = rows[index], run.runningSubagents > 0 else { continue }
            for slot in run.subagents.indices where run.subagents[slot].status == .running { run.subagents[slot].stop(at: last) }
            rows[index] = .tools(id: id, run)
        }
    }
    if streaming.isEmpty == false { rows.append(.agent(id: "streaming", text: streaming, inProgress: true)) }
    return rows
}

/// The ids of the subagents the events show running, in the order they started: a start with no end, as the host counts them.
private func runningTasks(in events: [ChatEvent]) -> [String] {
    var running: [String] = []
    for event in events where event.kind == "task" {
        guard let task = event.taskId else { continue }
        switch event.state {
        case "started": if running.contains(task) == false { running.append(task) }
        case "completed", "failed", "stopped": running.removeAll { $0 == task }
        default: break
        }
    }
    return running
}

/// The run a turn that failed ended in: the last one of the turn, when the agent had not written an answer after it.
private func markLastRunErred(in rows: inout [FeedRow]) {
    for index in rows.indices.reversed() {
        switch rows[index] {
        case .tools(let id, var group):
            group.erred = true
            rows[index] = .tools(id: id, group)
            return
        case .user, .agent: return
        default: continue
        }
    }
}

/// Puts a call at the end of the run the last row is, or opens a row for it that starts with the thoughts that were waiting.
private func place(_ call: ToolCall, in rows: inout [FeedRow], id: String, held: inout [Thought]) -> (row: Int, call: Int) {
    if case .tools(let group, var run)? = rows.last {
        run.calls.append(call)
        rows[rows.count - 1] = .tools(id: group, run)
        return (rows.count - 1, run.calls.count - 1)
    }
    rows.append(.tools(id: held.first?.id ?? id, ToolGroup(calls: [call], thoughts: held)))
    held = []
    return (rows.count - 1, 0)
}

/// Puts a subagent at the end of the run the last row is, or opens a row for it, as `place` does for a call.
private func place(_ subagent: Subagent, in rows: inout [FeedRow], id: String, held: inout [Thought]) -> (row: Int, index: Int) {
    if case .tools(let group, var run)? = rows.last {
        run.subagents.append(subagent)
        rows[rows.count - 1] = .tools(id: group, run)
        return (rows.count - 1, run.subagents.count - 1)
    }
    rows.append(.tools(id: held.first?.id ?? id, ToolGroup(calls: [], thoughts: held, subagents: [subagent])))
    held = []
    return (rows.count - 1, 0)
}

private func what(_ approval: ChatEvent) -> String { [approval.tool, approval.arg].compactMap { $0 }.joined(separator: " ") }

/// "Allowed pnpm test · Allow once · by you": the verb is from whether the chosen choice allows, the label is the provider's own.
private func decided(_ approval: ChatEvent, choice: String?, answers: [String: String]?, id: String) -> FeedRow {
    if let questions = approval.questions, questions.isEmpty == false {
        guard let answers, let chosen = approval.choices?.first(where: { $0.id == choice })?.allow, chosen else {
            return .decided(id: id, text: "Skipped the questions · by you", allow: false)
        }
        let parts = questions.compactMap { question in answers[question.question].map { "\(question.header): \($0)" } }
        return .decided(id: id, text: (["Answered · by you"] + parts).joined(separator: "\n"), allow: true)
    }
    guard let chosen = approval.choices?.first(where: { $0.id == choice }) else {
        return .decided(id: id, text: "Answered \(what(approval)) · by you", allow: false)
    }
    return .decided(id: id, text: "\(chosen.allow ? "Allowed" : "Declined") \(what(approval)) · \(chosen.label) · by you", allow: chosen.allow)
}

/// "claude-sonnet-5-5 · 12s · 1.8k in · 436 out": each part only when the host or the provider gave it.
/// What closes a turn: the model, how long it took and the tokens the provider reported. `text` is all of it as one line.
public struct TurnSummary: Equatable {
    public var model: String?
    public var duration: String?
    /// What the model read: the new input and what came from the cache (most of it once a session has a history).
    public var input: Double?
    public var cacheRead: Double?
    public var cacheWrite: Double?
    public var output: Double?
    /// What the turn's last model call read: the context at the turn's end. The three counts above add every call of the turn up, and each call
    /// reads the whole context again, so they are many times it; nil from a host that does not say it.
    public var contextTokens: Double?

    public init(model: String? = nil, duration: String? = nil, input: Double? = nil, cacheRead: Double? = nil, cacheWrite: Double? = nil, output: Double? = nil, contextTokens: Double? = nil) {
        (self.model, self.duration, self.input, self.cacheRead, self.cacheWrite, self.output) = (model, duration, input, cacheRead, cacheWrite, output)
        self.contextTokens = contextTokens
    }

    init?(_ end: ChatEvent, turnStart: Int?) {
        func count(_ keys: String...) -> Double? { keys.lazy.compactMap { end.usage?[$0] }.first }
        self.init(
            model: end.model, duration: turnStart.map { formatDuration(end.at - $0) },
            input: count("input_tokens", "inputTokens"), cacheRead: count("cache_read_input_tokens", "cacheReadInputTokens"),
            cacheWrite: count("cache_creation_input_tokens", "cacheCreationInputTokens"), output: count("output_tokens", "outputTokens"),
            contextTokens: count("context_tokens", "contextTokens")
        )
        if text.isEmpty { return nil }
    }

    /// Everything the turn's model calls read added up, nil when the provider reported none of it.
    public var read: Double? {
        let reads = [input, cacheRead, cacheWrite].compactMap { $0 }
        return reads.isEmpty ? nil : reads.reduce(0, +)
    }

    /// `181.2k context`: the context at the turn's end. A host that does not say it (an older one, or a turn it stored before) leaves only what the
    /// calls read added up, which is not the context and is not called that: `540.1k in`.
    public var contextText: String? {
        if let contextTokens { return "\(Self.tokens(contextTokens)) context" }
        return read.map { "\(Self.tokens($0)) in" }
    }

    /// `12`, `2.5k`: a count as the line writes it.
    public static func tokens(_ count: Double) -> String { count < 1000 ? "\(Int(count))" : String(format: "%.1fk", count / 1000) }

    public var text: String {
        [shortModel, duration, contextText, output.map { "\(Self.tokens($0)) out" }].compactMap { $0 }.joined(separator: " · ")
    }

    /// The model as a person says it: `claude-haiku-5-5` is `haiku 5.5`, and a dated one (`claude-opus-4-1-20250805`) loses its date. A name
    /// that is not Claude's, or not in that shape, stays as it came.
    public var shortModel: String? {
        guard let model else { return nil }
        guard model.hasPrefix("claude-") else { return model }
        var parts = model.dropFirst("claude-".count).split(separator: "-").map(String.init)
        if let last = parts.last, last.count == 8, last.allSatisfy(\.isNumber) { parts.removeLast() }
        guard let family = parts.first, parts.dropFirst().allSatisfy({ $0.allSatisfy(\.isNumber) }), parts.count > 1 else { return model }
        return "\(family) \(parts.dropFirst().joined(separator: "."))"
    }
}

/// The closing line of a turn that ends right after an agent message, taken out of the feed and handed to that message by its id: the
/// message shows it (on hover) as part of itself. A closing line after anything else stays a row.
public func foldingClosingLines(_ rows: [FeedRow]) -> (rows: [FeedRow], lines: [String: TurnSummary]) {
    var kept: [FeedRow] = []
    var lines: [String: TurnSummary] = [:]
    for row in rows {
        if case .turnEnd(_, let summary) = row, case .agent(let id, _, _)? = kept.last {
            lines[id] = summary
        } else {
            kept.append(row)
        }
    }
    return (kept, lines)
}

/// The conversation of one open session: polls `events` by cursor while `run()` is running (the view runs it in a task that ends
/// when the person leaves the session), in pages of at most `ConversationModel.page`, and keeps the feed.
@MainActor @Observable public final class ConversationModel {
    public static let page = 200
    public static let intervalMilliseconds = 250
    public static let interval = Duration.milliseconds(intervalMilliseconds)

    public let sessionId: String
    public private(set) var rows: [FeedRow] = []
    /// Whether the first answer has arrived: until it does the view is loading, not empty.
    public private(set) var loaded = false
    /// Why the last poll failed, nil when it worked; the polling goes on, as the host may come back.
    public private(set) var failure: String?
    /// The `after` of the next request.
    public private(set) var cursor = 0
    /// Whether new output scrolls the view to the end: the Follow new output setting, set by the view.
    public var followsOutput = true
    /// Whether the view is at the end of the conversation: the view reports it as the person scrolls.
    public var atEnd = true
    /// Counts the times the view is to scroll to the end: new output arrived while it follows and the person was at the end.
    public private(set) var scrolls = 0
    /// When each message was written (ms since the epoch), by the id of its row; the message in progress has none yet.
    public private(set) var times: [String: Int] = [:]
    /// Called when a turn fails with a quota error (the Usage page's quotas are then out of date).
    @ObservationIgnored public var onQuotaError: (@MainActor () -> Void)?
    /// What is typed in the box; kept in `memory` as it changes, so it is still there when the person comes back to the session.
    public var draft = "" {
        didSet { if draft != oldValue { memory.saveDraft(sessionId, draft) } }
    }
    /// Whether the agent is answering (or waiting for an approval): the host refuses a message then, so the box queues it and the send button is Stop.
    public private(set) var busy = false
    /// The message typed while the agent answered: one at a time, sent when the turn ends.
    public private(set) var queued: String?
    /// The session's agent, as the host's list names it; what the app saw last until the first answer, empty for a session it never saw.
    public private(set) var agent = ""
    /// Whether the session's agent process runs; a session that is not live shows the closed notice and resumes when a message is sent.
    public private(set) var live = true
    /// Whether the session is asleep: closed, and not on its way to another state (being archived, prepared or woken by a send). Only then the
    /// closed notice shows. It holds at once the first time the session is read; after that a session has to stay closed for a second, as
    /// archiving closes it a moment before the host's list says it is archived.
    public private(set) var asleep = false
    /// Whether a send is waking the session.
    public private(set) var waking = false
    /// The events the feed was built from, added up over every rebuild: a test tells a rebuild (all the events) from an append (one), as
    /// `Transcript.work` does for an epic.
    @ObservationIgnored private(set) var feedWork = 0
    @ObservationIgnored private var closedSince: Date?
    @ObservationIgnored private var known = true
    @ObservationIgnored private var preparingSession = false
    private static let settle: TimeInterval = 1
    /// Whether the session is in the archive: its transcript is read only and the box gives way to a notice with Resume.
    public private(set) var archived = false
    /// What the agent waits for after its turn ended, from the host's list: the card over the box says it.
    public private(set) var background: [BackgroundTask] = []
    /// Whether the host can stop one of those tasks by itself (it lists `stopTask`): read from its hello once.
    public private(set) var canStopTask = false
    /// The message whose send or resume the host refused, for the banner's Try again; nil with no refusal or when it was not a send.
    public private(set) var refusedText: String?
    /// Why the last send, resume, stop or answer was refused, said under the box; nil when it worked.
    public private(set) var refusal: String?
    /// What the provider offers and the values it runs with, as the last `events` reply said: the pill follows this, never a request.
    public private(set) var options: [ChatOption] = []
    /// Why the last change of an option was refused, said in the panel; nil when it worked.
    public private(set) var optionRefusal: String?
    /// What the provider lets the person invoke in this session, as the last `events` reply said; empty for a closed session.
    public private(set) var commands: [ChatCommand] = []
    /// What a closed session could invoke the last time it was seen running, kept like `remembered`.
    public private(set) var rememberedCommands: [ChatCommand] = []
    /// The agent last written to `memory`, so a poll writes it only when it changed: a write to the defaults wakes every observer of them.
    @ObservationIgnored private var savedAgent = ""
    /// What the box lists to invoke: the running agent's, else what it listed when it last ran; that too until the first answer, so the box
    /// does not fill in after the view appears.
    public var shownCommands: [ChatCommand] { commands.isEmpty ? rememberedCommands : commands }
    /// What a closed session offered the last time it was seen running, kept between runs of the app.
    public private(set) var remembered: [ChatOption] = []
    /// The values chosen while the session is closed: the host cannot change them until its agent runs, so they wait and are applied
    /// when a message wakes the session.
    public private(set) var wakeOptions: [String: String] = [:]
    /// What the box lists: what the provider offers while the agent runs, else what it offered last with the choices made since; that too
    /// until the first answer, so the selects are there from the first frame of a session the app has seen.
    public var shownOptions: [ChatOption] {
        if options.isEmpty == false { return options }
        return remembered.map { option in
            guard let chosen = wakeOptions[option.id] else { return option }
            return ChatOption(id: option.id, label: option.label, values: option.values, current: chosen)
        }
    }
    /// The steps of the session's preparation, from its `step` events, while the host prepares it; empty once the agent answers.
    public private(set) var steps: [StepRow] = []
    /// What the person sent as the first message of the session the draft opened, shown until the host's own record of it arrives (a failed
    /// step before the message leaves none) so the text is never lost.
    public private(set) var firstMessage: String?
    /// The subagent view open over the conversation, rebuilt with the feed; nil with none open.
    public private(set) var openSubagent: SubagentWork?
    @ObservationIgnored private var openCall: String?
    /// Whether the host lists `stopTask`, read from its hello once; false until then and for an older host.
    @ObservationIgnored private var hostStops: Bool?
    /// Counts the sends, so a poll that began before one does not tell the model the agent is idle when it is not.
    @ObservationIgnored private var sends = 0

    @ObservationIgnored private let host: ChatHost
    @ObservationIgnored private let sleep: (Duration) async throws -> Void
    @ObservationIgnored private let log: (String) -> Void
    @ObservationIgnored private let memory: OptionsMemory
    @ObservationIgnored private var events: [ChatEvent] = []
    @ObservationIgnored private var streaming = ""
    /// How the session's preparation stands: `failed` offers Try again, `running` offers Cancel; nil once the agent answered.
    public private(set) var preparation: ChatSession.Preparation?
    /// What the host refused when the person asked to try the preparation again or to cancel it, in words.
    public private(set) var preparationRefusal: String?
    @ObservationIgnored private var progress: String?
    /// The approvals the host still waits for, from the last reply.
    @ObservationIgnored private var pending: Set<String> = []
    /// The person's last message, which Try again sends again.
    @ObservationIgnored private var lastUserText: String?

    public init(
        host: ChatHost, sessionId: String, sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        log: @escaping (String) -> Void = { FileHandle.standardError.write(Data("carrier: \($0)\n".utf8)) },
        memory: OptionsMemory = .none
    ) {
        self.host = host
        self.sessionId = sessionId
        self.sleep = sleep
        self.log = log
        self.memory = memory
        remembered = memory.load(sessionId)
        rememberedCommands = memory.loadCommands(sessionId)
        agent = memory.loadAgent(sessionId)
        savedAgent = agent
        draft = memory.loadDraft(sessionId)
    }

    /// Polls until the task is cancelled or `sleep` throws.
    public func run() async {
        repeat { await poll() } while (try? await sleep(Self.interval)) != nil
    }

    /// Whether a round is under way, and whether another was asked for meanwhile.
    @ObservationIgnored private var polling = false
    @ObservationIgnored private var again = false

    /// One round: reads pages until one is not full, then rebuilds the feed when something changed. A round asked for while one is under
    /// way (an action's, or the one `deliver` asks from inside a round) is not a second reader of the same cursor: the one under way goes
    /// round once more when it ends.
    public func poll() async {
        guard polling == false else {
            again = true
            return
        }
        polling = true
        defer { polling = false }
        repeat {
            again = false
            await round()
        } while again
    }

    private func round() async {
        // a round can be asked for from an action while another ends, so each interval has its own id
        let signpost = Signposts.poll.beginInterval("conversation poll", id: Signposts.poll.makeSignpostID())
        let eventsBefore = events.count
        var changed = loaded == false
        defer { Signposts.poll.endInterval("conversation poll", signpost, "\(self.events.count - eventsBefore) new events, changed \(changed)") }
        let sendsBefore = sends
        do {
            var reply: ChatEvents
            var fresh: [ChatEvent]
            repeat {
                reply = try await host.events(sessionId, after: cursor, limit: Self.page)
                // ids only grow (the host reads after the cursor, in order): one already here is never added twice
                fresh = reply.events.filter { $0.id > (events.last?.id ?? 0) }
                // kept as each page comes, so a later page that fails does not lose the cursor's progress
                events += fresh
                if let last = fresh.last(where: { $0.kind == "user" }) { lastUserText = last.text }
                cursor = max(cursor, reply.cursor)
                changed = changed || fresh.isEmpty == false
            // a full page that brought nothing new does not move the cursor: asking again would only get the same page
            } while reply.events.count >= Self.page && fresh.isEmpty == false
            let first = loaded == false
            if hostStops == nil, let listed = try? await host.capabilities() {
                hostStops = listed.contains(.stopTask)
                canStopTask = hostStops == true
                changed = true
            }
            if let session = try await host.list(archived: false).first(where: { $0.id == sessionId }) {
                agent = session.agent
                live = session.live
                archived = false
                known = true
                preparingSession = session.state == .preparing
                background = session.background
            } else if let session = try await host.list(archived: true).first(where: { $0.id == sessionId }) {
                agent = session.agent
                live = false
                archived = true
                known = true
                preparingSession = false
                background = []
            } else {
                live = false
                archived = false
                known = false
                preparingSession = false
                background = []
            }
            settleAsleep(first: first)
            changed = changed || reply.streaming != streaming
            streaming = reply.streaming
            changed = changed || reply.pending != pending
            pending = reply.pending
            if preparation != reply.preparation { preparation = reply.preparation }
            progress = reply.progress
            loaded = true
            failure = nil
            options = reply.options
            commands = reply.commands
            if agent.isEmpty == false, agent != savedAgent {
                memory.saveAgent(sessionId, agent)
                savedAgent = agent
            }
            if reply.commands.isEmpty == false, reply.commands != rememberedCommands {
                rememberedCommands = reply.commands
                memory.saveCommands(sessionId, reply.commands)
            }
            if reply.options.isEmpty == false, reply.options != remembered {
                remembered = reply.options
                memory.save(sessionId, reply.options)
            }
            if sends == sendsBefore, let state = reply.state {
                // the feed shows a subagent that never ended as stopped only while the session is not working
                changed = changed || busy != (state != .idle)
                busy = state != .idle
            }
        } catch {
            let message = Self.words(error)
            if failure != message { log("session \(sessionId): \(message)") }
            failure = message
        }
        let preparing = preparationSteps(events, preparation: preparation, progress: progress)
        if preparing != steps { steps = preparing }
        if changed {
            let next = feed()
            if quotaErrorAppeared(from: rows, to: next) { onQuotaError?() }
            rows = next
            openSubagent = openCall.flatMap(work)
            times = Dictionary(events.filter { $0.kind == "user" || $0.kind == "assistant" }.map { ("e\($0.id)", $0.at) }) { $1 }
            if followsOutput && atEnd { scrolls += 1 }
        }
        if busy == false, let next = queued {
            queued = nil
            await deliver(next)
        }
    }

    /// Enter or the send button: sends what is typed, or holds it as the queued message when the agent is answering (replacing
    /// the one that was held). With `.interrupt` the turn is stopped as well: the host answers the stop once the turn has ended, and the
    /// poll that sees the session idle delivers the held message.
    public func submit(whileWorking: WhileWorking = .queue) async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { return }
        if busy {
            queued = text
            draft = ""
            clearRefusal()
            if whileWorking == .interrupt {
                await stop()
                await poll()
            }
        } else {
            await deliver(text)
        }
    }

    /// A button of an approval card: passes the choice to the host and polls, so the card becomes the line once the host recorded the
    /// answer. A refusal (not pending any more, not one of the choices) is shown in words; the next poll draws what the host says.
    public func answer(_ approvalId: String, choice: String, answers: [String: String]? = nil) async {
        do {
            try await host.answer(sessionId, approval: approvalId, choice: choice, answers: answers)
        } catch {
            refusedText = nil
            refusal = report(error, "answer the approval")
            return
        }
        clearRefusal()
        await poll()
    }

    /// Chooses a value in the options panel: asks the host and reads the session again, so the pill shows what the host says. A
    /// refusal is kept in words for the panel and nothing changes here.
    public func setOption(_ option: String, _ value: String) async {
        // a closed session cannot change anything: the choice waits for the message that wakes it
        if options.isEmpty, loaded, remembered.contains(where: { $0.id == option && $0.values.contains { $0.id == value } }) {
            wakeOptions[option] = value
            optionRefusal = nil
            return
        }
        do {
            try await host.setOption(sessionId, option: option, value: value)
        } catch {
            optionRefusal = report(error, "change the option")
            return
        }
        optionRefusal = nil
        await poll()
    }

    /// Continue on the mark of a stopped turn.
    public func continueTurn() async { await deliver("Continue", refill: false) }

    /// Try again on a failed preparation: the host repeats the steps that did not finish and the list fills in again.
    public func retryPreparation() async {
        do {
            try await host.retryPreparation(sessionId)
        } catch {
            preparationRefusal = report(error, "try the preparation again")
            return
        }
        preparationRefusal = nil
        await poll()
    }

    /// Cancel while preparing: the host stops the running step and deletes the session, and answers the plan for the draft to take back; nil
    /// when it refused, which is said in words and leaves the session as it was.
    public func cancelPreparation() async -> SessionPlan? {
        do {
            let plan = try await host.cancelPreparation(sessionId)
            preparationRefusal = nil
            return plan
        } catch {
            preparationRefusal = report(error, "cancel the preparation")
            return nil
        }
    }

    /// Try again on a banner: the refused message again, or the person's last message when the turn failed.
    public func retry() async {
        if let text = refusedText ?? lastUserText { await deliver(text, refill: false) }
    }

    /// The first message the draft sent with the plan of this session: it shows as the person's message until the host records it.
    public func show(firstMessage text: String) {
        firstMessage = text
        rows = feed()
    }

    private func feed() -> [FeedRow] {
        let signpost = Signposts.feed.beginInterval("chat feed")
        defer { Signposts.feed.endInterval("chat feed", signpost, "\(self.events.count) events") }
        feedWork += events.count
        let rows = chatFeed(events, streaming: streaming, pending: pending, working: busy)
        guard let firstMessage, events.contains(where: { $0.kind == "user" }) == false else { return rows }
        return [.user(id: "first-message", text: firstMessage)] + rows
    }

    /// The subagent view the person opened (the call that launched it), nil for the conversation itself.
    public func show(subagent call: String?) {
        openCall = call
        openSubagent = call.flatMap(work)
    }

    /// The subagent's view from the events, its header saying whether the host can stop it.
    private func work(_ call: String) -> SubagentWork? {
        var work = subagentWork(in: events, call: call, working: busy)
        work?.header.hostStops = hostStops == true
        return work
    }

    /// Stop in the subagent's header: asks the host to stop the open subagent and nothing else. The view shows it stopped when the host's
    /// `stopped` event arrives, not before; a refusal (it ended meanwhile) needs no word, the next poll says how it stands.
    public func stopOpenSubagent() async {
        guard let header = openSubagent?.header, header.canStop, let task = header.taskId else { return }
        do {
            try await host.stopTask(sessionId, task: task)
        } catch {
            _ = report(error, "stop the subagent")
        }
    }

    /// Drops the queued message.
    public func cancelQueued() { queued = nil }

    /// Takes the queued message back into the box to be edited; what is already typed there stays under it.
    public func editQueued() {
        guard let held = queued else { return }
        queued = nil
        draft = draft.isEmpty ? held : held + "\n" + draft
    }

    /// Send now on the queued message: stops the turn, and the poll that sees the agent idle delivers it.
    public func sendQueuedNow() async {
        guard queued != nil else { return }
        await stop()
        await poll()
    }

    /// Stops one of the tasks the agent waits for in the background; the host refuses one that has already ended.
    public func stopTask(_ taskId: String) async {
        do {
            try await host.stopTask(sessionId, task: taskId)
            clearRefusal()
        } catch {
            refusedText = nil
            refusal = report(error, "stop the task")
        }
    }

    /// The Stop button: ends the turn (with none running, the host stops what the agent waits for in the background), then stops each subagent
    /// still running (only a host that lists `stopTask` can; a refusal means it ended meanwhile); the queued message, if any, goes when the poll
    /// sees the agent idle.
    public func stop() async {
        do {
            try await host.interrupt(sessionId)
            clearRefusal()
        } catch {
            refusedText = nil
            refusal = report(error, "stop the turn")
        }
        guard hostStops == true else { return }
        for task in runningTasks(in: events) {
            do {
                try await host.stopTask(sessionId, task: task)
            } catch {
                _ = report(error, "stop the subagent")
            }
        }
    }

    private func settleAsleep(first: Bool) {
        if live || archived || known == false || preparingSession || waking {
            closedSince = nil
        } else if closedSince == nil {
            closedSince = first ? .distantPast : .now
        }
        let next = closedSince.map { Date.now.timeIntervalSince($0) >= Self.settle } ?? false
        if asleep != next { asleep = next }
    }

    /// Sends the text, resuming the session first when the host's list says it is not live. A refusal is shown and the text goes back
    /// to the box when it came from there or from the queue (`refill`); on success the box is emptied unless the person has typed something else.
    private func deliver(_ text: String, refill: Bool = true) async {
        sends += 1
        waking = true
        asleep = false
        defer { waking = false }
        // the box empties on Enter and not when the host has answered; a refusal puts the text back
        if refill, draft.trimmingCharacters(in: .whitespacesAndNewlines) == text { draft = "" }
        do {
            if try await host.list(archived: false).first(where: { $0.id == sessionId })?.live != true {
                try await host.resume(sessionId)
                await applyWakeOptions()
            }
            // a message that starts with the name of a command the session lists invokes it; the host composes what the provider is told
            if let invoked = invokedCommand(in: text, among: shownCommands) {
                try await host.send(sessionId, invoked.arguments, command: invoked.command.id)
            } else {
                try await host.send(sessionId, text)
            }
        } catch {
            refusal = report(error, "send the message")
            refusedText = text
            if refill, draft.isEmpty { draft = text }
            return
        }
        clearRefusal()
        if draft.trimmingCharacters(in: .whitespacesAndNewlines) == text { draft = "" }
        sends += 1
        busy = true
        await poll()
    }

    /// The choices made while the session was closed, now that its agent runs: the model first, as the reasoning levels depend on it. One
    /// the host refuses is said in words and the rest still go.
    private func applyWakeOptions() async {
        let waiting = wakeOptions.sorted { ($0.key == "model" ? 0 : 1, $0.key) < ($1.key == "model" ? 0 : 1, $1.key) }
        wakeOptions = [:]
        for (option, value) in waiting {
            do {
                try await host.setOption(sessionId, option: option, value: value)
            } catch {
                optionRefusal = report(error, "change the option")
            }
        }
    }

    private func clearRefusal() {
        refusal = nil
        refusedText = nil
    }

    private func report(_ error: Error, _ doing: String) -> String {
        let message = Self.words(error)
        // a refusal is the host answering as it should; anything else is a failure to talk to it
        if case ControlError.remote = error { return message }
        log("session \(sessionId): could not \(doing): \(message)")
        return message
    }

    nonisolated static func words(_ error: Error) -> String {
        switch error {
        case ControlError.closed: "The chat host is not answering"
        case ControlError.remote(let reason): reason
        case ControlError.timeout: "The chat host took too long to answer"
        default: "The chat host sent something that was not understood"
        }
    }
}
