import Foundation

// A run of the agent's work as the conversation draws it (docs/specs/sessions-in-the-app.md, "The conversation: tools grouped"): one row
// that says what was done, whose thoughts and calls open to their detail. Classification is `ToolKind(tool:)`, by the provider's own tool name.

/// One block of the agent's reasoning, placed among the calls of its run.
public struct Thought: Equatable, Identifiable {
    public let id: String
    public let text: String
    /// Milliseconds since the epoch: when the block ended (the provider gives it whole, never in pieces).
    public let at: Int
    /// How many of the run's calls came before it.
    public let before: Int
}

/// One step of a run, in the order the agent took it.
public enum WorkStep: Equatable, Identifiable {
    case thought(Thought)
    case call(ToolCall)

    public var id: String {
        switch self {
        case .thought(let thought): thought.id
        case .call(let call): call.id
        }
    }
}

/// What the agent did between two pieces of the conversation: its calls and its reasoning, in order, and what they say together.
public struct ToolGroup: Equatable {
    public internal(set) var calls: [ToolCall]
    public internal(set) var thoughts: [Thought] = []
    /// The subagents the run launched, in the order they started.
    public internal(set) var subagents: [Subagent] = []
    /// Whether the turn ended in an error while this was its last run: the work did not finish by itself, the provider failed.
    public internal(set) var erred = false
    /// Where a run of thoughts with no call counts its time from: the start of the turn. ponytail: a thought-only run late in a turn counts from the
    /// turn's start too; track the end of the previous piece if that ever reads wrong.
    var since: Int?

    public init(calls: [ToolCall], thoughts: [Thought] = [], subagents: [Subagent] = [], since: Int? = nil) {
        (self.calls, self.thoughts, self.subagents, self.since) = (calls, thoughts, subagents, since)
    }

    /// The thoughts and the calls as one list, in the order they happened.
    public var steps: [WorkStep] {
        var steps: [WorkStep] = []
        var next = 0
        for index in 0...calls.count {
            while next < thoughts.count, thoughts[next].before <= index {
                steps.append(.thought(thoughts[next]))
                next += 1
            }
            if index < calls.count { steps.append(.call(calls[index])) }
        }
        steps += thoughts[next...].map(WorkStep.thought)
        return steps
    }

    /// Failed when the turn ended in an error, Thought when there are no calls, Explored when there are only reads and searches, Changed when there is a change, Worked otherwise;
    /// Working while a call is going.
    public var title: String {
        if isWorking { return "Working" }
        if erred { return "Failed" }
        if calls.isEmpty { return subagents.isEmpty ? "Thought" : "Worked" }
        if calls.contains(where: { $0.kind == .edit }) { return "Changed" }
        return calls.allSatisfy({ $0.kind == .read || $0.kind == .search }) ? "Explored" : "Worked"
    }

    /// The non-zero counts as "3 thoughts · 2 files read · 1 search · 2 files changed · 1 command · 1 MCP call · 2 subagents · 1 other tool", in that order; files changed counts distinct paths.
    public var summary: String {
        func count(_ kind: ToolKind) -> Int { calls.filter { $0.kind == kind }.count }
        func part(_ n: Int, _ one: String, _ many: String) -> String? { n == 0 ? nil : "\(n) \(n == 1 ? one : many)" }
        let mcpCalls = calls.filter { if case .mcp = $0.kind { true } else { false } }.count
        let changed = Set(calls.filter { $0.kind == .edit }.map { $0.arg.isEmpty ? $0.id : $0.arg }).count
        return [
            part(thoughts.count, "thought", "thoughts"),
            part(count(.read), "file read", "files read"), part(count(.search), "search", "searches"),
            part(changed, "file changed", "files changed"), part(count(.shell), "command", "commands"),
            part(mcpCalls, "MCP call", "MCP calls"), part(subagents.count, "subagent", "subagents"),
            part(count(.other), "other tool", "other tools"),
        ].compactMap { $0 }.joined(separator: " · ")
    }

    /// The chip of the live line: Needs you while an approval waits, N subagents while any runs, else the kind of the call going on, Thinking when none is.
    /// Nil for a call with no kind of its own (a web fetch, a todo list): the line then says only its words.
    public func chip(waiting: Bool) -> KindChip? {
        if waiting { return .needsYou }
        if runningSubagents > 0 { return .subagents(runningSubagents) }
        guard let call = calls.last(where: { $0.status == .running }) else { return .thinking }
        switch call.kind {
        case .read: return .read
        case .search: return .search
        case .edit: return .edit
        case .shell: return .shell
        case .mcp(let server, _): return .mcp(server: server)
        case .other: return nil
        }
    }

