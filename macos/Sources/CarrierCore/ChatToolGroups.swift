import Foundation

// A run of tool calls as the conversation draws it (docs/specs/sessions-in-the-app.md, "The conversation: tools grouped"): one row
// that says what was done, whose calls open to their detail. Classification is `ToolKind(tool:)`, by the provider's own tool name.

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

/// The calls between two pieces of the conversation, and what they say together.
public struct ToolGroup: Equatable {
    public internal(set) var calls: [ToolCall]

    /// Explored when there are only reads and searches, Changed when there is a change, Worked otherwise; Working while a call is going.
    public var title: String {
        if isWorking { return "Working" }
        if calls.contains(where: { $0.kind == .edit }) { return "Changed" }
        return calls.allSatisfy({ $0.kind == .read || $0.kind == .search }) ? "Explored" : "Worked"
    }

    /// The non-zero counts as "2 files read · 1 search · 2 files changed · 1 command", in that order; files changed counts distinct paths.
    public var summary: String {
        func count(_ kind: ToolKind) -> Int { calls.filter { $0.kind == kind }.count }
        func part(_ n: Int, _ one: String, _ many: String) -> String? { n == 0 ? nil : "\(n) \(n == 1 ? one : many)" }
        let changed = Set(calls.filter { $0.kind == .edit }.map { $0.arg.isEmpty ? $0.id : $0.arg }).count
        return [
            part(count(.read), "file read", "files read"), part(count(.search), "search", "searches"),
            part(changed, "file changed", "files changed"), part(count(.shell), "command", "commands"),
            part(count(.other), "other tool", "other tools"),
        ].compactMap { $0 }.joined(separator: " · ")
    }

    public var failed: Int { calls.filter { $0.status == .failed }.count }
    public var added: Int { calls.reduce(0) { $0 + $1.added } }
    public var removed: Int { calls.reduce(0) { $0 + $1.removed } }
    public var isWorking: Bool { calls.contains { $0.status == .running } }
    /// What the agent is doing now: the call that started last of those still going.
    public var doing: String? { calls.last { $0.status == .running }?.doing }

    /// When the first call started, in milliseconds since the epoch.
    public var startedAt: Int { calls.first?.startedAt ?? 0 }
    /// How long the run took; nil while it goes on.
    public var durationMs: Int? {
        guard isWorking == false, let end = calls.compactMap(\.endedAt).max() else { return nil }
        return end - startedAt
    }
}
