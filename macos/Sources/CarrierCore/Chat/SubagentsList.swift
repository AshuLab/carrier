import Foundation

/// What the Subagents button in a session's header shows, as a pure value of the session's subagents.
public enum SubagentsButtonState: Equatable, Sendable {
    /// The session launched no subagent, or was stored before the host linked subagents to their calls.
    case hidden
    /// At least one subagent runs: the count of every subagent in the launches that still have one running, nested ones included.
    case running(count: Int)
    /// Nothing runs: every subagent of the session, and `failed` if any of them failed.
    case quiet(total: Int, failed: Bool)
}

/// One subagent in a launch, with the subagents it launched nested under it in display order.
public struct SubagentItem: Equatable, Identifiable {
    public let subagent: Subagent
    public let children: [SubagentItem]

    public init(subagent: Subagent, children: [SubagentItem] = []) {
        self.subagent = subagent
        self.children = children
    }

    public var id: String { subagent.id }

    /// Every subagent in this subtree, including this one.
    public var totalCount: Int { 1 + children.reduce(0) { $0 + $1.totalCount } }

    /// How many subagents in this subtree are running now.
    public var runningCount: Int { (subagent.status == .running ? 1 : 0) + children.reduce(0) { $0 + $1.runningCount } }

    /// How many subagents in this subtree failed.
    public var failedCount: Int { (subagent.status == .failed ? 1 : 0) + children.reduce(0) { $0 + $1.failedCount } }

    var earliestStart: Int {
        children.reduce(subagent.startedAt) { min($0, $1.earliestStart) }
    }

    var latestEnd: Int {
        let own = subagent.endedAt ?? subagent.startedAt
        return children.reduce(own) { max($0, $1.latestEnd) }
    }
}

/// The subagents of one run of the agent's calls, with nested subagents under their launcher.
public struct SubagentLaunch: Equatable, Identifiable {
    public let id: String
    /// Top-level subagents of this run, ordered running, failed, finished, with start order kept inside each group.
    public let items: [SubagentItem]
    /// Earliest start among all subagents in this launch, in milliseconds since the epoch.
    public let startedAt: Int
    /// Latest end among all subagents in this launch when all have ended, in milliseconds since the epoch; nil while any runs.
    public let endedAt: Int?

    public init(id: String, items: [SubagentItem], startedAt: Int, endedAt: Int?) {
        self.id = id
        self.items = items
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    public var totalCount: Int { items.reduce(0) { $0 + $1.totalCount } }
    public var runningCount: Int { items.reduce(0) { $0 + $1.runningCount } }
    public var failedCount: Int { items.reduce(0) { $0 + $1.failedCount } }
    public var isRunning: Bool { runningCount > 0 }
}

/// Every launch of a session, running launches first and finished launches after, and the button state derived from them.
public struct SubagentsList: Equatable {
    public static let empty = SubagentsList(launches: [])

    public let launches: [SubagentLaunch]

    public init(launches: [SubagentLaunch]) {
        self.launches = launches
    }

    public var totalCount: Int { launches.reduce(0) { $0 + $1.totalCount } }
    public var runningCount: Int { launches.reduce(0) { $0 + $1.runningCount } }
    public var failedCount: Int { launches.reduce(0) { $0 + $1.failedCount } }

    /// The header button's state: hidden until the first subagent starts, running while any launch runs, quiet when all ended.
    public var buttonState: SubagentsButtonState {
        if launches.isEmpty { return .hidden }
        let active = launches.filter(\.isRunning)
        if active.isEmpty == false {
            return .running(count: active.reduce(0) { $0 + $1.totalCount })
        }
        return .quiet(total: totalCount, failed: failedCount > 0)
    }

