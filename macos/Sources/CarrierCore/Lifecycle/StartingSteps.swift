import Foundation

// What the Agent output tab says while the ship stage of a running epic has no agent output yet: the steps before the first
// agent writes, each with what the engine already knows (the wait for a slot, the branch, the clock of the step), so the wait
// reads as progress and not as an empty page. A value the snapshot does not have is left out of the line, never guessed.

public struct StartStep: Equatable {
    public var title: String
    public var state: StepState
    /// What is known about the step; nil when nothing is.
    public var detail: String?
    /// The time at the right of the step: when it began, or how long it has been going; nil when there is none to show.
    public var clock: String?
}

/// Whether the epic is running its ship stage: until an agent has output, the tab shows `startingSteps`.
public func isStarting(_ epic: PanelEpic) -> Bool {
    epic.status == .running && (epic.stage == nil || epic.stage == .ship)
}

/// The workspace counts as ready once the engine reports a worktree. `now` is ms since epoch.
public func startingSteps(_ epic: PanelEpic, reply: EpicReply?, now: Int, time: TimeFormat = .stored(), bundle: Bundle? = nil, locale: Locale = .current) -> [StartStep] {
    let workspaceReady = reply?.worktrees.isEmpty == false
    let branch = (reply?.branch ?? epic.branch).flatMap { $0.isEmpty ? nil : $0 }
    var waited: String?
    if let queued = epic.queuedAt, let started = epic.startedAt, started >= queued { waited = Copy.lifecycleStepWaited(duration: formatDuration(started - queued), bundle: bundle, locale: locale) }
    let workspace = branch.map { workspaceReady ? Copy.lifecycleStepWorktree(branch: $0, bundle: bundle, locale: locale) : Copy.lifecycleStepBranch(branch: $0, bundle: bundle, locale: locale) }
    return [
        StartStep(title: Copy.lifecycleStepQueued(bundle: bundle, locale: locale), state: .done, detail: waited, clock: epic.startedAt.map { clockTime($0, time: time) }),
        StartStep(
            title: workspaceReady ? Copy.lifecycleStepWorkspaceReady(bundle: bundle, locale: locale) : Copy.lifecycleStepWorkspacePreparing(bundle: bundle, locale: locale), state: workspaceReady ? .done : .current, detail: workspace,
            clock: workspaceReady ? nil : epic.startedAt.map { formatDuration(now - $0) }
        ),
        StartStep(title: Copy.lifecycleStepFirstAgent(bundle: bundle, locale: locale), state: workspaceReady ? .current : .waiting, detail: Copy.lifecycleStepOutputHere(bundle: bundle, locale: locale), clock: nil),
    ]
}
