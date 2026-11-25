import AppKit
import CarrierCore
import Combine
import Foundation
import GhosttyTerminal

/// The store's tab and split operations: opening, selecting, moving, splitting, renaming and pruning.
extension CarrierTerminalStore {
    @discardableResult
    func createStandaloneTerminal(
        workingDirectory: String?,
        fallbackDirectory: String = NSHomeDirectory()
    ) -> UUID {
        let terminalId = UUID()
        _ = openTab(
            for: .terminal(terminalId),
            workingDirectory: workingDirectory,
            fallbackDirectory: fallbackDirectory,
            activate: true
        )
        return terminalId
    }

    @discardableResult
    func openTab(
        for owner: TerminalOwner,
        workingDirectory: String?,
        envVars: [String: String] = [:],
        command: String? = nil,
        waitAfterCommand: Bool = false,
        title: String? = nil,
        customTitle: String? = nil,
        fallbackDirectory: String = NSHomeDirectory(),
        activate: Bool = true
    ) -> TerminalTab {
        let resolvedCwd = resolveWorkingDirectory(workingDirectory, fallback: fallbackDirectory)
        let spec = TerminalLaunchSpec(
            workingDirectory: resolvedCwd,
            envVars: envVars,
            command: command,
            waitAfterCommand: waitAfterCommand,
            title: title,
            customTitle: customTitle
        )
        return persistMutation {
            let tab = registry.openTab(owner: owner, spec: spec, activate: activate)
            if case .session(let sessionId) = owner {
                missingSessionsInPreviousPoll.remove(sessionId)
            }
            return tab
        }
    }

    func selectTab(_ tabId: UUID, for owner: TerminalOwner? = nil) {
        persistMutation {
            registry.selectTab(id: tabId, for: owner)
            if let activePaneId = registry.tab(id: tabId)?.activePaneId {
                focus(paneId: activePaneId)
            }
        }
    }

    @discardableResult
    func selectAdjacentTab(offset: Int, for owner: TerminalOwner) -> Bool {
        guard let nextTabId = registry.adjacentTabId(offset: offset, for: owner) else { return false }
        selectTab(nextTabId, for: owner)
        return true
    }

    @discardableResult
    func focusAdjacentPane(offset: Int, inTab tabId: UUID) -> Bool {
        guard let nextPaneId = registry.adjacentPaneId(offset: offset, inTab: tabId) else { return false }
        selectPane(nextPaneId)
        return true
    }

    @discardableResult
    func moveTabRelative(_ tabId: UUID, offset: Int) -> Bool {
        guard registry.moveTabRelative(id: tabId, offset: offset) else { return false }
        persistMutation {
            if let paneId = registry.tab(id: tabId)?.activePaneId {
                focus(paneId: paneId)
            }
        }
        return true
    }

    @discardableResult
    func moveTab(_ tabId: UUID, toIndex index: Int) -> Bool {
        let moved = registry.moveTab(id: tabId, toIndex: index)
        if moved {
            persistMutation {
                if let paneId = registry.tab(id: tabId)?.activePaneId {
                    focus(paneId: paneId)
                }
            }
        }
        return moved
    }

    @discardableResult
    func moveTab(
        _ tabId: UUID,
        toOwner destinationOwner: TerminalOwner,
        atIndex index: Int? = nil,
        activate: Bool = true
    ) -> Bool {
        let moved = registry.moveTab(id: tabId, toOwner: destinationOwner, atIndex: index, activate: activate)
        if moved {
            persistMutation {
                if activate, let paneId = registry.tab(id: tabId)?.activePaneId {
                    focus(paneId: paneId)
                }
            }
        }
        return moved
    }

    @discardableResult
    func splitPane(
        _ targetPaneId: UUID,
        edge: SplitEdge,
        workingDirectory: String? = nil,
        envVars: [String: String] = [:],
        command: String? = nil,
        waitAfterCommand: Bool = false,
        title: String? = nil,
        customTitle: String? = nil,
        ratio: Double = 0.5,
        activate: Bool = true
    ) -> TerminalPane? {
        let inheritedCwd = registry.pane(id: targetPaneId)?.workingDirectory ?? NSHomeDirectory()
        let resolvedCwd = resolveWorkingDirectory(workingDirectory ?? inheritedCwd, fallback: inheritedCwd)
        let spec = TerminalLaunchSpec(
            workingDirectory: resolvedCwd,
            envVars: envVars,
            command: command,
            waitAfterCommand: waitAfterCommand,
            title: title,
            customTitle: customTitle
        )
        guard let created = registry.splitPane(targetPaneId, edge: edge, spec: spec, ratio: ratio, activate: activate) else {
            return nil
        }
        return persistMutation {
            if activate { focus(paneId: created.id) }
            return created
        }
    }

