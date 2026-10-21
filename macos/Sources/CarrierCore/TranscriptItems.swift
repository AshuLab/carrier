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

/// Events in, items out, in id order. An event seen twice counts once, a call whose end came first still has one card, and a call
/// with no end is pending. A `task` event and any kind this app does not know are left out.
public func transcriptItems(_ events: [ExecEvent]) -> [TranscriptItem] {
    var seen = Set<Int>()
    var slots: [(id: Int, call: String?, item: TranscriptItem?)] = []
    var starts: [String: ExecEvent] = [:]
    var ends: [String: ExecEvent] = [:]
    var first: [String: Int] = [:]
    for event in events.sorted(by: { $0.id < $1.id }) where seen.insert(event.id).inserted {
        switch event.kind {
        case "say": slots.append((event.id, nil, .message(id: event.id, text: event.text ?? "")))
        case "note": slots.append((event.id, nil, .note(id: event.id, text: event.text ?? "")))
        case "error": slots.append((event.id, nil, .error(id: event.id, text: event.text ?? "")))
        case "tool_start", "tool_end":
            // an event with no callId is a call of its own
            let call = event.callId ?? "event \(event.id)"
            if first[call] == nil {
                first[call] = event.id
                slots.append((event.id, call, nil))
            }
            if event.kind == "tool_start" { starts[call] = event } else { ends[call] = event }
        default: break
        }
    }
    return slots.map { slot in
        if let item = slot.item { return item }
        let call = slot.call!
        let start = starts[call], end = ends[call]
        let tool = end?.tool ?? start?.tool ?? "tool"
        let status: ToolStatus = end == nil ? .pending : end?.status == "err" ? .error : .ok
        return .tool(id: slot.id, TranscriptCard(
            tool: tool, kind: ToolKind(tool: tool), arg: start?.arg ?? end?.arg ?? "", summary: end?.summary ?? "",
            status: status, duration: end?.durationMs.map(formatCallDuration)
        ))
    }
}

/// What an open session shows: the merged items, or the summarised `tail` lines of a harness with no parser yet.
public enum TranscriptBody: Equatable {
    case items([TranscriptItem])
    case tail([String])
}

public func transcriptBody(_ transcript: Transcript?) -> TranscriptBody {
    guard let transcript else { return .items([]) }
    return transcript.structured ? .items(transcriptItems(transcript.events)) : .tail(transcript.tail)
}
