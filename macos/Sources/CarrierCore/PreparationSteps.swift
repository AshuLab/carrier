import Foundation

// The list of steps at the top of a conversation while the host prepares a session from its plan (docs/adr/0018): each step the host
// recorded as a `step` event, with where it stands and a line in words. The list ends when the agent answers.

/// A row of the list: one step, as the last of its events left it.
public struct StepRow: Equatable, Identifiable {
    public enum Status: String { case running, done, failed }

    public let step: String
    public let status: Status
    /// What the step is doing or did, in words.
    public let line: String
    /// Why a failed step failed, in the host's words.
    public let reason: String?
    /// While a clone runs: the last line of git's own progress.
    public let progress: String?

    public var id: String { step }
}

/// The rows the session's `step` events make, in the order the steps first appeared. Nothing once the session is not being prepared
/// (`preparation` is nil: the agent answered, or the host does not prepare sessions), so the list ends with the answer; a failed
/// preparation keeps its list, with the reason on the step that failed. `progress` goes on the step that is running.
public func preparationSteps(_ events: [ChatEvent], preparation: ChatSession.Preparation?, progress: String? = nil) -> [StepRow] {
    guard preparation != nil else { return [] }
    var order: [String] = []
    var latest: [String: (status: StepRow.Status, detail: String?)] = [:]
    for event in events where event.kind == "step" {
        guard let step = event.step, let status = event.status.flatMap(StepRow.Status.init(rawValue:)) else { continue }
        if latest[step] == nil { order.append(step) }
        latest[step] = (status, event.detail)
    }
    return order.compactMap { step in
        guard let now = latest[step] else { return nil }
        return StepRow(
            step: step, status: now.status, line: stepLine(step, now.status), reason: now.status == .failed ? now.detail : nil,
            progress: now.status == .running ? progress : nil
        )
    }
}

private func stepLine(_ step: String, _ status: StepRow.Status) -> String {
    let words: (running: String, done: String, failed: String) = switch step {
    case "clone": ("Cloning the repository…", "Cloned the repository", "Could not clone the repository")
    case "fetch": ("Updating the repository…", "Updated the repository", "Could not update the repository")
    case "project": ("Creating the project…", "Created the project", "Could not create the project")
    case "worktree": ("Making the worktree…", "Made the worktree", "Could not make the worktree")
    case "checkout": ("Checking out the branch…", "Checked out the branch", "Could not check out the branch")
    case "agent": ("Starting the agent…", "Started the agent", "Could not start the agent")
    case "message": ("Waiting for the agent to answer…", "The agent answered", "The agent did not answer")
    default: ("Working on \(step)…", "Finished \(step)", "Could not finish \(step)")
    }
    return switch status {
    case .running: words.running
    case .done: words.done
    case .failed: words.failed
    }
}
