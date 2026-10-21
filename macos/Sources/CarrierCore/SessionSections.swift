import Foundation

// The Agent output tab's list: one section per agent session of an epic, newest first, built from the `sessions` reply and the
// events fetched so far (docs/specs/macos-app-redesign.md, story 19). The views map it one to one.

// MARK: counts

public struct SessionCounts: Equatable {
    public var calls = 0
    public var edits = 0
    public var added = 0
    public var removed = 0
    public var tests = 0
    public var errors = 0
}

private let editTools: Set<String> = ["Edit", "MultiEdit", "Write", "NotebookEdit"]
private let shellTools: Set<String> = ["Bash", "shell", "exec_command"]
private let testWords: Set<String> = ["test", "tests", "--test", "vitest", "jest", "pytest", "mocha", "rspec", "phpunit"]

/// Whether a shell command runs tests: one of its words is a test runner or `test` (`pnpm test`, `swift test`, `pnpm test:unit`).
/// ponytail: a word match, so `git commit -m test` counts; a real shell parse if the number ever matters.
func runsTests(_ command: String) -> Bool {
    command.split(whereSeparator: { " \t\n;&|()".contains($0) }).contains { testWords.contains(String($0)) || $0.hasPrefix("test:") }
}

/// What a session did, from its events. A tool call is a `tool_start` and a `tool_end` joined by `callId`; an event with no
/// `callId` is one call of its own. An error is an `error` event or a call that ended with status `err`.
public func sessionCounts(_ events: [ExecEvent]) -> SessionCounts {
    var counts = SessionCounts()
    var calls: [String: (tool: String?, arg: String?)] = [:]
    for event in events {
        switch event.kind {
        case "error":
            counts.errors += 1
        case "tool_start", "tool_end":
            let key = event.callId ?? "event \(event.id)"
            var call = calls[key] ?? (nil, nil)
            call.tool = event.tool ?? call.tool
            call.arg = event.arg ?? call.arg
            calls[key] = call
            if event.kind == "tool_end" {
                if event.status == "err" { counts.errors += 1 }
                for line in event.diff ?? [] {
                    if line.sign == "+" { counts.added += 1 } else if line.sign == "-" { counts.removed += 1 }
                }
            }
        default:
            break
        }
    }
    counts.calls = calls.count
    for call in calls.values {
        if let tool = call.tool, editTools.contains(tool) { counts.edits += 1 }
        if let tool = call.tool, shellTools.contains(tool), let arg = call.arg, runsTests(arg) { counts.tests += 1 }
    }
    return counts
}

/// `8 tool calls · 2 edits +42 −8 · 1 test run · 2 errors`: plain text, every part but the tool calls left out at zero.
public func countsLine(_ counts: SessionCounts) -> String {
    func plural(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
    var parts = [plural(counts.calls, "tool call")]
    if counts.edits > 0 { parts.append("\(plural(counts.edits, "edit")) +\(counts.added) −\(counts.removed)") }
    if counts.tests > 0 { parts.append(plural(counts.tests, "test run")) }
    if counts.errors > 0 { parts.append(plural(counts.errors, "error")) }
    return parts.joined(separator: " · ")
}

// MARK: sections

/// What the user folded or unfolded by hand; a section nobody touched follows its default.
public struct SessionFolds: Equatable {
    private var chosen: [String: Bool] = [:]

    public init() {}

    public func isOpen(_ section: SessionSection) -> Bool { chosen[section.id] ?? section.openByDefault }

    public mutating func toggle(_ section: SessionSection) { chosen[section.id] = !isOpen(section) }
}

public struct SessionSection: Equatable, Identifiable {
    public enum State: Equatable { case running, stopped, done }

    public var id: String
    public var state: State
    /// "Claude", "Codex".
    public var agent: String
    /// The avatar's letter (the mockup's: C for Claude, X for Codex).
    public var initial: String
    /// "Builder" (ship), "Reviewer", "Fixer".
    public var role: String
    /// "Ship", "Round 2".
    public var place: String
    /// nil when no events are known (the harness has no parser yet, or none has arrived): the header then has no counts.
    public var counts: String?
    /// "since 16:09" while it runs, how long it took when it finished; nil for a stopped one, whose badge says it.
    public var timeLabel: String?
    /// Running and stopped open, finished folded; the newest one is open whatever it is.
    public var openByDefault: Bool
    /// What shows under the header when it is open.
    public var body: TranscriptBody = .items([])
}

public struct SessionList: Equatable {
    public var sections: [SessionSection]
    /// "5 earlier sessions"; nil when there are none.
    public var earlier: String?
}

/// How many sessions the list shows; the rest are counted in the line under it.
public let visibleSessions = 3

/// Anything but running and finished is a session that stopped before it was done (failed, timed_out, interrupted, invalid_result).
func sessionState(_ status: String) -> SessionSection.State {
    switch status {
    case "running": .running
    case "finished": .done
    default: .stopped
    }
}

private func agentName(_ harness: String) -> String {
    switch harness {
    case "claude": "Claude"
    case "codex": "Codex"
    case "agy": "Antigravity"
    default: harness.prefix(1).uppercased() + harness.dropFirst()
    }
}

/// Newest first, as the reply is. `transcripts` holds the events fetched so far, by execution id.
public func sessionList(_ reply: SessionsReply?, transcripts: [String: Transcript] = [:], timeZone: TimeZone = .current) -> SessionList {
    let all = reply?.sessions ?? []
    let shown = all.prefix(visibleSessions)
    let sections = shown.enumerated().map { index, session -> SessionSection in
        let state = sessionState(session.status)
        let transcript = transcripts[session.executionId]
        let time: String?
        switch state {
        case .running:
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            formatter.timeZone = timeZone
            time = "since " + formatter.string(from: Date(timeIntervalSince1970: Double(session.startedAt) / 1000))
        case .done: time = session.finishedAt.map { formatDuration($0 - session.startedAt) }
        case .stopped: time = nil
        }
        let agent = agentName(session.agent.harness)
        return SessionSection(
            id: session.executionId,
            state: state,
            agent: agent,
            initial: session.agent.harness == "codex" ? "X" : agent.prefix(1).uppercased(),
            role: ["ship": "Builder", "review": "Reviewer", "fix": "Fixer"][session.stage] ?? session.stage.capitalized,
            place: session.round.map { "Round \($0)" } ?? session.stage.capitalized,
            counts: transcript.flatMap { $0.structured ? countsLine(sessionCounts($0.events)) : nil },
            timeLabel: time,
            openByDefault: state != .done || index == 0,
            body: transcriptBody(transcript)
        )
    }
    let rest = all.count - shown.count
    return SessionList(sections: sections, earlier: rest > 0 ? "\(rest) earlier \(rest == 1 ? "session" : "sessions")" : nil)
}

/// What the poller should ask for to fill this list: the events of the open running session (live) and, once, those of the
/// finished ones shown (for their counts).
public func epicFocus(_ epic: EpicRef, running: Bool, data: EpicData?, folds: SessionFolds) -> EpicFocus {
    let list = sessionList(data?.sessions)
    return EpicFocus(
        epic: epic,
        epicRunning: running,
        transcript: list.sections.first { $0.state == .running && folds.isOpen($0) }?.id,
        counting: list.sections.filter { $0.state != .running }.map(\.id)
    )
}
