import Foundation

// The transcript under an open session: the events fetched so far turned into one item per message, note, error, thought or tool call
// (docs/specs/macos-app-redesign.md, story 20). A tool call arrives as a `tool_start` and a `tool_end` joined by `callId`, and becomes
// the chat's `ToolCall`: `flowItems` then groups the calls into the chat's `ToolGroup`, so the epic and a session draw them with the same views.

public enum ToolStatus: Equatable {
    case ok, error
    /// Started and not ended yet.
    case pending

    /// The status mark; nil for pending, which is a spinner.
    public var icon: AppIcon? {
        switch self {
        case .ok: .checkCircleFilled
        case .error: .closeCircleFilled
        case .pending: nil
        }
    }
}

public enum ToolKind: Hashable {
    case read, search, edit, shell, other
    /// A call to a tool of an MCP server, named `mcp__<server>__<tool>`.
    case mcp(server: String, tool: String)

    public init(tool: String?) {
        if let tool, tool.hasPrefix("mcp__") {
            let rest = tool.dropFirst("mcp__".count)
            if let split = rest.range(of: "__"), split.lowerBound > rest.startIndex, split.upperBound < rest.endIndex {
                self = .mcp(server: String(rest[..<split.lowerBound]), tool: String(rest[split.upperBound...]))
                return
            }
        }
        switch tool {
        case "Read": self = .read
        case "Grep", "Glob": self = .search
        case "Edit", "MultiEdit", "Write", "NotebookEdit", "apply_patch": self = .edit
        // "command" is the Codex chat adapter's own name for a command it ran
        case "Bash", "shell", "exec_command", "command": self = .shell
        default: self = .other
        }
    }

    /// The icon of the kind of call.
    public var icon: AppIcon {
        switch self {
        case .read: .fileText
        case .search: .search
        case .edit: .pencil
        case .shell: .terminal
        case .other: .tool
        case .mcp: .plug
        }
    }
}

/// How many rows of an edit's diff are drawn before "Show N more lines".
public let collapsedDiffRows = 30

/// `hunk` is the quiet separator between fragments that are not adjacent; its text is git's `@@ -a,b +c,d @@`.
public enum DiffSign: Equatable { case added, removed, context, hunk }

/// Diff rows as a card first shows them: `collapsedDiffRows` rows, and how many are left out. All of them once expanded.
public func visibleDiffRows(_ rows: [DiffRow], expanded: Bool) -> (rows: [DiffRow], hidden: Int) {
    guard expanded == false, rows.count > collapsedDiffRows else { return (rows, 0) }
    return (Array(rows.prefix(collapsedDiffRows)), rows.count - collapsedDiffRows)
}

public struct DiffRow: Equatable {
    public var sign: DiffSign
    public var text: String
}

/// One line of the split view: what was removed on the left and what was added on the right, either missing when the other side has
/// no match. A context line or a hunk separator fills both sides with the same row.
public struct DiffPair: Equatable {
    public var left: DiffRow?
    public var right: DiffRow?
}

/// The rows of a diff as the split view draws them: each block of changed rows pairs its removed lines with its added ones, in order.
public func splitDiffPairs(_ rows: [DiffRow]) -> [DiffPair] {
    var pairs: [DiffPair] = []
    var removed: [DiffRow] = []
    var added: [DiffRow] = []
    func flush() {
        for i in 0..<max(removed.count, added.count) {
            pairs.append(DiffPair(left: i < removed.count ? removed[i] : nil, right: i < added.count ? added[i] : nil))
        }
        removed = []
        added = []
    }
    for row in rows {
        switch row.sign {
        case .removed: removed.append(row)
        case .added: added.append(row)
        case .context, .hunk:
            flush()
            pairs.append(DiffPair(left: row, right: row))
        }
    }
    flush()
    return pairs
}

public struct CardDiff: Equatable {
    public var rows: [DiffRow]
    public var added: Int
    public var removed: Int
}

/// A diff line longer than this is cut and ends in an ellipsis: one huge line would make its row too slow to lay out.
public let maxDiffLineLength = 2_000

/// The `diff` of an event (or of a `fileDiff` reply) as rows: "+" added, "-" removed, "@" a hunk separator, anything else (" " and a
/// sign this app does not know) context.
/// nil for no diff or an empty one.
public func cardDiff(_ diff: [ExecEvent.DiffLine]?) -> CardDiff? {
    guard let diff, diff.isEmpty == false else { return nil }
    var result = CardDiff(rows: [], added: 0, removed: 0)
    result.rows.reserveCapacity(diff.count)
    for line in diff {
        let sign: DiffSign = switch line.sign {
        case "+": .added
        case "-": .removed
        case "@": .hunk
        default: .context
        }
        if sign == .added { result.added += 1 } else if sign == .removed { result.removed += 1 }
        let text = line.text.count > maxDiffLineLength ? String(line.text.prefix(maxDiffLineLength)) + "…" : line.text
        result.rows.append(DiffRow(sign: sign, text: text))
    }
    return result
}

public enum TranscriptItem: Equatable, Identifiable {
    case message(id: Int, text: String)
    case note(id: Int, text: String)
    case error(id: Int, text: String)
    /// A block of the agent's reasoning (a `reasoning` event, as the chat host stores it). The engine's parsers send none today.
    case thought(id: Int, text: String, at: Int)
    case tool(id: Int, ToolCall)