    /// The timers of the live line at `now`: the running call's own time with the turn's beside it while that is longer, or the turn's alone
    /// while the agent is thinking. The turn counts from `turnStart`, from the run's start when the feed gives none. While subagents run the
    /// own time is the longest-running one's: that is what the line waits on.
    public func liveTimer(now: Int, turnStart: Int? = nil) -> LiveTimer {
        let turn = max(0, now - (turnStart ?? startedAt))
        if let first = subagents.filter({ $0.status == .running }).map(\.startedAt).min() {
            let own = max(0, now - first)
            return LiveTimer(primaryMs: own, turnMs: turn > own ? turn : nil, slow: false)
        }
        guard let call = calls.last(where: { $0.status == .running }) else { return LiveTimer(primaryMs: turn, turnMs: nil, slow: false) }
        let own = call.elapsedMs(now: now)
        return LiveTimer(primaryMs: own, turnMs: turn > own ? turn : nil, slow: call.isSlow(now: now))
    }

    public var failed: Int { calls.filter { $0.status == .failed }.count }
    public var added: Int { calls.reduce(0) { $0 + $1.added } }
    public var removed: Int { calls.reduce(0) { $0 + $1.removed } }
    /// How many subagents of the run are running.
    public var runningSubagents: Int { subagents.filter { $0.status == .running }.count }
    public var isWorking: Bool { calls.contains { $0.status == .running } || runningSubagents > 0 }
    /// Whether the turn was stopped before a call ended.
    public var isStopped: Bool { calls.contains { $0.status == .stopped } }
    /// What the agent is doing now: the call that started last of those still going.
    public var doing: String? { runningSubagents > 0 ? "Waiting for them" : calls.last { $0.status == .running }?.doing }

    /// When the first step started, in milliseconds since the epoch.
    public var startedAt: Int { since ?? [calls.first?.startedAt, thoughts.first?.at, subagents.first?.startedAt].compactMap { $0 }.min() ?? 0 }
    /// How long the run took; nil while it goes on, and for a lone thought that has no span.
    public var durationMs: Int? {
        guard isWorking == false, let end = (calls.compactMap(\.endedAt) + thoughts.map(\.at) + subagents.compactMap(\.endedAt)).max() else { return nil }
        let ms = end - startedAt
        return calls.isEmpty && ms <= 0 ? nil : ms
    }
}

extension ToolCall {
    /// Whether the call opens by itself, by what the person chose for the tools.
    public func opensByDefault(_ mode: ToolOutputMode, opensFailed: Bool) -> Bool { mode.opens(failed: status == .failed, opensFailed: opensFailed) }
}

/// The feed without the calls of its runs when the tools are hidden, and without their thoughts when the person does not want the reasoning;
/// a run left with nothing goes.
public func visibleFeed(_ rows: [FeedRow], mode: ToolOutputMode, showsReasoning: Bool = true) -> [FeedRow] {
    rows.compactMap { row in
        switch row {
        case .tools(let id, var group):
            if mode == .hidden { group.calls = [] }
            if showsReasoning == false { group.thoughts = [] }
            return group.calls.isEmpty && group.thoughts.isEmpty && group.subagents.isEmpty ? nil : .tools(id: id, group)
        // a pending approval is not in the feed: it is the card over the message box (`pendingApprovals`); once answered it is a line
        case .approval: return nil
        default: return row
        }
    }
}

/// The approvals the person can answer now, in the order they were asked: the first is the card over the message box.
public func pendingApprovals(_ rows: [FeedRow]) -> [ApprovalCard] {
    rows.compactMap { if case .approval(_, let card) = $0 { card } else { nil } }
}

/// What the person has flipped after Fold or unfold the tool calls: every run of the feed folded, or all unfolded when all are folded
/// already. A run is folded until it is flipped, so `flipped` is the ids of the runs that are open.
public func togglingToolGroups(in rows: [FeedRow], flipped: Set<String>) -> Set<String> {
    let ids = rows.compactMap { row -> String? in if case .tools(let id, _) = row { id } else { nil } }
    let unfold = ids.allSatisfy { flipped.contains($0) == false }
    return unfold ? flipped.union(ids) : flipped.subtracting(ids)
}

/// The keys of `flipped` that belong to one row of the feed: its own id and the ones under it (`"<id>/..."`, a thought or a call of its run). A row
/// is drawn from these and from nothing else of `flipped`, so it is drawn again only when these change, not when another row's key does.
public func flippedKeys(of id: String, in flipped: Set<String>) -> Set<String> {
    if flipped.isEmpty { return [] }
    let under = id + "/"
    return flipped.filter { $0 == id || $0.hasPrefix(under) }
}

/// The text of the agent's last answer; nil when it has not written one.
public func lastAnswer(in rows: [FeedRow]) -> String? {
    for row in rows.reversed() {
        if case .agent(_, let text, _) = row, text.isEmpty == false { return text }
    }
    return nil
}

/// The run the agent is working in while a turn goes on: the last run of the feed, when no message of the person or of the agent comes after
/// it (once the answer starts, the work is over). Nil when the feed does not end in one.
public func workInProgress(in rows: [FeedRow]) -> String? {
    for row in rows.reversed() {
        switch row {
        case .tools(let id, _): return id
        case .user, .agent, .turnEnd, .error, .stopped: return nil
        default: continue
        }
    }
    return nil
}
