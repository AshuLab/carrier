import Foundation

// A transcript of thousands of events made up in code: the fixture server answers `events` with it under
// `--fixture-long-transcript`, the tests merge it, and `--smoke-window` times the merge.

/// `rounds` rounds of a message, a read, an edit with a diff, a passing command with output and a failing one with output:
/// nine events a round, ids from 1.
public func longTranscriptEvents(rounds: Int) -> [ExecEvent] {
    var events: [ExecEvent] = []
    var id = 0
    func add(_ kind: String, call: String? = nil, tool: String? = nil, arg: String? = nil, text: String? = nil, summary: String? = nil,
             status: String? = nil, output: [String]? = nil, diff: [ExecEvent.DiffLine]? = nil) {
        id += 1
        events.append(ExecEvent(id: id, at: id * 100, kind: kind, text: text, callId: call, tool: tool, arg: arg, summary: summary,
                                status: status, durationMs: kind == "tool_end" ? 80 + id % 900 : nil, output: output, diff: diff))
    }
    func call(_ n: Int, _ tool: String, _ arg: String, summary: String, status: String = "ok", output: [String]? = nil, diff: [ExecEvent.DiffLine]? = nil) {
        add("tool_start", call: "call-\(n)", tool: tool, arg: arg)
        add("tool_end", call: "call-\(n)", tool: tool, arg: arg, summary: summary, status: status, output: output, diff: diff)
    }
    for round in 0..<rounds {
        add("say", text: "Round \(round + 1): reading the module, then changing it.")
        call(round * 4, "Read", "src/module\(round).ts", summary: "212 lines")
        call(round * 4 + 1, "Edit", "src/module\(round).ts", summary: "Edited 1 place", diff: [
            .init(sign: " ", text: "const ttl = 60;"), .init(sign: "-", text: "const alg = \"HS256\";"), .init(sign: "+", text: "const alg = \"ES256\";"),
        ])
        call(round * 4 + 2, "Bash", "pnpm lint", summary: "ok", output: ["checked 212 files", "no problems"])
        call(round * 4 + 3, "Bash", "pnpm test", summary: "2 failed", status: "err", output: ["FAIL src/module\(round).test.ts", "Tests 2 failed"])
    }
    return events
}
