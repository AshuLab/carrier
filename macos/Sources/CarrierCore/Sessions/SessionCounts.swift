import Foundation

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
