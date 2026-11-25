import Foundation
import Observation

/// A row of the feed.
public enum FeedRow: Equatable, Identifiable {
    /// What the person wrote: a bubble on the right.
    case user(id: String, text: String)
    /// What the agent wrote, as markdown; `inProgress` is the text still being written, which is not stored yet.
    case agent(id: String, text: String, inProgress: Bool)
    /// The line that closes a turn: the model, how long it took and the usage the provider reported.
    case turnEnd(id: String, TurnSummary)
    /// A run of the agent's work, its reasoning and its calls: one row that opens to its steps.
    case tools(id: String, ToolGroup)
    /// An approval waiting for the person: a card with the provider's choices.
    case approval(id: String, ApprovalCard)
    /// An approval that was answered: one line, green when the choice allowed and red when it did not.
    case decided(id: String, text: String, allow: Bool)
    /// An approval that is not waiting any more and was not answered (its turn ended): one plain line.
    case line(id: String, text: String)
    /// The point where the session changed agent: who it was and who it is, drawn as a divider with both agents and a line of what carried over.
    case switched(id: String, ChatEvent.Switched)
    /// An error event: the provider's text, in the banner of a failed turn.
    case error(id: String, text: String)
    /// A turn the person stopped: the mark with Continue.
    case stopped(id: String)
    /// A `/clear` that went through: the agent starts again from an empty context. `freed` is the context the turn before it ended with, nil when
    /// no turn said it. It stands where the empty turn's line would be.
    case cleared(id: String, freed: Double?)
    /// The provider summarized the conversation to free context, on the person's `/compact` or by itself: a cut like the clear's, where the agent goes on from the summary.
    case compacted(id: String, Compaction)

    public var id: String {
        switch self {
        case .user(let id, _), .agent(let id, _, _), .turnEnd(let id, _), .tools(let id, _), .approval(let id, _), .decided(let id, _, _),
            .line(let id, _), .switched(let id, _), .error(let id, _), .stopped(let id), .cleared(let id, _), .compacted(let id, _): id
        }
    }
}

/// What the divider of a change of agent says under the two agents: what the new one has of the conversation and what it does not.
public func handoffDetail(to agent: String) -> String {
    "\(agent) goes on from a selection of the messages above and can read the rest. Reasoning and tool results did not carry over."
}

/// What the divider of a `/clear` says under the capsule: the messages stay to be read, and the agent no longer has them.
public func clearedDetail(agent: String) -> String {
    "The messages above stay here to read, but \(agent) no longer sees them: it starts again from an empty context."
}

/// `38.8k tokens freed`: what the capsule of a `/clear` says beside its title, nil when no turn before it said the context.
public func clearedFreedText(_ freed: Double?) -> String? {
    guard let freed, freed > 0 else { return nil }
    return "\(TurnSummary.tokens(freed)) tokens freed"
}

/// What a `compact` event says: when it ran, the context it left and what it cost; `error` is set when it failed and nothing else is.
public struct Compaction: Equatable {
    public let auto: Bool
    public let before: Double?
    public let after: Double?
    public let ms: Int?
    public let error: String?

    public init(auto: Bool = false, before: Double? = nil, after: Double? = nil, ms: Int? = nil, error: String? = nil) {
        self.auto = auto
        self.before = before
        self.after = after
        self.ms = ms
        self.error = error
    }

    init(_ event: ChatEvent) {
        self.init(auto: event.trigger == "auto", before: event.before, after: event.after, ms: event.ms, error: event.error)
    }

    /// The capsule's title.
    public var title: String { error == nil ? "Context compacted" : "Compaction failed" }

