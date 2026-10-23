// What the Agent output tab says while the ship stage of a running epic has no agent output yet: the steps before the first
// agent writes, so the wait reads as progress and not as an empty page.

public struct StartStep: Equatable {
    public var title: String
    public var state: StepState
}

/// nil unless the epic is running its ship stage; the workspace counts as ready once the engine reports a worktree.
public func startingSteps(_ subject: EpicSubject, reply: EpicReply?) -> [StartStep]? {
    guard case .active(let epic) = subject, epic.status == .running, epic.stage == nil || epic.stage == .ship else { return nil }
    let workspaceReady = reply?.worktrees.isEmpty == false
    return [
        StartStep(title: "Epic queued", state: .done),
        StartStep(title: workspaceReady ? "Workspace ready" : "Preparing the workspace", state: workspaceReady ? .done : .current),
        StartStep(title: "First agent starts, its output appears here", state: workspaceReady ? .current : .waiting),
    ]
}
