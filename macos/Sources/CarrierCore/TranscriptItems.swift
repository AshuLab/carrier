import Foundation

// The transcript under an open session: the events fetched so far turned into what the view draws, one item per message,
// note, error or tool call (docs/specs/macos-app-redesign.md, story 20). A tool call arrives as a `tool_start` and a
// `tool_end` joined by `callId`.

public enum ToolStatus: Equatable {
    case ok, error
    /// Started and not ended yet.
    case pending

    /// An SF Symbol name; nil for pending, which is a spinner.
    public var icon: String? {
        switch self {
        case .ok: "checkmark"
        case .error: "xmark.circle.fill"
        case .pending: nil
        }
    }
}

public enum ToolKind: Equatable {
    case read, search, edit, shell, other

    public init(tool: String?) {
        switch tool {
        case "Read": self = .read
        case "Grep", "Glob": self = .search
        case "Edit", "MultiEdit", "Write", "NotebookEdit": self = .edit
        case "Bash", "shell", "exec_command": self = .shell
        default: self = .other
        }
    }

    /// An SF Symbol name.
    public var icon: String {
        switch self {
        case .read: "doc.text"
        case .search: "magnifyingglass"
        case .edit: "pencil"
        case .shell: "terminal"
        case .other: "wrench.and.screwdriver"
        }
    }
}

public struct TranscriptCard: Equatable {
    public var tool: String
    public var kind: ToolKind
    public var arg: String
    public var summary: String
    public var status: ToolStatus
    /// "340 ms", "6.2 s"; nil while pending or when the engine gave none.
    public var duration: String?
    /// The first and last lines of what a command printed; empty when the call printed nothing or the engine sent none.
    public var output: [String] = []
    /// The lines an edit changed; nil when there are none.
    public var diff: CardDiff?

    /// Output opens by itself only for a call that failed; any other shows a link.
    public var outputOpenByDefault: Bool { status == .error }
}

public enum DiffSign: Equatable { case added, removed, context }

public struct DiffRow: Equatable {
    public var sign: DiffSign
    public var text: String
}

public struct CardDiff: Equatable {
    public var rows: [DiffRow]
    public var added: Int
    public var removed: Int
}

/// A diff line longer than this is cut and ends in an ellipsis: one huge line would make its row too slow to lay out.
public let maxDiffLineLength = 2_000

/// The `diff` of an event as rows: "+" added, "-" removed, anything else (" " and a sign this app does not know) context.
/// nil for no diff or an empty one.
public func cardDiff(_ diff: [ExecEvent.DiffLine]?) -> CardDiff? {
    guard let diff, diff.isEmpty == false else { return nil }
    var result = CardDiff(rows: [], added: 0, removed: 0)
    result.rows.reserveCapacity(diff.count)
    for line in diff {
        let sign: DiffSign = line.sign == "+" ? .added : line.sign == "-" ? .removed : .context
        if sign == .added { result.added += 1 } else if sign == .removed { result.removed += 1 }
        let text = line.text.count > maxDiffLineLength ? String(line.text.prefix(maxDiffLineLength)) + "…" : line.text
        result.rows.append(DiffRow(sign: sign, text: text))
    }
    return result
}

/// What the user opened or closed by hand, by item id; a card nobody touched follows its default.
public struct OutputFolds: Equatable {
    private var chosen: [Int: Bool] = [:]

    public init() {}

    public func isOpen(_ id: Int, _ card: TranscriptCard) -> Bool { chosen[id] ?? card.outputOpenByDefault }

    public mutating func toggle(_ id: Int, _ card: TranscriptCard) { chosen[id] = !isOpen(id, card) }
}

public enum TranscriptItem: Equatable, Identifiable {
    case message(id: Int, text: String)
    case note(id: Int, text: String)
    case error(id: Int, text: String)
    case tool(id: Int, TranscriptCard)

    /// The id of the first event of the item, so a call keeps its place when its end arrives.
    public var id: Int {
        switch self {
        case .message(let id, _), .note(let id, _), .error(let id, _), .tool(let id, _): id
        }
    }
}

/// "340 ms", "6.2 s", "2m 05s": milliseconds under a second, one decimal under a minute, then the panel's own format.
public func formatCallDuration(_ ms: Int) -> String {
    if ms < 1000 { return "\(max(0, ms)) ms" }
    let tenths = (ms + 50) / 100
    if tenths < 600 { return "\(tenths / 10).\(tenths % 10) s" }
    return formatDuration(max(ms, 60_000))
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
        case "tool_start", "tool_end":
            // an event with no callId is a call of its own
            let key = event.callId ?? "event \(event.id)"
            let known = calls[key]
            var call = known ?? Call(id: event.id, index: items.count)
            if event.kind == "tool_start" { call.start = event } else { call.end = event }
            let item = TranscriptItem.tool(id: call.id, Self.card(call.start, call.end))
            if known == nil { items.append(item) } else { items[call.index] = item }
            calls[key] = call
        default: break
        }
    }

    private static func card(_ start: ExecEvent?, _ end: ExecEvent?) -> TranscriptCard {
        let tool = end?.tool ?? start?.tool ?? "tool"
        return TranscriptCard(
            tool: tool, kind: ToolKind(tool: tool), arg: start?.arg ?? end?.arg ?? "", summary: end?.summary ?? "",
            status: end == nil ? .pending : end?.status == "err" ? .error : .ok, duration: end?.durationMs.map(formatCallDuration),
            output: end?.output ?? [], diff: cardDiff(end?.diff)
        )
    }
}

/// Events in, items out, in id order. An event seen twice counts once, a call whose end came first still has one card, and a call
/// with no end is pending. A `task` event and any kind this app does not know are left out.
public func transcriptItems(_ events: [ExecEvent]) -> [TranscriptItem] {
    var transcript = Transcript()
    transcript.apply(EventsReply(events: events, next: 0, running: true, structured: true))
    return transcript.items
}

/// What an open session shows: the merged items, or the summarised `tail` lines of a harness with no parser yet.
public enum TranscriptBody: Equatable {
    case items([TranscriptItem])
    case tail([String])
}

public func transcriptBody(_ transcript: Transcript?) -> TranscriptBody {
    guard let transcript else { return .items([]) }
    return transcript.structured ? .items(transcript.items) : .tail(transcript.tail)
}
