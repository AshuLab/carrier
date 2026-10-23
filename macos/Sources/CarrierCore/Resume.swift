import Foundation

// Resuming a stopped epic from its view (docs/specs/resume-a-stopped-epic.md): the card the view draws, the request that asks the
// engine and the words of each way it can fail. The app has no GitHub token (ADR 0005): the engine puts the label back.

/// What the card between an epic's title and its tabs says. The view only draws it.
public struct ResumeCard: Equatable {
    /// The reason, capitalised: "Review limit reached".
    public var title: String
    /// One line of what resuming does for this kind.
    public var words: String
    /// Orange when a person's input is needed, red when something failed.
    public var attention: Attention
    /// What the confirmation sheet says will happen.
    public var sheet: [String]
    /// False for an engine that cannot be asked: the card still gives the reason and the words.
    public var showsButton: Bool
}

/// nil unless the epic is stopped in needs-human. `canResume`: the engine's hello lists `resumeEpic`.
public func resumeCard(_ epic: PanelEpic, canResume: Bool) -> ResumeCard? {
    guard epic.status == .needsHuman else { return nil }
    let line = interventionLine(epic)
    let attention = Attention(kind: epic.needsHumanKind)
    let words: String
    switch epic.needsHumanKind {
    case "review_limit": words = "Resuming gives the epic \(epic.maxReviews) new review rounds."
    case "agent_needs_human": words = "Do what the agent asked on the pull request first, then resume."
    case "retries_exhausted", "timeout", "auth", "workspace", "pr_invalid": words = "Fix the cause first, then resume to start the epic again from ship."
    default: words = "Deal with the cause first, then resume."
    }
    return ResumeCard(
        title: line.prefix(1).uppercased() + line.dropFirst(), words: words, attention: attention,
        sheet: [
            "solve:epic:ready goes back on the issue.",
            "The epic starts again from ship, reusing its worktree and its pull request.",
            "The review rounds start over.",
            "If the cause is not fixed, it stops here again.",
        ],
        showsButton: canResume
    )
}

/// The reasons the engine gives for refusing `resumeEpic`.
public enum ResumeRefusal: String, CaseIterable {
    case unknownEpic = "unknown epic"
    case notStopped = "not stopped"
    case githubUnavailable = "github unavailable"
    case didNotRestart = "did not restart"

    var words: String {
        switch self {
        case .unknownEpic: "Carrier does not know this epic."
        case .notStopped: "This epic is not stopped, so there is nothing to resume."
        case .githubUnavailable: "GitHub did not answer, so nothing was resumed. Try again."
        case .didNotRestart: "The label is back on the issue, but the epic did not start within thirty seconds. The next check will take it."
        }
    }
}

public enum ResumeResult: Equatable {
    /// The epic started again.
    case resumed
    /// The engine's reason.
    case refused(String)
    /// no socket to talk to, or the connection died
    case stopped
    /// an engine that does not list `resumeEpic`
    case unsupported
}

/// Asks the engine at `socketPath`. Blocks (the engine answers when the epic has started, up to thirty seconds): call it off the
/// main thread.
public func resumeEpic(socketPath: String, repo: String, issue: Int) -> ResumeResult {
    guard let client = ControlClient.connect(path: socketPath, timeout: 45) else { return .stopped }
    defer { client.close() }
    do {
        _ = try client.hello()
        return try client.resumeEpic(repo: repo, issue: issue) ? .resumed : .unsupported
    } catch ControlError.remote(let reason) {
        return .refused(reason)
    } catch {
        return .stopped
    }
}

/// What the card says when the epic was not resumed; nil when it was.
public func resumeFailureWords(_ result: ResumeResult) -> String? {
    switch result {
    case .resumed: nil
    case .refused(let reason): ResumeRefusal(rawValue: reason)?.words ?? "Carrier could not resume this epic (\(reason))."
    case .stopped: "Carrier is not running."
    case .unsupported: "This Carrier cannot resume epics. Update it."
    }
}
