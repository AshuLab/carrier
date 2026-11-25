import Foundation

extension TerminalRegistry {
    // MARK: - Split Panes & Intra/Inter-Tab Moves

    @discardableResult
    public mutating func splitPane(
        _ targetPaneId: UUID,
        edge: SplitEdge,
        spec: TerminalLaunchSpec? = nil,
        newPaneId: UUID = UUID(),
        ratio: Double = 0.5,
        activate: Bool = true
    ) -> TerminalPane? {
        guard pane(id: newPaneId) == nil, let loc = location(ofPaneId: targetPaneId), var tab = tabsById[loc.tabId] else {
            return nil
        }
        guard let targetPane = tab.panes[targetPaneId] else { return nil }
        guard let nextRoot = tab.root.inserting(newPaneId, nextTo: targetPaneId, edge: edge, ratio: ratio) else {
            return nil
        }
        let resolvedCwd = spec?.workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let cwd = (resolvedCwd?.isEmpty == false ? resolvedCwd! : targetPane.workingDirectory)
        let pane = TerminalPane(
            id: newPaneId,
            title: spec?.title ?? "Terminal",
            customTitle: spec?.customTitle,
            workingDirectory: cwd,
            envVars: spec?.envVars ?? [:],
            command: spec?.command,
            waitAfterCommand: spec?.waitAfterCommand ?? false
        )
        tab.root = nextRoot
        tab.panes[newPaneId] = pane
        tab.zoomedPaneId = nil
        if activate {
            tab.activePaneId = newPaneId
            activeTabByOwner[tab.owner] = tab.id
        }
        tab.normalize()
        tabsById[tab.id] = tab
        return pane
    }

    public mutating func selectPane(id paneId: UUID) {
        guard let loc = location(ofPaneId: paneId), var tab = tabsById[loc.tabId] else { return }
        tab.activePaneId = paneId
        if let zoomed = tab.zoomedPaneId, zoomed != paneId {
            tab.zoomedPaneId = nil
        }
        tabsById[tab.id] = tab
        activeTabByOwner[loc.owner] = tab.id
    }

    @discardableResult
    public mutating func closePane(id paneId: UUID) -> (removedPane: TerminalPane, closedTabId: UUID?)? {
        guard let loc = location(ofPaneId: paneId), var tab = tabsById[loc.tabId], let pane = tab.panes[paneId] else {
            return nil
        }
        if tab.panes.count <= 1 {
            _ = closeTab(id: tab.id)
            return (pane, tab.id)
        }
        let siblingFallback = tab.root.sibling(of: paneId)
        let removal = tab.root.removing(paneId)
        guard removal.removed, let nextRoot = removal.node else {
            _ = closeTab(id: tab.id)
            return (pane, tab.id)
        }
        tab.root = nextRoot
        tab.panes.removeValue(forKey: paneId)
        if tab.activePaneId == paneId {
            tab.activePaneId = siblingFallback ?? nextRoot.leafPaneIds[0]
        }
        if tab.zoomedPaneId == paneId || tab.panes.count <= 1 {
            tab.zoomedPaneId = nil
        }
        tab.normalize()
        tabsById[tab.id] = tab
        return (pane, nil)
    }

    public mutating func setSplitRatio(inTab tabId: UUID, at path: [SplitBranch], ratio: Double) {
        guard var tab = tabsById[tabId] else { return }
        tab.root = tab.root.settingRatio(at: path, ratio: ratio)
        tabsById[tabId] = tab
    }

    public mutating func equalizeSplits(inTab tabId: UUID) {
        guard var tab = tabsById[tabId] else { return }
        tab.root = tab.root.equalized()
        tabsById[tabId] = tab
    }

    public mutating func toggleZoom(paneId: UUID) {
        guard let loc = location(ofPaneId: paneId), var tab = tabsById[loc.tabId] else { return }
        guard tab.panes.count > 1 else {
            tab.zoomedPaneId = nil
            tabsById[tab.id] = tab
            return
        }
        tab.activePaneId = paneId
        tab.zoomedPaneId = tab.zoomedPaneId == paneId ? nil : paneId
        tabsById[tab.id] = tab
        activeTabByOwner[loc.owner] = tab.id
    }