    func selectPane(_ paneId: UUID) {
        let alreadyActive = registry.workspaces
            .lazy
            .flatMap(\.tabs)
            .first { $0.panes[paneId] != nil }?
            .activePaneId == paneId
        guard alreadyActive == false else { return }
        persistMutation(immediate: false) {
            registry.selectPane(id: paneId)
            focus(paneId: paneId)
        }
    }

    /// Resolves the currently focused pane in the key window, if any.
    func focusedPaneTarget() -> (tab: TerminalTab, paneId: UUID)? {
        if let focusedId = focusedPaneResolverForTests?() ?? focusedPaneId(for: NSApp?.keyWindow?.firstResponder),
           let tab = registry.workspaces.lazy.flatMap(\.tabs).first(where: { $0.panes[focusedId] != nil }) {
            return (tab, focusedId)
        }
        return nil
    }

    /// Resolves the focused pane in the key window, or falls back to `preferredOwner`'s active pane for menu/keyboard actions.
    func activePaneTarget(preferredOwner: TerminalOwner? = nil) -> (tab: TerminalTab, paneId: UUID)? {
        if let focused = focusedPaneTarget() {
            return focused
        }
        if let preferredOwner, let tab = activeTab(for: preferredOwner) {
            return (tab, tab.activePaneId)
        }
        return nil
    }

    func setSplitRatio(inTab tabId: UUID, at path: [SplitBranch], ratio: Double) {
        persistMutation(immediate: false) {
            registry.setSplitRatio(inTab: tabId, at: path, ratio: ratio)
        }
    }

    func equalizeSplits(inTab tabId: UUID) {
        persistMutation {
            registry.equalizeSplits(inTab: tabId)
        }
    }

    func toggleZoom(paneId: UUID) {
        persistMutation {
            registry.toggleZoom(paneId: paneId)
        }
    }

    @discardableResult
    func movePane(_ sourcePaneId: UUID, toTarget targetPaneId: UUID, edge: SplitEdge, ratio: Double = 0.5) -> Bool {
        let moved = registry.movePane(sourcePaneId, toTarget: targetPaneId, edge: edge, ratio: ratio)
        if moved {
            persistMutation {
                focus(paneId: sourcePaneId)
            }
        }
        return moved
    }

    @discardableResult
    func swapPanes(_ firstPaneId: UUID, _ secondPaneId: UUID) -> Bool {
        let swapped = registry.swapPanes(firstPaneId, secondPaneId)
        if swapped {
            persistMutation {}
        }
        return swapped
    }

    @discardableResult
    func detachPaneToNewTab(
        _ paneId: UUID,
        toOwner targetOwner: TerminalOwner? = nil,
        atIndex index: Int? = nil,
        activate: Bool = true
    ) -> TerminalTab? {
        let detached = registry.detachPaneToNewTab(paneId, toOwner: targetOwner, atIndex: index, activate: activate)
        if detached != nil {
            persistMutation {
                if activate { focus(paneId: paneId) }
            }
        }
        return detached
    }

    func renamePane(_ paneId: UUID, customTitle: String?) {
        persistMutation {
            registry.renamePane(paneId, customTitle: customTitle)
        }
    }

    func renameTab(_ tabId: UUID, customTitle: String?) {
        persistMutation {
            registry.renameTab(id: tabId, customTitle: customTitle)
        }
    }

    /// Reconciles live session terminals with an authoritative list from the chat host,
    /// pruning only sessions missing from two consecutive authoritative snapshots.
    func reconcileKnownSessions(_ knownSessionIds: Set<String>) {
        missingSessionsInPreviousPoll = missingSessionsInPreviousPoll.subtracting(knownSessionIds)
        let activeSessionIds = Set(registry.workspaces.compactMap { workspace -> String? in
            guard case .session(let id) = workspace.owner else { return nil }
            return id
        })
        let missingNow = activeSessionIds.subtracting(knownSessionIds)
        let confirmedMissing = missingNow.intersection(missingSessionsInPreviousPoll)
        missingSessionsInPreviousPoll = missingNow.subtracting(confirmedMissing)
        guard confirmedMissing.isEmpty == false else { return }
        pruneSessions(keeping: Set(activeSessionIds).subtracting(confirmedMissing))
    }

    func pruneSessions(keeping knownSessionIds: Set<String>) {
        let removedPaneIds = registry.pruneSessions(keeping: knownSessionIds)
        guard removedPaneIds.isEmpty == false else { return }
        persistMutation {
            for paneId in removedPaneIds {
                tearDown(paneId: paneId)
            }
        }
    }
}
