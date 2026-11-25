import AppKit
import CarrierCore
import Combine
import Foundation
import GhosttyTerminal

/// The store's close confirmation, process inspection and teardown.
extension CarrierTerminalStore {
    func activeProcesses(for target: TerminalCloseTarget) async -> [TerminalActiveProcess] {
        await inspectProcesses(for: target).running
    }

    func pendingConfirmation(
        for target: TerminalCloseTarget,
        removalKind: SessionRemovalKind? = nil
    ) async -> Question? {
        guard preferences.terminal.confirmCloseRunningProcess else { return nil }
        let inspection = await inspectProcesses(for: target)
        guard inspection.running.isEmpty == false || inspection.error != nil else { return nil }

        let targetTitle: String? = switch target {
        case .pane(let id): registry.pane(id: id)?.displayTitle
        case .tab(let id): registry.tab(id: id)?.title
        case .owner, .owners, .all: nil
        }

        return terminalConfirmationQuestion(
            for: target,
            running: inspection.running,
            targetTitle: targetTitle,
            removalKind: removalKind,
            inspectionError: inspection.error
        )
    }

    @discardableResult
    func closePane(id paneId: UUID, force: Bool = false) async -> Bool {
        if force == false {
            return await confirmAndCloseIfNeeded(
                target: .pane(paneId),
                stillExists: { registry.pane(id: paneId) != nil },
                forceClose: { forceClosePane(id: paneId) }
            )
        }
        return forceClosePane(id: paneId)
    }

    @discardableResult
    func forceClosePane(id paneId: UUID) -> Bool {
        guard registry.closePane(id: paneId) != nil else { return false }
        return persistMutation {
            tearDown(paneId: paneId)
            return true
        }
    }

    @discardableResult
    func closeTab(id tabId: UUID, force: Bool = false) async -> Bool {
        if force == false {
            return await confirmAndCloseIfNeeded(
                target: .tab(tabId),
                stillExists: { registry.tab(id: tabId) != nil },
                forceClose: { forceCloseTab(id: tabId) }
            )
        }
        return forceCloseTab(id: tabId)
    }

    @discardableResult
    func forceCloseTab(id tabId: UUID) -> Bool {
        guard let tab = registry.tab(id: tabId) else { return false }
        return persistMutation {
            let paneIds = tab.orderedPaneIds
            _ = registry.closeTab(id: tabId)
            for paneId in paneIds {
                tearDown(paneId: paneId)
            }
            return true
        }
    }

    @discardableResult
    func closeOtherTabs(except keepingTabId: UUID, for owner: TerminalOwner, force: Bool = false) async -> Bool {
        selectTab(keepingTabId, for: owner)
        let otherIds = registry.tabs(for: owner).map(\.id).filter { $0 != keepingTabId }
        for otherId in otherIds {
            guard await closeTab(id: otherId, force: force) else { return false }
        }
        return true
    }

    @discardableResult
    func closeAll(for owner: TerminalOwner, force: Bool = false) async -> Bool {
        guard registry.allPaneIds(for: owner).isEmpty == false else { return true }
        if force == false {
            return await confirmAndCloseIfNeeded(
                target: .owner(owner),
                stillExists: { registry.allPaneIds(for: owner).isEmpty == false },
                forceClose: { forceCloseAll(for: owner) }
            )
        }
        return forceCloseAll(for: owner)
    }

    @discardableResult
    func forceCloseAll(for owner: TerminalOwner) -> Bool {
        let paneIds = registry.allPaneIds(for: owner)
        guard paneIds.isEmpty == false else { return true }
        return persistMutation {
            _ = registry.closeAll(for: owner)
            for paneId in paneIds {
                tearDown(paneId: paneId)
            }
            return true
        }
    }

    private func confirmAndCloseIfNeeded(
        target: TerminalCloseTarget,
        stillExists: () -> Bool,
        forceClose: () -> Bool
    ) async -> Bool {
        guard stillExists() else { return false }
        guard pendingCloseTargets.insert(target).inserted else { return false }
        defer { pendingCloseTargets.remove(target) }
        if let question = await pendingConfirmation(for: target) {
            guard isTornDown == false, stillExists() else { return false }
            guard onCloseConfirmationNeeded?(target, question) == true else {
                return false
            }
        }
        guard isTornDown == false, stillExists() else { return false }
        return forceClose()
    }

    private func inspectProcesses(for target: TerminalCloseTarget) async -> (running: [TerminalActiveProcess], error: String?) {
        let paneIds = targetPaneIds(for: target)
        let inputs = paneIds.compactMap { paneId -> TerminalPaneInspectionInput? in
            guard let state = viewStates[paneId] else { return nil }
            return TerminalPaneInspectionInput(paneId: paneId, state: state, platformView: platformViews[paneId])
        }
        guard inputs.isEmpty == false else { return ([], nil) }

        let result = await processInspector.inspectActiveCommands(in: inputs)
        var running: [TerminalActiveProcess] = []
        for input in inputs {
            let commands = result.commandsByPane[input.paneId] ?? []
            guard commands.isEmpty == false else { continue }
            let title = registry.pane(id: input.paneId)?.displayTitle ?? "Terminal"
            running.append(TerminalActiveProcess(paneId: input.paneId, paneTitle: title, commands: commands))
        }
        return (running, result.inspectionError)
    }

    /// Persists current workspace layout if initialized with data, then tears down all live surfaces on quit.
    func teardownAll() {
        isTornDown = true
        persistTask?.cancel()
        persistTask = nil
        if hasLoadedOrMutatedPersistence {
            saveWorkspaceNow()
        }
        removeAppearanceObservers()
        removeKeyMonitor()

        let livePaneIds = Array(Set(viewStates.keys).union(platformViews.keys))
        for paneId in livePaneIds {
            tearDown(paneId: paneId)
        }
    }

    func saveWorkspaceNow() {
        persistTask?.cancel()
        persistTask = nil
        guard persistenceWriteBlocked == false else { return }
        _ = fileStore.save(registry.exportPersistedWorkspace())
    }
}