    /// The id of the first event of the item, so a call keeps its place when its end arrives.
    public var id: Int {
        switch self {
        case .message(let id, _), .note(let id, _), .error(let id, _), .thought(let id, _, _), .tool(let id, _): id
        }
    }
}

/// "340 ms", "6 s", "2m 05s": milliseconds under a second, whole seconds under a minute (the tenths are noise from the first second
/// on), then minutes and seconds (a call is a span that has ended, so its seconds stay) and the panel's own format from an hour.
public func formatCallDuration(_ ms: Int) -> String {
    if ms < 1000 { return "\(max(0, ms)) ms" }
    if ms < 60_000 { return "\(ms / 1000) s" }
    let seconds = ms / 1000
    return seconds < 3600 ? "\(seconds / 60)m \(String(format: "%02d", seconds % 60))s" : formatDuration(ms)
}

/// The items of a transcript, built one event at a time: an append touches only the new event (and its call's card), never the
/// whole list. `work` counts the events processed, so a test can tell an append from a rebuild.
struct TranscriptBuilder: Equatable {
    private struct Call {
        var id: Int
        var index: Int
        var start: ExecEvent?
        var end: ExecEvent?
    }

    private(set) var items: [TranscriptItem] = []
    private(set) var work = 0
    private var calls: [String: Call] = [:]

    static func == (a: Self, b: Self) -> Bool { a.items == b.items }

    /// Back to nothing, keeping the count of work done.
    mutating func reset() {
        items = []
        calls = [:]
    }

    /// Events must come in id order and once each. A `task` event and any kind this app does not know are left out.
    mutating func add(_ event: ExecEvent) {
        work += 1
        switch event.kind {
        case "say": items.append(.message(id: event.id, text: event.text ?? ""))
        case "note": items.append(.note(id: event.id, text: event.text ?? ""))
        case "error": items.append(.error(id: event.id, text: event.text ?? ""))
        case "reasoning":
            // trimmed and never empty, as the chat's feed takes it
            if let text = event.text?.trimmingCharacters(in: .whitespacesAndNewlines), text.isEmpty == false { items.append(.thought(id: event.id, text: text, at: event.at)) }
        case "tool_start", "tool_end":
            // an event with no callId is a call of its own
            let key = event.callId ?? "event \(event.id)"
            let known = calls[key]
            var call = known ?? Call(id: event.id, index: items.count)
            if event.kind == "tool_start" { call.start = event } else { call.end = event }
            let item = TranscriptItem.tool(id: call.id, Self.call(call.start, call.end, id: call.id))
            if known == nil { items.append(item) } else { items[call.index] = item }
            calls[key] = call
        default: break
        }
    }

    /// The call as the chat draws it: the start and the end the engine's parser sent, as the chat host would have stored them. The edit's
    /// structured diff replaces the one the chat reads out of an output, a read or a search says what the engine counted (its output is only
    /// the first and last lines) and a failure with no output says why in the engine's words.
    private static func call(_ start: ExecEvent?, _ end: ExecEvent?, id: Int) -> ToolCall {
        let tool = end?.tool ?? start?.tool ?? "tool"
        let callId = start?.callId ?? end?.callId
        var call = ToolCall(start: ChatEvent(id: id, at: (start ?? end)?.at ?? 0, kind: "tool_start", callId: callId, tool: tool, arg: start?.arg ?? end?.arg))
        guard let end else { return call }
        call.finish(ChatEvent(id: end.id, at: end.at, kind: "tool_end", callId: callId, tool: tool, output: end.output, status: end.status))
        if let ms = end.durationMs { call.endedAt = call.startedAt + ms }
        if call.status == .ok, let diff = cardDiff(end.diff) {
            (call.diff, call.added, call.removed) = (diff.rows, diff.added, diff.removed)
            call.result = call.resultLine()
        }
        let summary = end.summary ?? ""
        if call.status == .failed, call.output.isEmpty, summary.isEmpty == false { call.output = [summary] }
        if call.status == .ok, summary.isEmpty == false, call.kind == .read || call.kind == .search { call.result = summary }
        return call
    }
}

/// Events in, items out, in id order. An event seen twice counts once, a call whose end came first still has one card, and a call
/// with no end is pending. A `task` event and any kind this app does not know are left out.
public func transcriptItems(_ events: [ExecEvent]) -> [TranscriptItem] {
    var transcript = Transcript()
    transcript.apply(EventsReply(events: events, next: 0, running: true, structured: true))
    return transcript.items
}

/// What an open session shows: the main rows and the subagents in event order, with the runs of calls folded, or the summarised `tail` lines of a harness with no parser yet.
public enum TranscriptBody: Equatable {
    /// The events of the session have not arrived yet: a loading row, not "No activity yet".
    case loading
    case items([FlowItem])
    case tail([String])
}

public func transcriptBody(
    _ transcript: Transcript?, slices: [EpicReply.Slice] = [], running: Bool = false, now: Int = Int(Date().timeIntervalSince1970 * 1000),
    time: TimeFormat = .stored()
) -> TranscriptBody {
    guard let transcript else { return .loading }
    return transcript.structured ? .items(transcript.flow(slices: slices, running: running, now: now, time: time)) : .tail(transcript.tail)
}
