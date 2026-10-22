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

public enum CountTone: Equatable { case plain, added, removed, error }

/// A piece of the counts line and how the view paints it: lines added in green, removed in red, errors in red.
public struct CountRun: Equatable {
    public var text: String
    public var tone: CountTone
}

/// `8 tool calls · 2 edits +42 −8 · 1 test run · 2 errors` in pieces, every part but the tool calls left out at zero.
public func countsRuns(_ counts: SessionCounts) -> [CountRun] {
    func plural(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
    var runs = [CountRun(text: plural(counts.calls, "tool call"), tone: .plain)]
    if counts.edits > 0 {
        runs += [
            CountRun(text: " · \(plural(counts.edits, "edit")) ", tone: .plain), CountRun(text: "+\(counts.added)", tone: .added),
            CountRun(text: " ", tone: .plain), CountRun(text: "−\(counts.removed)", tone: .removed),
        ]
    }
    if counts.tests > 0 { runs.append(CountRun(text: " · \(plural(counts.tests, "test run"))", tone: .plain)) }
    if counts.errors > 0 {
        runs += [CountRun(text: " · ", tone: .plain), CountRun(text: plural(counts.errors, "error"), tone: .error)]
    }
    return runs
}

/// The same line as plain text.
public func countsLine(_ counts: SessionCounts) -> String { countsRuns(counts).map(\.text).joined() }

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
    /// The same line in pieces, for the colours; empty when `counts` is nil.
    public var countRuns: [CountRun] = []
    /// "since 16:09" while it runs, how long it took when it finished; nil for a stopped one, whose badge says it.
    public var timeLabel: String?
    /// Running and stopped open, finished folded; the newest one is open whatever it is.
    public var openByDefault: Bool
    /// What Continue in Terminal resumes; nil for a running session, whatever the engine sent (ADR 0007).
    public var resume: ResumeDescriptor?
    /// What the agent reported when it ended; nil when no result was imported.
    public var result: ResultCard?
    /// What shows under the header when it is open.
    public var body: TranscriptBody = .items([])
    /// The subagents of the session, each with its own activity; read-only, the resume above covers the whole session.
    public var lanes: [LaneSection] = []
}

// MARK: result

/// The closing card of a session: how it ended, the agent's own account and what it checked.
public struct ResultCard: Equatable {
    public enum Tone: Equatable { case good, warning, stop }

    /// "Completed", "Changes requested", "Needs a human".
    public var outcome: String
    public var tone: Tone
    public var summary: String
    /// "CI passed: <evidence>"; nil when the result has no verification.
    public var ci: String?
    /// Why the agent stopped; nil unless the outcome is needs_human.
    public var reason: String?
}

public func resultCard(_ result: SessionResult?) -> ResultCard? {
    guard let result else { return nil }
    let outcome: (String, ResultCard.Tone) = switch result.outcome {
    case "completed": ("Completed", .good)
    case "changes_requested": ("Changes requested", .warning)
    case "needs_human": ("Needs a human", .stop)
    default: (result.outcome.replacingOccurrences(of: "_", with: " ").capitalized, .warning) // a value added later still shows
    }
    return ResultCard(
        outcome: outcome.0, tone: outcome.1, summary: result.summary,
        ci: result.verification.map { "CI \($0.ci): \($0.evidence)" },
        reason: result.outcome == "needs_human" ? result.reason : nil
    )
}

/// The text with each web address in it as a link; only http and https survive `browserURL`.
public func linkedText(_ text: String) -> AttributedString {
    var linked = AttributedString(text)
    let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    for match in detector?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? [] {
        guard let url = match.url, let link = browserURL(url.absoluteString), let range = Range(match.range, in: text),
              let start = AttributedString.Index(range.lowerBound, within: linked), let end = AttributedString.Index(range.upperBound, within: linked)
        else { continue }
        linked[start..<end].link = link
    }
    return linked
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
            countRuns: transcript.flatMap { $0.structured ? countsRuns(sessionCounts($0.events)) : nil } ?? [],
            timeLabel: time,
            openByDefault: state != .done || index == 0,
            resume: state == .running ? nil : session.resume,
            result: resultCard(session.result),
            body: transcriptBody(transcript),
            lanes: transcript?.structured == true ? transcript?.laneSections ?? [] : []
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