    @discardableResult
    public mutating func movePane(
        _ sourcePaneId: UUID,
        toTarget targetPaneId: UUID,
        edge: SplitEdge,
        ratio: Double = 0.5
    ) -> Bool {
        guard sourcePaneId != targetPaneId,
              let sourceLoc = location(ofPaneId: sourcePaneId),
              let targetLoc = location(ofPaneId: targetPaneId),
              let sourcePane = tabsById[sourceLoc.tabId]?.panes[sourcePaneId]
        else {
            return false
        }

        if sourceLoc.tabId == targetLoc.tabId {
            guard var tab = tabsById[sourceLoc.tabId], tab.panes.count > 1 else { return false }
            let removed = tab.root.removing(sourcePaneId)
            guard removed.removed, let shrunkRoot = removed.node else { return false }
            guard let expandedRoot = shrunkRoot.inserting(sourcePaneId, nextTo: targetPaneId, edge: edge, ratio: ratio) else {
                return false
            }
            tab.root = expandedRoot
            tab.activePaneId = sourcePaneId
            tab.zoomedPaneId = nil
            tab.normalize()
            tabsById[tab.id] = tab
            activeTabByOwner[tab.owner] = tab.id
            return true
        }

        // Remove from source tab first so the unique leaf invariant holds globally.
        guard closePane(id: sourcePaneId) != nil else { return false }
        guard var targetTab = tabsById[targetLoc.tabId] else { return false }
        guard let expandedRoot = targetTab.root.inserting(sourcePaneId, nextTo: targetPaneId, edge: edge, ratio: ratio) else {
            return false
        }
        targetTab.root = expandedRoot
        targetTab.panes[sourcePaneId] = sourcePane
        targetTab.activePaneId = sourcePaneId
        targetTab.zoomedPaneId = nil
        targetTab.normalize()
        tabsById[targetTab.id] = targetTab
        activeTabByOwner[targetLoc.owner] = targetTab.id
        return true
    }

    @discardableResult
    public mutating func swapPanes(_ firstPaneId: UUID, _ secondPaneId: UUID) -> Bool {
        guard firstPaneId != secondPaneId,
              let firstLoc = location(ofPaneId: firstPaneId),
              let secondLoc = location(ofPaneId: secondPaneId),
              var firstTab = tabsById[firstLoc.tabId],
              var secondTab = tabsById[secondLoc.tabId],
              let firstPane = firstTab.panes[firstPaneId],
              let secondPane = secondTab.panes[secondPaneId]
        else {
            return false
        }

        if firstLoc.tabId == secondLoc.tabId {
            firstTab.root = firstTab.root.swapping(firstPaneId, secondPaneId)
            if firstTab.activePaneId == firstPaneId {
                firstTab.activePaneId = secondPaneId
            } else if firstTab.activePaneId == secondPaneId {
                firstTab.activePaneId = firstPaneId
            }
            firstTab.zoomedPaneId = nil
            firstTab.normalize()
            tabsById[firstTab.id] = firstTab
            return true
        }

        firstTab.root = replaceLeaf(firstTab.root, old: firstPaneId, new: secondPaneId)
        secondTab.root = replaceLeaf(secondTab.root, old: secondPaneId, new: firstPaneId)
        firstTab.panes.removeValue(forKey: firstPaneId)
        firstTab.panes[secondPaneId] = secondPane
        secondTab.panes.removeValue(forKey: secondPaneId)
        secondTab.panes[firstPaneId] = firstPane
        if firstTab.activePaneId == firstPaneId { firstTab.activePaneId = secondPaneId }
        if secondTab.activePaneId == secondPaneId { secondTab.activePaneId = firstPaneId }
        firstTab.zoomedPaneId = nil
        secondTab.zoomedPaneId = nil
        firstTab.normalize()
        secondTab.normalize()
        tabsById[firstTab.id] = firstTab
        tabsById[secondTab.id] = secondTab
        return true
    }

    @discardableResult
    public mutating func detachPaneToNewTab(
        _ paneId: UUID,
        toOwner targetOwner: TerminalOwner? = nil,
        atIndex requestedIndex: Int? = nil,
        newTabId: UUID = UUID(),
        activate: Bool = true
    ) -> TerminalTab? {
        guard tabsById[newTabId] == nil,
              let sourceLoc = location(ofPaneId: paneId),
              let sourceTab = tabsById[sourceLoc.tabId],
              let pane = sourceTab.panes[paneId]
        else {
            return nil
        }

        let destinationOwner = targetOwner ?? sourceLoc.owner
        if sourceTab.panes.count <= 1 {
            guard destinationOwner != sourceLoc.owner else { return nil }
            guard moveTab(id: sourceTab.id, toOwner: destinationOwner, atIndex: requestedIndex, activate: activate) else {
                return nil
            }
            return tabsById[sourceTab.id]
        }

        guard closePane(id: paneId) != nil else { return nil }
        let newTab = TerminalTab(
            id: newTabId,
            owner: destinationOwner,
            root: .leaf(paneId),
            panes: [paneId: pane],
            activePaneId: paneId
        )
        insertTab(newTab, at: requestedIndex, activate: activate)
        return newTab
    }
}
