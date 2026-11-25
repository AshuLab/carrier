import Foundation

/// A short conversation made up for Settings to show how wide a message is: the person's message, a run of the agent's work and its answer, as the
/// feed has them, so the preview draws the real rows and not a stand-in.
public func sampleConversation(bundle: Bundle? = nil, locale: Locale = .current) -> [FeedRow] {
    var read = ToolCall(start: ChatEvent(id: 1, at: 1_000, kind: "tool_start", callId: "sample-read", tool: "Read", arg: "src/upload/retry.ts"))
    read.finish(ChatEvent(id: 2, at: 1_400, kind: "tool_end", callId: "sample-read", output: ["export async function upload(file: File) {"], status: "ok"))
    var run = ToolCall(start: ChatEvent(id: 3, at: 2_000, kind: "tool_start", callId: "sample-run", tool: "Bash", arg: "pnpm test"))
    run.finish(ChatEvent(id: 4, at: 5_200, kind: "tool_end", callId: "sample-run", output: ["Tests  12 passed"], status: "ok"))
    return [
        .user(id: "sample-user", text: Copy.fixtureSampleUserMessage(bundle: bundle, locale: locale)),
        .tools(id: "sample-tools", ToolGroup(calls: [read, run])),
        .agent(
            id: "sample-agent",
            text: Copy.fixtureSampleAgentMessage(bundle: bundle, locale: locale),
            inProgress: false
        ),
    ]
}
