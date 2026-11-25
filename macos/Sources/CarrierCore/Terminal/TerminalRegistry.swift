import Foundation

/// Pure workspace registry managing owners, multi-tab state, split pane trees, pane moves, and focus transitions.
public struct TerminalRegistry: Equatable, Sendable {
    public internal(set) var tabsById: [UUID: TerminalTab] = [:]
    public internal(set) var orderByOwner: [TerminalOwner: [UUID]] = [:]
    public internal(set) var activeTabByOwner: [TerminalOwner: UUID] = [:]
    public internal(set) var terminalOrder: [UUID] = []

    public init() {}

    public var owners: [TerminalOwner] {
        orderByOwner.keys.sorted(by: ownerSortOrder)
    }

    public var allTabs: [TerminalTab] {
        orderByOwner.values.flatMap { $0.compactMap { tabsById[$0] } }
    }

    public var allPaneIds: [UUID] {
        allTabs.flatMap(\.orderedPaneIds)
    }

    public func tabs(for owner: TerminalOwner) -> [TerminalTab] {
        (orderByOwner[owner] ?? []).compactMap { tabsById[$0] }
    }

    public func standaloneTerminals() -> [StandaloneTerminalSummary] {
        terminalOrder.compactMap { standaloneTerminal(id: $0) }
    }

    public func standaloneTerminal(id: UUID) -> StandaloneTerminalSummary? {
        let tabs = tabs(for: .terminal(id))
        guard tabs.isEmpty == false, let activeTab = activeTab(for: .terminal(id)) ?? tabs.first else {
            return nil
        }
        return StandaloneTerminalSummary(id: id, tabs: tabs, activeTab: activeTab)
    }

    public func activeTabId(for owner: TerminalOwner) -> UUID? {
        activeTabByOwner[owner]
    }

    public func activeTab(for owner: TerminalOwner) -> TerminalTab? {
        activeTabByOwner[owner].flatMap { tabsById[$0] }
    }

    public func activePane(for owner: TerminalOwner) -> TerminalPane? {
        activeTab(for: owner)?.activePane
    }

    public func tab(id tabId: UUID) -> TerminalTab? {
        tabsById[tabId]
    }

    public func pane(id paneId: UUID) -> TerminalPane? {
        guard let location = location(ofPaneId: paneId) else { return nil }
        return tabsById[location.tabId]?.panes[paneId]
    }

    public func location(ofPaneId paneId: UUID) -> (owner: TerminalOwner, tabId: UUID)? {
        for (owner, tabIds) in orderByOwner {
            for tabId in tabIds {
                if let tab = tabsById[tabId], tab.panes[paneId] != nil {
                    return (owner, tabId)
                }
            }
        }
        return nil
    }

    public func allPaneIds(for owner: TerminalOwner) -> [UUID] {
        tabs(for: owner).flatMap(\.orderedPaneIds)
    }

    public var workspaces: [TerminalWorkspace] {
        orderByOwner.keys.sorted(by: ownerSortOrder).map { owner in
            TerminalWorkspace(
                owner: owner,
                tabs: tabs(for: owner),
                activeTabId: activeTabByOwner[owner]
            )
        }
    }

    // MARK: - Tab Lifecycle & Ordering

    @discardableResult
    public mutating func openTab(
        owner: TerminalOwner,
        spec: TerminalLaunchSpec,
        id: UUID = UUID(),
        paneId: UUID = UUID(),
        title: String? = nil,
        activate: Bool = true
    ) -> TerminalTab {
        let tab = TerminalTab(id: id, owner: owner, spec: spec, paneId: paneId, title: title)
        insertTab(tab, at: nil, activate: activate)
        return tab
    }

    public mutating func selectTab(id: UUID, for owner: TerminalOwner? = nil) {
        guard let tab = tabsById[id] else { return }
        if let owner, tab.owner != owner { return }
        activeTabByOwner[tab.owner] = id
    }

    public func adjacentTabId(offset: Int, for owner: TerminalOwner) -> UUID? {
        guard let order = orderByOwner[owner], order.count > 1 else { return nil }
        let currentIndex = activeTabByOwner[owner].flatMap { order.firstIndex(of: $0) } ?? 0
        let wrapped = ((currentIndex + offset) % order.count + order.count) % order.count
        return order[wrapped]
    }

    public func adjacentPaneId(offset: Int, inTab tabId: UUID) -> UUID? {
        guard let tab = tabsById[tabId] else { return nil }
        let ordered = tab.orderedPaneIds
        guard ordered.count > 1 else { return nil }
        let currentIndex = ordered.firstIndex(of: tab.activePaneId) ?? 0
        let wrapped = ((currentIndex + offset) % ordered.count + ordered.count) % ordered.count
        return ordered[wrapped]
    }

    public func canMoveTab(id: UUID, offset: Int) -> Bool {
        guard let tab = tabsById[id], let order = orderByOwner[tab.owner], let current = order.firstIndex(of: id) else {
            return false
        }
        let nextIndex = current + offset
        return nextIndex >= 0 && nextIndex < order.count && nextIndex != current
    }

    @discardableResult
    public mutating func moveTabRelative(id: UUID, offset: Int) -> Bool {
        guard let tab = tabsById[id], let order = orderByOwner[tab.owner], let current = order.firstIndex(of: id) else {
            return false
        }
        let nextIndex = current + offset
        guard nextIndex >= 0, nextIndex < order.count, nextIndex != current else { return false }
        return moveTab(id: id, toIndex: nextIndex)
    }

    @discardableResult
    public mutating func moveTab(id: UUID, toIndex requestedIndex: Int) -> Bool {
        guard let tab = tabsById[id], var order = orderByOwner[tab.owner], let current = order.firstIndex(of: id) else {
            return false
        }
        order.remove(at: current)
        let bounded = min(max(requestedIndex, 0), order.count)
        order.insert(id, at: bounded)
        orderByOwner[tab.owner] = order
        return true
    }

    @discardableResult
    public mutating func moveTab(
        id: UUID,
        toOwner destinationOwner: TerminalOwner,
        atIndex requestedIndex: Int? = nil,
        activate: Bool = true
    ) -> Bool {
        guard var tab = tabsById[id] else { return false }
        if tab.owner == destinationOwner {
            if let requestedIndex { return moveTab(id: id, toIndex: requestedIndex) }
            if activate { activeTabByOwner[destinationOwner] = id }
            return true
        }
        removeTabEntryOnly(id: id, from: tab.owner)
        tab.owner = destinationOwner
        insertTab(tab, at: requestedIndex, activate: activate)
        return true
    }

    @discardableResult
    public mutating func closeTab(id: UUID) -> TerminalTab? {
        guard let removed = tabsById[id] else { return nil }
        removeTabEntryOnly(id: id, from: removed.owner)
        return removed
    }

    @discardableResult
    public mutating func closeAll(for owner: TerminalOwner) -> [TerminalTab] {
        let removed = tabs(for: owner)
        for tab in removed {
            tabsById.removeValue(forKey: tab.id)
        }
        orderByOwner.removeValue(forKey: owner)
        activeTabByOwner.removeValue(forKey: owner)
        if case .terminal(let id) = owner {
            terminalOrder.removeAll { $0 == id }
        }
        return removed
    }
}
