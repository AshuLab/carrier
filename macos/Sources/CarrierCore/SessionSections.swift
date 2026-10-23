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

    public init(calls: Int = 0, edits: Int = 0, added: Int = 0, removed: Int = 0, tests: Int = 0, errors: Int = 0) {
        (self.calls, self.edits, self.added, self.removed, self.tests, self.errors) = (calls, edits, added, removed, tests, errors)
    }
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

/// `8 tool calls · 2 edits +42 −8 · 1 test run · 2 errors`, every part but the tool calls left out at zero.
public func countsLine(_ counts: SessionCounts) -> String {
    func plural(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
    var line = plural(counts.calls, "tool call")
    if counts.edits > 0 { line += " · \(plural(counts.edits, "edit")) +\(counts.added) −\(counts.removed)" }
    if counts.tests > 0 { line += " · \(plural(counts.tests, "test run"))" }
    if counts.errors > 0 { line += " · \(plural(counts.errors, "error"))" }
    return line
}

// MARK: sections

/// What the user folded or unfolded by hand; a section nobody touched follows its default.
public struct SessionFolds: Equatable {
    private var chosen: [String: Bool] = [:]
    /// The epics whose "Earlier sessions" row is open: the sessions past `visibleSessions` are drawn under it. The folds are
    /// shared by every epic of the window, so this is keyed by epic.
    private var earlierOpen: Set<EpicRef> = []

    public init() {}

    public func isEarlierOpen(_ epic: EpicRef) -> Bool { earlierOpen.contains(epic) }

    public mutating func toggleEarlier(_ epic: EpicRef) {
        if earlierOpen.insert(epic).inserted == false { earlierOpen.remove(epic) }
    }

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
    public var counts: SessionCounts?
    /// "since 16:09" while it runs, how long it took when it finished; nil for a stopped one, whose badge says it.
    public var timeLabel: String?
    /// Running and stopped open, finished folded; the newest one is open whatever it is.
    public var openByDefault: Bool
    /// What Continue in Terminal resumes; nil for a running session, whatever the engine sent (ADR 0007).
    public var resume: ResumeDescriptor?
    /// What the agent reported when it ended; nil when no result was imported.
    public var result: ResultCard?
    /// What shows under the header when it is open: the main rows and the subagents (read-only, the resume above covers the whole
    /// session) in the order the events happened.
    public var body: TranscriptBody = .items([])
}

// MARK: result

/// The closing card of a session: how it ended, the agent's own account and what it checked.
public struct ResultCard: Equatable {
    public struct CI: Equatable {
        /// "passed" or "absent" (no CI to check); a value added later still shows.
        public var verdict: String
        public var evidence: String
    }

    public enum Tone: Equatable { case good, warning, stop }

    /// "Completed", "Changes requested", "Needs a human".
    public var outcome: String
    public var tone: Tone
    public var summary: String
    /// What the agent says it checked; nil when the result has no verification.
    public var ci: CI?
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
        ci: result.verification.map { ResultCard.CI(verdict: $0.ci, evidence: $0.evidence) },
        reason: result.outcome == "needs_human" ? result.reason : nil
    )
}

/// The text with each web address in it as a link; only http and https survive `browserURL`.
public func linkedText(_ text: String) -> AttributedString { withWebLinks(AttributedString(text)) }

/// `text` with its web addresses as links, and any other link it already had (a Markdown one) taken away: the agent writes
/// this text, so only http and https may open.
private func withWebLinks(_ text: AttributedString) -> AttributedString {
    var linked = text
    for run in text.runs {
        if let link = run.link, browserURL(link.absoluteString) == nil { linked[run.range].link = nil }
    }
    let plain = String(text.characters)
    let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    for match in detector?.matches(in: plain, range: NSRange(plain.startIndex..., in: plain)) ?? [] {
        guard let url = match.url, let link = browserURL(url.absoluteString), let range = Range(match.range, in: plain),
              let start = AttributedString.Index(range.lowerBound, within: linked), let end = AttributedString.Index(range.upperBound, within: linked)
        else { continue }
        linked[start..<end].link = link
    }
    return linked
}

