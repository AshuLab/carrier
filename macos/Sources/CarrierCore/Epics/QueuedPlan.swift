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
public func queuedPlan(position: Int, agents: PanelSnapshot.Agents?, slots: PanelSnapshot.Slots?, bundle: Bundle? = nil, locale: Locale = .current) -> QueuedPlan {
    func row(_ number: Int, _ name: String, _ agent: PanelSnapshot.Agent?, _ line: String) -> PlanRow {
        PlanRow(number: number, name: name, agent: agent.map { agentName($0.harness) }, model: agent?.model, line: line)
    }
    let rows = [
        row(1, Copy.sessionPlaceShip(bundle: bundle, locale: locale), agents?.author, Copy.epicsPlanShip(bundle: bundle, locale: locale)),
        row(2, Copy.sessionPlaceReview(bundle: bundle, locale: locale), agents?.reviewer, Copy.epicsPlanReview(bundle: bundle, locale: locale)),
        row(3, Copy.sessionPlaceFix(bundle: bundle, locale: locale), agents?.author, Copy.epicsPlanFix(bundle: bundle, locale: locale)),
        row(4, Copy.epicsStepReady(bundle: bundle, locale: locale), nil, Copy.epicsPlanReady(bundle: bundle, locale: locale)),
    ]

    let ahead = max(position - 1, 0)
    let footer: String
    if let slots, slots.busy < slots.total {
        footer = Copy.epicsPlanSlotFree(busy: slots.busy, total: slots.total, ahead: ahead, bundle: bundle, locale: locale)
    } else if let slots {
        footer = Copy.epicsPlanSlotsBusy(total: slots.total, busy: slots.busy, ahead: ahead, bundle: bundle, locale: locale)
    } else {
        footer = Copy.epicsPlanSlotUnknown(bundle: bundle, locale: locale)
    }
    return QueuedPlan(rows: rows, footer: footer)
}

extension PanelSnapshot {
    /// The plan of a queued epic, from its repository's agents and the slots now.
    public func queuedPlan(for epic: QueuedEpic, position: Int, bundle: Bundle? = nil, locale: Locale = .current) -> QueuedPlan {
        CarrierCore.queuedPlan(position: position, agents: watched?.first { $0.repo == epic.repo }?.agents, slots: slots, bundle: bundle, locale: locale)
    }
}
