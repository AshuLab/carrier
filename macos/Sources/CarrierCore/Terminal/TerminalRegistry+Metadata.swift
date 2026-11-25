import Foundation

extension TerminalRegistry {
    // MARK: - Pane Metadata

    public mutating func updatePaneTitle(_ title: String, forPane paneId: UUID) {
        guard let loc = location(ofPaneId: paneId), var tab = tabsById[loc.tabId], var pane = tab.panes[paneId] else {
            return
        }
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        pane.title = cleaned.isEmpty ? "Terminal" : cleaned
        tab.panes[paneId] = pane
        tabsById[tab.id] = tab
    }

    public mutating func renamePane(_ paneId: UUID, customTitle: String?) {
        guard let loc = location(ofPaneId: paneId), var tab = tabsById[loc.tabId], var pane = tab.panes[paneId] else {
            return
        }
        pane.customTitle = TerminalPane.cleanCustomTitle(customTitle)
        tab.panes[paneId] = pane
        tabsById[tab.id] = tab
    }

    public mutating func renameTab(id tabId: UUID, customTitle: String?) {
        guard var tab = tabsById[tabId] else { return }
        tab.customTitle = TerminalPane.cleanCustomTitle(customTitle)
        tabsById[tabId] = tab
    }

    public mutating func updatePaneWorkingDirectory(_ workingDirectory: String, forPane paneId: UUID) {
        let trimmed = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false,
              let loc = location(ofPaneId: paneId),
              var tab = tabsById[loc.tabId],
              var pane = tab.panes[paneId]
        else {
            return
        }
        pane.workingDirectory = trimmed
        tab.panes[paneId] = pane
        tabsById[tab.id] = tab
    }

    @discardableResult
    public mutating func pruneSessions(keeping knownSessionIds: Set<String>) -> [UUID] {
        var removedPaneIds: [UUID] = []
        for owner in owners {
            guard case .session(let sessionId) = owner, knownSessionIds.contains(sessionId) == false else {
                continue
            }
            for tab in closeAll(for: owner) {
                removedPaneIds.append(contentsOf: tab.orderedPaneIds)
            }
        }
        return removedPaneIds
    }

    // MARK: - Internal Helpers

    mutating func replaceContents(with cleanWorkspaces: [TerminalWorkspace]) {
        tabsById = [:]
        orderByOwner = [:]
        activeTabByOwner = [:]
        terminalOrder = []
        for workspace in cleanWorkspaces where workspace.tabs.isEmpty == false {
            var order = orderByOwner[workspace.owner] ?? []
            for var tab in workspace.tabs {
                tab.owner = workspace.owner
                tab.normalize()
                guard tab.panes.isEmpty == false, tabsById[tab.id] == nil else { continue }
                tabsById[tab.id] = tab
                order.append(tab.id)
            }
            guard order.isEmpty == false else { continue }
            orderByOwner[workspace.owner] = order
            if case .terminal(let id) = workspace.owner, terminalOrder.contains(id) == false {
                terminalOrder.append(id)
            }
            if let preferredActive = workspace.activeTabId, order.contains(preferredActive) {
                activeTabByOwner[workspace.owner] = preferredActive
            } else if activeTabByOwner[workspace.owner] == nil {
                activeTabByOwner[workspace.owner] = order.first
            }
        }
    }

    mutating func insertTab(_ tab: TerminalTab, at requestedIndex: Int?, activate: Bool) {
        var cleanTab = tab
        cleanTab.normalize()
        tabsById[cleanTab.id] = cleanTab
        if case .terminal(let id) = cleanTab.owner, terminalOrder.contains(id) == false {
            terminalOrder.append(id)
        }
        var order = orderByOwner[cleanTab.owner] ?? []
        if let requestedIndex {
            let bounded = min(max(requestedIndex, 0), order.count)
            order.insert(cleanTab.id, at: bounded)
        } else {
            order.append(cleanTab.id)
        }
        orderByOwner[cleanTab.owner] = order
        if activate || activeTabByOwner[cleanTab.owner] == nil {
            activeTabByOwner[cleanTab.owner] = cleanTab.id
        }
    }

    mutating func removeTabEntryOnly(id: UUID, from owner: TerminalOwner) {
        tabsById.removeValue(forKey: id)
        var order = orderByOwner[owner] ?? []
        guard let index = order.firstIndex(of: id) else { return }
        order.remove(at: index)
        if order.isEmpty {
            orderByOwner.removeValue(forKey: owner)
            activeTabByOwner.removeValue(forKey: owner)
            if case .terminal(let terminalId) = owner {
                terminalOrder.removeAll { $0 == terminalId }
            }
        } else {
            orderByOwner[owner] = order
            if activeTabByOwner[owner] == id {
                let fallbackIndex = min(index, order.count - 1)
                activeTabByOwner[owner] = order[fallbackIndex]
            }
        }
    }

    func replaceLeaf(_ node: SplitNode, old: UUID, new: UUID) -> SplitNode {
        switch node {
        case .leaf(let id):
            return .leaf(id == old ? new : id)
        case .split(let axis, let ratio, let first, let second):
            return .split(axis: axis, ratio: ratio, first: replaceLeaf(first, old: old, new: new), second: replaceLeaf(second, old: old, new: new))
        }
    }

    func ownerSortOrder(_ lhs: TerminalOwner, _ rhs: TerminalOwner) -> Bool {
        switch (lhs, rhs) {
        case (.terminal(let a), .terminal(let b)):
            let ia = terminalOrder.firstIndex(of: a)
            let ib = terminalOrder.firstIndex(of: b)
            switch (ia, ib) {
            case (.some(let x), .some(let y)): return x < y
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return a.uuidString < b.uuidString
            }
        case (.terminal, _): return true
        case (_, .terminal): return false
        case (.epic(let r1, let i1), .epic(let r2, let i2)):
            return r1 == r2 ? i1 < i2 : r1 < r2
        case (.epic, .session): return true
        case (.session, .epic): return false
        case (.session(let a), .session(let b)): return a < b
        }
    }
}