/// A line of an agent's message as the view lays it out.
public enum MarkdownBlock: Equatable {
    case line(AttributedString)
    /// A `- ` list item; `level` is how many steps of two spaces it is indented.
    case bullet(level: Int, AttributedString)
    /// A blank line, once however many there were.
    case gap
}

/// An agent's message as Markdown, a block per line: bold, italics, code and links inside the line, `- ` lists as bullets and
/// `#` headings as bold lines, which the inline parser leaves alone. ponytail: no code fences, tables or numbered lists, the fence
/// lines are dropped and what is inside shows as lines of text; a block parser if agents start writing them a lot.
public func markdownBlocks(_ text: String) -> [MarkdownBlock] {
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    func inline(_ line: String) -> AttributedString {
        withWebLinks((try? AttributedString(markdown: line, options: options)) ?? AttributedString(line))
    }
    var blocks: [MarkdownBlock] = []
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let trimmed = line.drop { $0 == " " }
        let indent = line.count - trimmed.count
        if trimmed.hasPrefix("```") { continue }
        if trimmed.allSatisfy(\.isWhitespace) {
            if blocks.isEmpty == false, blocks.last != .gap { blocks.append(.gap) }
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            blocks.append(.bullet(level: indent / 2, inline(String(trimmed.dropFirst(2)))))
        } else if trimmed.hasPrefix("#"), case let title = trimmed.drop(while: { $0 == "#" }).drop(while: { $0 == " " }), title.isEmpty == false {
            blocks.append(.line(inline("**\(title)**")))
        } else {
            blocks.append(.line(inline(String(line))))
        }
    }
    if blocks.last == .gap { blocks.removeLast() }
    return blocks
}

public struct SessionList: Equatable {
    /// The newest `visibleSessions`.
    public var sections: [SessionSection]
    /// The rest, newest first, never open by default; empty with `visibleSessions` or fewer.
    public var earlier: [SessionSection]
}

/// How many sessions the list shows; the rest are behind the "Earlier sessions" row.
public let visibleSessions = 5

/// Anything but running and finished is a session that stopped before it was done (failed, timed_out, interrupted, invalid_result).
func sessionState(_ status: String) -> SessionSection.State {
    switch status {
    case "running": .running
    case "finished": .done
    default: .stopped
    }
}

/// Newest first, as the reply is. `transcripts` holds the events fetched so far, by execution id.
/// `resumable` is false for an epic that ended: its sessions are over and Continue in Terminal is not offered.
public func sessionList(
    _ reply: SessionsReply?, transcripts: [String: Transcript] = [:], slices: [EpicReply.Slice] = [],
    now: Int = Int(Date().timeIntervalSince1970 * 1000), timeZone: TimeZone = .current, resumable: Bool = true
) -> SessionList {
    let all = reply?.sessions ?? []
    let built = all.enumerated().map { index, session -> SessionSection in
        let state = sessionState(session.status)
        let transcript = transcripts[session.executionId]
        let time: String?
        switch state {
        case .running:
            time = "since " + clock(session.startedAt, timeZone: timeZone)
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
            counts: transcript.flatMap { $0.structured ? sessionCounts($0.events) : nil },
            timeLabel: time,
            openByDefault: index < visibleSessions && (state != .done || index == 0),
            resume: state == .running || resumable == false ? nil : session.resume,
            result: resultCard(session.result),
            body: transcriptBody(transcript, slices: slices, running: state == .running, now: now, timeZone: timeZone)
        )
    }
    return SessionList(sections: Array(built.prefix(visibleSessions)), earlier: Array(built.dropFirst(visibleSessions)))
}

/// What the poller should ask for to fill this list: the events of the open running session (live) and, once, those of the
/// finished ones shown (for their counts), and those of the older ones while their row is open.
public func epicFocus(_ epic: EpicRef, running: Bool, data: EpicData?, folds: SessionFolds) -> EpicFocus {
    let list = sessionList(data?.sessions)
    return EpicFocus(
        epic: epic,
        epicRunning: running,
        // always: the tab's count shows before the tab is opened, and the view keeps which tab is open to itself
        filesTabVisible: true,
        transcript: list.sections.first { $0.state == .running && folds.isOpen($0) }?.id,
        counting: list.sections.filter { $0.state != .running }.map(\.id) + (folds.isEarlierOpen(epic) ? list.earlier.map(\.id) : [])
    )
}