    /// `142.3k → 18.4k tokens` from the sizes the provider gave (`18.4k tokens left` when it gave only what is left), with `auto` before when the agent did it by itself; nil when there is nothing to say.
    public var sizes: String? {
        guard error == nil else { return nil }
        var parts: [String] = auto ? ["auto"] : []
        if let before, let after, before > 0 { parts.append("\(TurnSummary.tokens(before)) \u{2192} \(TurnSummary.tokens(after)) tokens") }
        else if let after, after > 0 { parts.append("\(TurnSummary.tokens(after)) tokens left") }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    /// `−87%`: how much of the context the summary freed; nil unless both sizes are known and it did free some.
    public var saved: String? {
        guard error == nil, let before, let after, before > 0, after < before else { return nil }
        return "\u{2212}\(Int(((before - after) / before * 100).rounded()))%"
    }

    /// Under the capsule: what happened to the agent's view of the conversation. A failure says the context is as it was and why.
    public func detail(agent: String) -> String {
        if let error { return "The context is unchanged. \(error)" }
        let took = ms.map { " Took \(formatDuration($0))." } ?? ""
        if auto { return "The context filled up, so \(agent) summarized the earlier conversation and went on. The messages above stay here to read.\(took)" }
        return "\(agent) summarized the earlier conversation to free space. The messages above stay here to read; from now on it works from the summary.\(took)"
    }
}

/// Whether a message of the person is the `/clear` command: the whole text, with no argument.
public func isClearCommand(_ text: String) -> Bool { text.trimmingCharacters(in: .whitespacesAndNewlines) == "/clear" }

/// The row of the mark or banner that offers a way out (Continue, Try again): the last stopped or failed turn, and only while the
/// person has not written since. Earlier ones are only a record.
public func openOutcome(_ rows: [FeedRow]) -> String? {
    for row in rows.reversed() {
        switch row {
        case .user: return nil
        case .error(let id, _), .stopped(let id): return id
        default: continue
        }
    }
    return nil
}

/// A banner over the feed or the box: what the provider said (or the host's reason), and the hint under it when there is one.
public struct FailureBanner: Equatable {
    public let title: String
    public let detail: String
    public let hint: String?

    /// Whether it warns instead of failing: a banner with a hint (the provider is not signed in) is a warning, drawn in orange; one without is a failure, drawn in red.
    public var warns: Bool { hint != nil }
}

/// A key like `claude` starts a sentence as `Claude`; a name that already has a capital in it (a label like `iOS`) is the person's own and stays.
private func capitalized(_ agent: String) -> String {
    if agent.isEmpty { return "The agent" }
    return agent.contains(where: \.isUppercase) ? agent : agent.prefix(1).uppercased() + agent.dropFirst()
}

/// The banner of a turn that failed: "<Agent> couldn't continue" and the error's text.
public func failedTurnBanner(agent: String, error: String) -> FailureBanner {
    FailureBanner(title: "\(capitalized(agent)) couldn't continue", detail: error, hint: nil)
}

/// The banner of a refusal from `open`, `resume` or `send`: the host's own sentence, and for a provider that is not signed in the
/// line that says where to sign in.
public func refusalBanner(agent: String, reason: Refusal) -> FailureBanner {
    if let hint = signInLine(refusal: reason) { return FailureBanner(title: "\(capitalized(agent)) isn't signed in", detail: reason.shown(), hint: hint) }
    return FailureBanner(title: "\(capitalized(agent)) couldn't continue", detail: reason.shown(), hint: nil)
}

/// Above the box of a session that is not live: sending to it resumes it.
public let closedSessionNotice = (
    title: "This session is asleep",
    detail: "Its agent is napping. Send a message and it wakes up right where it left off.",
    chosen: "Its agent is napping. What you chose applies as soon as a message wakes it up."
)

/// Above the box of an idle session whose folder was deleted (its project was moved to the Trash), and what a send to it is refused with.
public let folderGoneNotice = (
    title: "This session's folder was deleted",
    detail: "Its project was moved to the Trash. What it did stays here to read, but it cannot go on."
)
public let folderGoneRefusal = "Its folder was deleted, so it cannot go on"

/// The line under a refusal when the provider is not signed in (`agent.notLoggedIn`), nil for any other.
public func signInLine(refusal reason: Refusal) -> String? {
    reason.has("agent.notLoggedIn") ? "Sign in from a terminal; Carrier never asks for your password" : nil
}

/// An approval as the card draws it: the question, the tool and its argument, and the provider's choices in its own order.
public struct ApprovalCard: Equatable {
    public let approvalId: String
    public let question: String
    public let tool: String
    public let arg: String?
    public let choices: [ChatChoice]
    /// The questions of an `AskUserQuestion` approval; empty for any other, which is drawn as the generic card.
    public let questions: [ChatQuestion]

    public init(approvalId: String, question: String, tool: String, arg: String? = nil, choices: [ChatChoice], questions: [ChatQuestion] = []) {
        (self.approvalId, self.question, self.tool, self.arg, self.choices, self.questions) = (approvalId, question, tool, arg, choices, questions)
    }
}
