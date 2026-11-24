/// A short conversation made up for Settings to show how wide a message is: the person's message, a run of the agent's work and its answer, as the
/// feed has them, so the preview draws the real rows and not a stand-in.
public func sampleConversation() -> [FeedRow] {
    var read = ToolCall(start: ChatEvent(id: 1, at: 1_000, kind: "tool_start", callId: "sample-read", tool: "Read", arg: "src/upload/retry.ts"))
    read.finish(ChatEvent(id: 2, at: 1_400, kind: "tool_end", callId: "sample-read", output: ["export async function upload(file: File) {"], status: "ok"))
    var run = ToolCall(start: ChatEvent(id: 3, at: 2_000, kind: "tool_start", callId: "sample-run", tool: "Bash", arg: "pnpm test"))
    run.finish(ChatEvent(id: 4, at: 5_200, kind: "tool_end", callId: "sample-run", output: ["Tests  12 passed"], status: "ok"))
    return [
        .user(id: "sample-user", text: "Can you retry the upload when it fails, and say what you changed?"),
        .tools(id: "sample-tools", ToolGroup(calls: [read, run])),
        .agent(
            id: "sample-agent",
            text: "I added a retry to `upload` that tries three times with a short pause between them, and a test that fails twice before it passes. "
                + "The width of a message is how far a line runs before it wraps: a narrow column is easy on the eye, and a wide one fits more of a table or a long command, like `pnpm test && pnpm typecheck`.",
            inProgress: false
        ),
    ]
}
