import Foundation

// What a queued epic will do once it starts, as plain values: four stages, the agent and model of each and a footer about the
// slots (docs/specs/macos-app-redesign.md, story 25). The view maps them one to one.

public struct PlanRow: Equatable {
    /// 1 to 4.
    public var number: Int
    public var name: String
    /// "Claude"; nil for a stage with no agent, or while the repository's agents are not known.
    public var agent: String?
    public var model: String?
    public var line: String
}

public struct QueuedPlan: Equatable {
    public var rows: [PlanRow]
    public var footer: String
}

/// `agents` are the repository's configured ones (`watched` in the snapshot); without them the rows show no agent. `slots` and
/// `position` (from 1) decide the footer.
public func queuedPlan(position: Int, agents: PanelSnapshot.Agents?, slots: PanelSnapshot.Slots?) -> QueuedPlan {
    func row(_ number: Int, _ name: String, _ agent: PanelSnapshot.Agent?, _ line: String) -> PlanRow {
        PlanRow(number: number, name: name, agent: agent.map { agentName($0.harness) }, model: agent?.model, line: line)
    }
    let rows = [
        row(1, "Ship", agents?.author, "Builds each slice in its own lane and merges it into the epic branch."),
        row(2, "Review", agents?.reviewer, "Reads the PR and lists the blockers it will not approve with."),
        row(3, "Fix", agents?.author, "Fixes the blockers; review and fix repeat until the reviewer approves."),
        row(4, "Ready", nil, "You try it and merge it. Carrier never merges to main."),
    ]

    let ahead = position - 1
    let footer: String
    if let slots, slots.busy < slots.total {
        let first = ahead <= 0 ? "It starts on its own at the next check." : "It starts on its own after the \(ahead) \(ahead == 1 ? "epic" : "epics") ahead of it."
        footer = "A slot is free (\(slots.busy) of \(slots.total) busy). \(first)"
    } else if let slots {
        let behind = ahead <= 0 ? "" : " \(ahead) \(ahead == 1 ? "epic goes" : "epics go") first."
        footer = "It starts on its own when one of the \(slots.total) slots is free. \(slots.busy) \(slots.busy == 1 ? "is" : "are") busy now.\(behind)"
    } else {
        footer = "It starts on its own when a slot is free."
    }
    return QueuedPlan(rows: rows, footer: footer)
}

extension PanelSnapshot {
    /// The plan of a queued epic, from its repository's agents and the slots now.
    public func queuedPlan(for epic: QueuedEpic, position: Int) -> QueuedPlan {
        CarrierCore.queuedPlan(position: position, agents: watched?.first { $0.repo == epic.repo }?.agents, slots: slots)
    }
}
