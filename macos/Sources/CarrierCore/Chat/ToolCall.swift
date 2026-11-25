import Foundation

public enum CallStatus: Equatable {
    case running, ok, failed
    /// The turn ended before the call did: the person stopped it, or the provider failed.
    case stopped
}

/// How long a Shell or MCP call runs before the live line draws its timer in amber: the same for both and for nothing else.
public let slowCallMs = 30_000

/// The timers on the right of a live line.
public struct LiveTimer: Equatable {
    /// The one that is read first: the running call's own time, or the turn's while no call goes.
    public let primaryMs: Int
    /// The turn's time, drawn quieter beside the call's while it is longer; nil when the call's is the whole of it or no call goes.
    public let turnMs: Int?
    /// Whether the call has run past `slowCallMs`: its timer is amber.
    public let slow: Bool
}

/// A `tool_start` completed by its `tool_end`.
public struct ToolCall: Equatable, Identifiable {
    public let id: String
    public let tool: String
    public let kind: ToolKind
    /// What the call is on: the command, the path or the pattern.
    public let arg: String
    public internal(set) var status: CallStatus
    /// What the engine counted for a read or a search ("212 lines"), which is then the call's result; its own words, so not translated.
    public internal(set) var reported: String?
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
    }

    mutating func stop() { status = .stopped }

    /// The short result of the call's line: "212 lines", "4 matches", "+3 −1", "failed", "stopped"; nothing while it runs.
    public func result(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        switch status {
        case .running: ""
        case .stopped: Copy.chatResultStopped(bundle: bundle, locale: locale)
        case .failed: Copy.chatResultFailed(bundle: bundle, locale: locale)
        case .ok: reported ?? resultLine(bundle: bundle, locale: locale)
        }
    }

    public var durationMs: Int? { endedAt.map { $0 - startedAt } }

    /// How long the call has run at `now` (milliseconds since the epoch), counted from its start.
    public func elapsedMs(now: Int) -> Int { max(0, now - startedAt) }

    /// Whether the call is slow at `now`: a Shell or MCP call still going for more than `slowCallMs`; exactly that is not slow.
    /// Nothing else is ever slow, however long it runs.
    public func isSlow(now: Int) -> Bool {
        guard status == .running else { return false }
        switch kind {
        case .shell, .mcp: return elapsedMs(now: now) > slowCallMs
        case .read, .search, .edit, .other: return false
        }
    }

    /// What the call is named in a row: the tool, and for an MCP call the tool without its server (`create_issue`, not `mcp__linear__create_issue`).
    public var label: String {
        if case .mcp(_, let name) = kind { return name }
        return tool.isEmpty ? Copy.chatToolUnnamed() : tool
    }

    /// What the row says the call is on: its argument, and for an MCP call its server, never the JSON of its arguments (those open with the step).
    public var subject: String {
        if case .mcp(let server, _) = kind { return server }
        return arg
    }

    /// "Reading src/a.ts", for a call that is going on; an MCP call is its tool's name alone.
    func doing(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        if case .mcp(_, let name) = kind { return name }
        if arg.isEmpty {
            let name = tool.isEmpty ? Copy.chatToolUnnamed(bundle: bundle, locale: locale) : tool
            let verb: Copy.ChatDoing = switch kind {
            case .read: .read
            case .search: .search
            case .edit: .edit
            case .shell: .shell
            case .other, .mcp: .other
            }
            return Copy.chatDoing(kind: verb, tool: name, bundle: bundle, locale: locale)
        }
        let name = tool.isEmpty ? Copy.chatToolUnnamed(bundle: bundle, locale: locale) : tool
        let verb: Copy.ChatDoingOn = switch kind {
        case .read: .read
        case .search: .search
        case .edit: .edit
        case .shell: .shell
        case .other, .mcp: .other
        }
        return Copy.chatDoingOn(kind: verb, arg: arg, tool: name, bundle: bundle, locale: locale)
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

    private func resultLine(bundle: Bundle?, locale: Locale) -> String {
        let done = Copy.chatResultDone(bundle: bundle, locale: locale)
        let lines = output.filter { $0.allSatisfy(\.isWhitespace) == false }
        switch kind {
        case .read: return Copy.chatResultLines(count: output.count, bundle: bundle, locale: locale)
        case .search: return Copy.chatResultMatches(count: lines.count, bundle: bundle, locale: locale)
        case .edit: return added + removed > 0 ? "+\(added) −\(removed)" : done
        case .shell: return done
        case .other, .mcp: return lines.first.map { String($0.trimmingCharacters(in: .whitespaces).prefix(80)) } ?? done
        }
    }
}

/// What the live line of a call group says the agent is waiting on, as the chip at its start.
public enum KindChip: Equatable {
    case thinking, read, search, edit, shell
    case mcp(server: String)
    case subagents(Int)
    /// A subagent's own type (`Explore`), the chip of its row.
    case subagent(type: String)
    case needsYou

    /// The server's own name for an MCP call.
    public func label(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        switch self {
        case .thinking: Copy.chatChipThinking(bundle: bundle, locale: locale)
        case .read: Copy.chatChipRead(bundle: bundle, locale: locale)
        case .search: Copy.chatChipSearch(bundle: bundle, locale: locale)
        case .edit: Copy.chatChipEdit(bundle: bundle, locale: locale)
        case .shell: Copy.chatChipShell(bundle: bundle, locale: locale)
        case .mcp(let server): server
        case .subagents(let count): Copy.chatChipSubagents(count: count, bundle: bundle, locale: locale)
        case .subagent(let type): type
        case .needsYou: Copy.sessionStatusNeedsYou(bundle: bundle, locale: locale)
        }
    }

    public var tint: ChipTint {
        switch self {
        case .thinking: .thought
        case .read, .search, .edit: .files
        case .shell: .shell
        case .mcp: .mcp
        case .subagents, .subagent: .subagents
        case .needsYou: .attention
        }
    }

    /// The icon of the kind of call; Thinking has none, it is the spark of the line's lead.
    public var icon: AppIcon? {
        switch self {
        case .thinking, .needsYou: nil
        case .read: .fileText
        case .search: .search
        case .edit: .pencil
        case .shell: .terminal
        case .mcp: .plug
        case .subagents, .subagent: .users
        }
    }
}

/// The colour role of a chip; the view maps it to a colour.
public enum ChipTint: Equatable { case thought, files, shell, mcp, subagents, attention }
