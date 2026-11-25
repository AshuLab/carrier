import AppKit
import CarrierCore
import Combine
import Foundation
import GhosttyTerminal

/// The store's builders of a pane's Ghostty state, its teardown, its observers and its persistence.
extension CarrierTerminalStore {
    private func resolvedEnvVars(for pane: TerminalPane) -> [String: String] {
        guard preferences.terminal.pinPromptToBottom, pane.command == nil else {
            return pane.envVars
        }
        do {
            try TerminalZshBottomPromptShim.prepareDirectory(zshShimDirectory)
        } catch {
            NSLog(
                "Carrier: failed to prepare Zsh bottom-prompt shim at %@: %@",
                zshShimDirectory.path,
                String(describing: error)
            )
            return pane.envVars
        }
        return TerminalZshBottomPromptShim.mergedEnvironment(
            baseEnvVars: pane.envVars,
            processEnvironment: processEnvironment,
            shimDirectory: zshShimDirectory,
            pinPromptToBottom: true,
            command: pane.command
        )
    }

    func buildState(for pane: TerminalPane) -> TerminalViewState {
        let paneId = pane.id
        let state = TerminalViewState(controller: controller)
        state.configuration = TerminalSurfaceOptions(
            backend: .exec,
            workingDirectory: pane.workingDirectory,
            envVars: resolvedEnvVars(for: pane),
            command: pane.command,
            waitAfterCommand: pane.waitAfterCommand
        )
        state.makePlatformView = { [weak self] in
            if let existing = self?.platformViews[paneId] { return existing }
            let view = TerminalView()
            self?.platformViews[paneId] = view
            return view
        }
        state.onOpenURL = { url, _ in
            guard isAllowedTerminalURL(url), let parsed = URL(string: url) else { return false }
            return NSWorkspace.shared.open(parsed)
        }
        state.onClose = { [weak self] processAlive in
            Task { @MainActor [weak self] in
                guard let self, self.isTornDown == false, self.registry.pane(id: paneId) != nil else { return }
                guard processAlive, self.preferences.terminal.confirmCloseRunningProcess else {
                    _ = self.forceClosePane(id: paneId)
                    return
                }
                let target = TerminalCloseTarget.pane(paneId)
                guard self.pendingCloseTargets.insert(target).inserted else { return }
                defer { self.pendingCloseTargets.remove(target) }
                let question = await self.pendingConfirmation(for: target) ?? terminalConfirmationQuestion(
                    for: target,
                    running: [],
                    targetTitle: self.registry.pane(id: paneId)?.displayTitle()
                )
                guard self.isTornDown == false, self.registry.pane(id: paneId) != nil else { return }
                let approved = self.onCloseConfirmationNeeded?(target, question) ?? false
                if approved {
                    _ = self.forceClosePane(id: paneId)
                }
            }
        }

        var bag: Set<AnyCancellable> = []
        state.$title
            .dropFirst()
            .sink { [weak self] title in
                self?.registry.updatePaneTitle(title, forPane: paneId)
            }
            .store(in: &bag)

        state.$workingDirectory
            .compactMap { $0 }
            .removeDuplicates()
            .sink { [weak self] cwd in
                self?.persistMutation(immediate: false) {
                    self?.registry.updatePaneWorkingDirectory(cwd, forPane: paneId)
                }
            }
            .store(in: &bag)

        state.$isFocused
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak self] _ in
                guard let self, self.isTornDown == false else { return }
                if let location = self.registry.location(ofPaneId: paneId),
                   self.registry.tab(id: location.tabId)?.activePaneId != paneId {
                    self.persistMutation(immediate: false) {
                        self.registry.selectPane(id: paneId)
                    }
                }
            }
            .store(in: &bag)

        cancellables[paneId] = bag
        return state
    }

    func tearDown(paneId: UUID) {
        cancellables.removeValue(forKey: paneId)
        visibleMountsByPane.removeValue(forKey: paneId)
        if let state = viewStates.removeValue(forKey: paneId) {
            state.onClose = nil
            state.onOpenURL = nil
            state.makePlatformView = nil
            state.isSurfaceVisible = false
        }
        if let view = platformViews.removeValue(forKey: paneId) {
            view.controller = nil
        }
    }

    func installAppearanceObservers() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.syncAppearance()
            }
        }
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.syncAppearance()
            }
        }
        appearanceObserver = NSApplication.shared.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.syncAppearance()
                }
            }
        }
    }

    func removeAppearanceObservers() {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
            self.defaultsObserver = nil
        }
        if let accessibilityObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver)
            self.accessibilityObserver = nil
        }
        appearanceObserver?.invalidate()
        appearanceObserver = nil
    }

    @discardableResult
    func persistMutation<T>(immediate: Bool = true, _ body: () -> T) -> T {
        let result = body()
        hasLoadedOrMutatedPersistence = true
        if immediate {
            saveWorkspaceNow()
        } else {
            schedulePersist()
        }
        return result
    }

    private func schedulePersist() {
        guard fileStore.fileURL != nil, persistenceWriteBlocked == false else { return }
        persistTask?.cancel()
        let debounce = persistDebounceNanoseconds
        persistTask = Task { @MainActor [weak self] in
            if debounce > 0 {
                try? await Task.sleep(nanoseconds: debounce)
            }
            guard Task.isCancelled == false else { return }
            self?.saveWorkspaceNow()
        }
    }

    func targetPaneIds(for target: TerminalCloseTarget) -> [UUID] {
        switch target {
        case .pane(let id):
            registry.pane(id: id) != nil ? [id] : []
        case .tab(let id):
            registry.tab(id: id)?.orderedPaneIds ?? []
        case .owner(let owner):
            registry.allPaneIds(for: owner)
        case .owners(let owners):
            owners.flatMap { registry.allPaneIds(for: $0) }
        case .all:
            registry.allPaneIds
        }
    }
}