    /// What VoiceOver and the tooltip say for the Subagents button.
    public func buttonSpoken(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        switch buttonState {
        case .hidden:
            ""
        case .running(let count):
            Copy.chatSubagentsButtonRunningSpoken(count: count, running: runningCount, bundle: bundle, locale: locale)
        case .quiet(let total, let failed):
            failed
                ? Copy.chatSubagentsButtonFailedSpoken(count: total, failed: failedCount, bundle: bundle, locale: locale)
                : Copy.chatSubagentsButtonSpoken(count: total, bundle: bundle, locale: locale)
        }
    }
}

/// The order inside a launch: running first, then failed, then finished, keeping start order within each group.
private func displayRank(_ status: SubagentStatus) -> Int {
    switch status {
    case .running: 0
    case .failed: 1
    case .completed, .stopped: 2
    }
}

/// Builds the session's launches from its events: each `ToolGroup` of `chatFeed` that launched at least one subagent is one launch,
/// with nested subagents joined to their launcher by `parentCallId` and ordered running, failed, finished at each level.
public func subagentsList(in events: [ChatEvent], working: Bool = true, bundle: Bundle? = nil, locale: Locale = .current) -> SubagentsList {
    let rows = chatFeed(events, working: working, bundle: bundle, locale: locale)

    // Nested subagents (`parentCallId != nil`) are not placed in `ToolGroup.subagents` by `chatFeed`, so collect them here.
    var nested: [String: (parent: String, subagent: Subagent, order: Int)] = [:]
    var nextOrder = 0
    for event in events {
        if event.kind == "task" {
            let call = event.callId ?? "e\(event.id)"
            if let parent = event.parentCallId {
                if nested[call] != nil {
                    nested[call]?.subagent.apply(task: event)
                } else {
                    nested[call] = (parent, Subagent(task: event, bundle: bundle, locale: locale), nextOrder)
                    nextOrder += 1
                }
            } else if nested[call] != nil {
                nested[call]?.subagent.apply(task: event)
            }
        } else if let parent = event.parentCallId, nested[parent] != nil {
            nested[parent]?.subagent.apply(inside: event)
        }
    }
    if working == false, let last = events.last?.at {
        for call in nested.keys where nested[call]?.subagent.status == .running {
            nested[call]?.subagent.stop(at: last)
        }
    }

    var childrenByParent: [String: [(order: Int, subagent: Subagent)]] = [:]
    for entry in nested.values {
        childrenByParent[entry.parent, default: []].append((entry.order, entry.subagent))
    }

    func makeItem(_ subagent: Subagent, visited: inout Set<String>) -> SubagentItem {
        guard visited.insert(subagent.id).inserted else { return SubagentItem(subagent: subagent) }
        let ordered = (childrenByParent[subagent.id] ?? []).sorted {
            let r0 = displayRank($0.subagent.status)
            let r1 = displayRank($1.subagent.status)
            return r0 != r1 ? r0 < r1 : $0.order < $1.order
        }
        return SubagentItem(subagent: subagent, children: ordered.map { makeItem($0.subagent, visited: &visited) })
    }

    var launches: [SubagentLaunch] = []
    var visited: Set<String> = []
    for row in rows {
        guard case .tools(let id, let group) = row, group.subagents.isEmpty == false else { continue }
        let ordered = group.subagents.enumerated().sorted {
            let r0 = displayRank($0.element.status)
            let r1 = displayRank($1.element.status)
            return r0 != r1 ? r0 < r1 : $0.offset < $1.offset
        }
        let items = ordered.map { makeItem($0.element, visited: &visited) }
        let startedAt = items.map(\.earliestStart).min() ?? 0
        let running = items.contains { $0.runningCount > 0 }
        let endedAt = running ? nil : items.map(\.latestEnd).max()
        launches.append(SubagentLaunch(id: id, items: items, startedAt: startedAt, endedAt: endedAt))
    }

    let running = launches.filter(\.isRunning)
    let finished = launches.filter { $0.isRunning == false }.enumerated().sorted {
        let e0 = $0.element.endedAt ?? $0.element.startedAt
        let e1 = $1.element.endedAt ?? $1.element.startedAt
        return e0 != e1 ? e0 > e1 : $0.offset > $1.offset
    }.map(\.element)
    return SubagentsList(launches: running + finished)
}
