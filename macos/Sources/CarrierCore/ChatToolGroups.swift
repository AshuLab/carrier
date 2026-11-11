import Foundation

// A run of the agent's work as the conversation draws it (docs/specs/sessions-in-the-app.md, "The conversation: tools grouped"): one row
// that says what was done, whose thoughts and calls open to their detail. Classification is `ToolKind(tool:)`, by the provider's own tool name.

public enum CallStatus: Equatable {
    case running, ok, failed
    /// The turn ended before the call did: the person stopped it, or the provider failed.
    case stopped
}

/// A `tool_start` completed by its `tool_end`.
public struct ToolCall: Equatable, Identifiable {
    public let id: String
    public let tool: String
    public let kind: ToolKind
    /// What the call is on: the command, the path or the pattern.
    public let arg: String
    public internal(set) var status: CallStatus
    /// The short result of the call's line: "212 lines", "4 matches", "+3 −1", "failed".
    public internal(set) var result = ""
    /// Milliseconds since the epoch.
    public let startedAt: Int
    public internal(set) var endedAt: Int?
    /// The provider's own output, as the host stored it.
    public internal(set) var output: [String] = []
    /// The output of a change read as a diff, when it is shaped like one; the host's events carry no other diff of an edit.
    public internal(set) var diff: [DiffRow] = []
    public internal(set) var added = 0
    public internal(set) var removed = 0

    init(start event: ChatEvent) {
        id = event.callId ?? "e\(event.id)"
        tool = event.tool ?? ""
        kind = ToolKind(tool: event.tool)
        arg = event.arg ?? ""
        status = .running
        startedAt = event.at
    }

    /// A call whose start was before the page the cursor began at.
    init(orphanEnd event: ChatEvent) {
        self.init(start: ChatEvent(id: event.id, at: event.at, kind: "tool_start", callId: event.callId, tool: event.tool, arg: event.arg))
        finish(event)
    }

    mutating func finish(_ end: ChatEvent) {
        endedAt = end.at
        output = end.output ?? []
        while output.last?.isEmpty == true { output.removeLast() }
        status = end.status == "err" ? .failed : .ok
        if kind == .edit { readDiff() }
        result = resultLine()
    }

    mutating func stop() {
        status = .stopped
        result = "stopped"
    }

    public var durationMs: Int? { endedAt.map { $0 - startedAt } }

    /// "Reading src/a.ts", for a call that is going on.
    var doing: String {
        let verb = switch kind {
        case .read: "Reading"
        case .search: "Searching"
        case .edit: "Editing"
        case .shell: "Running"
        case .other: "Using \(tool)"
        }
        return arg.isEmpty ? verb : "\(verb) \(arg)"
    }

    private mutating func readDiff() {
        for line in output {
            let sign: DiffSign
            if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("@@") { sign = .hunk } else if line.hasPrefix("+") {
                sign = .added
                added += 1
            } else if line.hasPrefix("-") {
                sign = .removed
                removed += 1
            } else { sign = .context }
            let text = sign == .context || sign == .hunk ? line : String(line.dropFirst())
            diff.append(DiffRow(sign: sign, text: text.count > maxDiffLineLength ? String(text.prefix(maxDiffLineLength)) + "…" : text))
        }
        // output that is no diff at all is the provider's words about the change, not a diff
        if added + removed == 0 { diff = [] }
    }

    private func resultLine() -> String {
        if status == .failed { return "failed" }
        let lines = output.filter { $0.allSatisfy(\.isWhitespace) == false }
        switch kind {
        case .read: return "\(output.count) \(output.count == 1 ? "line" : "lines")"
        case .search: return lines.isEmpty ? "no matches" : "\(lines.count) \(lines.count == 1 ? "match" : "matches")"
        case .edit: return added + removed > 0 ? "+\(added) −\(removed)" : "done"
        case .shell: return "done"
        case .other: return lines.first.map { String($0.trimmingCharacters(in: .whitespaces).prefix(80)) } ?? "done"
        }
    }
}

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
    /// Whether the turn ended in an error while this was its last run: the work did not finish by itself, the provider failed.
    public internal(set) var erred = false
    /// Where a run of thoughts with no call counts its time from: the start of the turn. ponytail: a thought-only run late in a turn counts from the
    /// turn's start too; track the end of the previous piece if that ever reads wrong.
    var since: Int?

    public init(calls: [ToolCall], thoughts: [Thought] = [], since: Int? = nil) {
        (self.calls, self.thoughts, self.since) = (calls, thoughts, since)
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
        if calls.isEmpty { return "Thought" }
        if calls.contains(where: { $0.kind == .edit }) { return "Changed" }
        return calls.allSatisfy({ $0.kind == .read || $0.kind == .search }) ? "Explored" : "Worked"
    }

    /// The non-zero counts as "3 thoughts · 2 files read · 1 search · 2 files changed · 1 command", in that order; files changed counts distinct paths.
    public var summary: String {
        func count(_ kind: ToolKind) -> Int { calls.filter { $0.kind == kind }.count }
        func part(_ n: Int, _ one: String, _ many: String) -> String? { n == 0 ? nil : "\(n) \(n == 1 ? one : many)" }
        let changed = Set(calls.filter { $0.kind == .edit }.map { $0.arg.isEmpty ? $0.id : $0.arg }).count
        return [
            part(thoughts.count, "thought", "thoughts"),
            part(count(.read), "file read", "files read"), part(count(.search), "search", "searches"),
            part(changed, "file changed", "files changed"), part(count(.shell), "command", "commands"),
            part(count(.other), "other tool", "other tools"),
        ].compactMap { $0 }.joined(separator: " · ")
    }

    public var failed: Int { calls.filter { $0.status == .failed }.count }
    public var added: Int { calls.reduce(0) { $0 + $1.added } }
    public var removed: Int { calls.reduce(0) { $0 + $1.removed } }
    public var isWorking: Bool { calls.contains { $0.status == .running } }
    /// Whether the turn was stopped before a call ended.
    public var isStopped: Bool { calls.contains { $0.status == .stopped } }
    /// What the agent is doing now: the call that started last of those still going.
    public var doing: String? { calls.last { $0.status == .running }?.doing }

    /// When the first step started, in milliseconds since the epoch.
    public var startedAt: Int { since ?? [calls.first?.startedAt, thoughts.first?.at].compactMap { $0 }.min() ?? 0 }
    /// How long the run took; nil while it goes on, and for a lone thought that has no span.
    public var durationMs: Int? {
        guard isWorking == false, let end = (calls.compactMap(\.endedAt) + thoughts.map(\.at)).max() else { return nil }
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
            return group.calls.isEmpty && group.thoughts.isEmpty ? nil : .tools(id: id, group)
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
