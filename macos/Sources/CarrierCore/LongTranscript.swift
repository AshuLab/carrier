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

/// `rounds` turns of a conversation, seven events a turn: a message, a read, a command with output, the answer in markdown (a list and
/// a code block) and the turn's end with its usage; ids from 1. The fixture host answers `events` with it under `--fixture-long-transcript`.
public func longChatEvents(rounds: Int) -> [ChatEvent] {
    var events: [ChatEvent] = []
    var id = 0
    func add(_ kind: String, text: String? = nil, callId: String? = nil, tool: String? = nil, arg: String? = nil, output: [String]? = nil, status: String? = nil, usage: [String: Double]? = nil) {
        id += 1
        events.append(ChatEvent(id: id, at: 1_792_000_000_000 + id * 700, kind: kind, text: text, callId: callId, tool: tool, arg: arg, output: output, status: status, outcome: kind == "turn_end" ? "ok" : nil, model: kind == "turn_end" ? "claude-sonnet-5-5" : nil, usage: usage))
    }
    for round in 0..<rounds {
        add("user", text: "Round \(round + 1): look at module \(round) and tell me what to change.")
        add("tool_start", callId: "r\(round)a", tool: "Read", arg: "src/module\(round).ts")
        add("tool_end", callId: "r\(round)a", tool: "Read", output: ["export const ttl = 60", "export const alg = \"HS256\""], status: "ok")
        add("tool_start", callId: "r\(round)b", tool: "Bash", arg: "pnpm test module\(round)")
        add("tool_end", callId: "r\(round)b", tool: "Bash", output: ["Tests 2 failed"], status: "err")
        add("assistant", text: "Module \(round) has two problems:\n\n- the algorithm is `HS256`\n- the ttl is not read from the config\n\n```ts\nexport const alg = \"ES256\"\n```")
        add("turn_end", usage: ["input_tokens": 1200, "output_tokens": 300])
    }
    return events
}
