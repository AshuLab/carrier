import AppKit
import CarrierCore
import Combine
import Foundation
import GhosttyTerminal
import Observation

/// Manages embedded Ghostty terminal tabs, split panes, pane-keyed platform view caching, search/selection,
/// settings synchronization, workspace persistence, and process close confirmation.
@MainActor
@Observable
final class CarrierTerminalStore {
    private static var _shared: CarrierTerminalStore?

    /// Populated by `WindowController` once chat sessions load so lazy init or live store can prune removed sessions.
    static var lastKnownSessionIds: Set<String>?

    static var sharedIfInitialized: CarrierTerminalStore? { _shared }

    static var shared: CarrierTerminalStore {
        if let existing = _shared { return existing }
        let isSelfTest = CommandLine.arguments.contains("--selftest")
        let store = CarrierTerminalStore(
            observesSystemAppearance: true,
            knownSessionIds: lastKnownSessionIds
        )
        if isSelfTest == false {
            store.onCloseConfirmationNeeded = { _, question in ask(question) }
        }
        _shared = store
        return store
    }

    private(set) var registry: TerminalRegistry
    private(set) var appearanceProfile: TerminalAppearanceProfile
    @ObservationIgnored let controller: TerminalController
    @ObservationIgnored private let fileStore: TerminalWorkspaceFileStore
    @ObservationIgnored private let preferences: AppPreferences
    @ObservationIgnored private let processInspector: any TerminalProcessInspecting
    @ObservationIgnored private let zshShimDirectory: URL
    @ObservationIgnored private let persistDebounceNanoseconds: UInt64

    /// Cached Ghostty surface state per `paneId` (reordering tabs or moving panes preserves live shells).
    @ObservationIgnored private var viewStates: [UUID: TerminalViewState] = [:]
    /// Cached Ghostty AppKit views per `paneId`.
    @ObservationIgnored private var platformViews: [UUID: TerminalView] = [:]
    /// Active SwiftUI mounts per `paneId` to avoid races during overlapping transitions.
    @ObservationIgnored private var visibleMountsByPane: [UUID: Set<UUID>] = [:]
    @ObservationIgnored private var cancellables: [UUID: Set<AnyCancellable>] = [:]
    @ObservationIgnored private var persistTask: Task<Void, Never>?
    @ObservationIgnored private var defaultsObserver: NSObjectProtocol?
    @ObservationIgnored private var accessibilityObserver: NSObjectProtocol?
    @ObservationIgnored private var appearanceObserver: NSKeyValueObservation?
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var lastAppliedAppearance: TerminalAppearanceProfile?
    @ObservationIgnored private var hasLoadedOrMutatedPersistence: Bool
    @ObservationIgnored private var persistenceWriteBlocked = false
    @ObservationIgnored private var missingSessionsInPreviousPoll: Set<String> = []
    @ObservationIgnored private var pendingCloseTargets: Set<TerminalCloseTarget> = []
    @ObservationIgnored private var isTornDown = false
    @ObservationIgnored var performClearScreenForTests: ((UUID) -> Bool)?
    @ObservationIgnored var sendControlLForTests: ((UUID) -> Bool)?
    @ObservationIgnored var focusedPaneResolverForTests: (() -> UUID?)?

    /// Hook invoked when Ghostty itself requests closing a live surface (e.g., `close_surface` keybinding).
    @ObservationIgnored var onCloseConfirmationNeeded: (@MainActor (TerminalCloseTarget, Question) -> Bool)?

    init(
        fileStore: TerminalWorkspaceFileStore? = nil,
        preferences: AppPreferences = AppPreferences(),
        scheme: ThemeScheme? = nil,
        processInspector: (any TerminalProcessInspecting)? = nil,
        zshShimDirectory: URL? = nil,
        persistDebounceNanoseconds: UInt64 = 250_000_000,
        observesSystemAppearance: Bool = false,
        knownSessionIds: Set<String>? = nil,
        fallbackDirectory: String = NSHomeDirectory(),
        initialRegistry: TerminalRegistry? = nil
    ) {
        let isEphemeralRun = CommandLine.arguments.contains("--fixture") || CommandLine.arguments.contains("--selftest")
        let resolvedStore = fileStore ?? TerminalWorkspaceFileStore(
            fileURL: isEphemeralRun ? nil : terminalWorkspaceURL(carrierFolder: currentCarrierFolder())
        )
        self.fileStore = resolvedStore
        self.preferences = preferences
        self.processInspector = processInspector ?? GhosttyTerminalProcessInspector()
        let derivedCarrierFolder: URL = {
            guard let dir = resolvedStore.fileURL?.deletingLastPathComponent() else {
                return URL(fileURLWithPath: currentCarrierFolder(), isDirectory: true)
            }
            return dir.lastPathComponent == "app" ? dir.deletingLastPathComponent() : dir
        }()
        self.zshShimDirectory = zshShimDirectory ?? TerminalZshBottomPromptShim.defaultDirectory(
            carrierFolder: derivedCarrierFolder
        )
        self.persistDebounceNanoseconds = persistDebounceNanoseconds

        let appearance = Self.makeAppearanceState(preferences: preferences, scheme: scheme)
        self.appearanceProfile = appearance.profile
        self.controller = TerminalController(
            configSource: .none,
            theme: appearance.theme,
            terminalConfiguration: appearance.configuration
        )
        self.controller.setColorScheme(TerminalAppearanceMapper.ghosttyColorScheme(appearance.scheme))
        self.lastAppliedAppearance = appearance.profile

        if let initialRegistry {
            self.registry = initialRegistry
            self.hasLoadedOrMutatedPersistence = true
        } else {
            switch resolvedStore.loadResult() {
            case .loaded(let persisted):
                self.registry = TerminalRegistry(
                    restoring: persisted,
                    knownSessionIds: knownSessionIds,
                    fallbackDirectory: fallbackDirectory
                )
                self.hasLoadedOrMutatedPersistence = true
            case .missing:
                self.registry = TerminalRegistry()
                self.hasLoadedOrMutatedPersistence = false
            case .rejected(.corrupt(backedUp: true)):
                // Corrupt file was safely moved to .bak.<timestamp>; allow saving new layout cleanly.
                self.registry = TerminalRegistry()
                self.hasLoadedOrMutatedPersistence = false
            case .rejected:
                self.registry = TerminalRegistry()
                self.hasLoadedOrMutatedPersistence = false
                self.persistenceWriteBlocked = true
            }
        }

        if observesSystemAppearance {
            installAppearanceObservers()
            installKeyMonitor()
        }
    }

    isolated deinit {
        removeAppearanceObservers()
        removeKeyMonitor()
    }

    // MARK: - Queries

    var hasLiveSurfaces: Bool { viewStates.isEmpty == false || platformViews.isEmpty == false }
    func tabs(for owner: TerminalOwner) -> [TerminalTab] { registry.tabs(for: owner) }
    func activeTabId(for owner: TerminalOwner) -> UUID? { registry.activeTabId(for: owner) }
    func activeTab(for owner: TerminalOwner) -> TerminalTab? { registry.activeTab(for: owner) }
    func activePane(for owner: TerminalOwner) -> TerminalPane? { registry.activePane(for: owner) }
    func tab(id tabId: UUID) -> TerminalTab? { registry.tab(id: tabId) }
    func pane(id paneId: UUID) -> TerminalPane? { registry.pane(id: paneId) }
    func standaloneTerminals() -> [StandaloneTerminalSummary] { registry.standaloneTerminals() }
    func standaloneTerminal(id: UUID) -> StandaloneTerminalSummary? { registry.standaloneTerminal(id: id) }

    // MARK: - Tab & Split Workspace Operations

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

    // MARK: - Pane-Keyed Ghostty Views, Search & Input

    func state(for paneId: UUID) -> TerminalViewState? {
        guard isTornDown == false, let pane = registry.pane(id: paneId) else { return nil }
        if let existing = viewStates[paneId] { return existing }

        let state = buildState(for: pane)
        viewStates[paneId] = state
        return state
    }

    func platformView(for paneId: UUID) -> TerminalView? {
        platformViews[paneId]
    }

    func focus(paneId: UUID) {
        viewStates[paneId]?.requestFocus()
    }

    @discardableResult
    func beginVisibilityMount(for paneId: UUID) -> UUID {
        let token = UUID()
        visibleMountsByPane[paneId, default: []].insert(token)
        viewStates[paneId]?.isSurfaceVisible = true
        return token
    }

    func endVisibilityMount(_ token: UUID, for paneId: UUID) {
        guard var tokens = visibleMountsByPane[paneId] else { return }
        tokens.remove(token)
        if tokens.isEmpty {
            visibleMountsByPane.removeValue(forKey: paneId)
            viewStates[paneId]?.isSurfaceVisible = false
        } else {
            visibleMountsByPane[paneId] = tokens
        }
    }

    func setVisible(_ visible: Bool, paneId: UUID) {
        if visible {
            viewStates[paneId]?.isSurfaceVisible = true
        } else {
            visibleMountsByPane.removeValue(forKey: paneId)
            viewStates[paneId]?.isSurfaceVisible = false
        }
    }

    @discardableResult
    func startSearch(paneId: UUID) -> Bool {
        viewStates[paneId]?.performBindingAction("start_search") ?? false
    }

    @discardableResult
    func search(_ needle: String, paneId: UUID) -> Bool {
        viewStates[paneId]?.performBindingAction("search:\(needle)") ?? false
    }

    @discardableResult
    func navigateSearch(next: Bool, paneId: UUID) -> Bool {
        let action = next ? "navigate_search:next" : "navigate_search:previous"
        return viewStates[paneId]?.performBindingAction(action) ?? false
    }

    @discardableResult
    func endSearch(paneId: UUID) -> Bool {
        viewStates[paneId]?.performBindingAction("end_search") ?? false
    }

    @discardableResult
    func clearScrollback(paneId: UUID) -> Bool {
        guard let state = viewStates[paneId] else { return false }
        guard preferences.terminal.pinPromptToBottom,
              registry.pane(id: paneId)?.command == nil
        else {
            return state.performBindingAction("clear_screen")
        }

        let input = TerminalPaneInspectionInput(
            paneId: paneId,
            state: state,
            platformView: platformViews[paneId]
        )
        Task { @MainActor [weak self] in
            guard let self, self.isTornDown == false, let liveState = self.viewStates[paneId] else { return }
            let result = await self.processInspector.inspectActiveCommands(in: [input])
            guard self.isTornDown == false, self.viewStates[paneId] === liveState else { return }
            let cleared = performClearScreenForTests?(paneId) ?? liveState.performBindingAction("clear_screen")
            let hasForegroundCommand = (result.commandsByPane[paneId]?.isEmpty == false)
            if cleared, result.inspectionError == nil, hasForegroundCommand == false, self.preferences.terminal.pinPromptToBottom {
                _ = sendControlLForTests?(paneId) ?? liveState.sendKey(.l, modifiers: .ctrl)
            }
        }
        return true
    }

    func focusedPaneId(for responder: NSResponder?) -> UUID? {
        guard let responderView = responder as? NSView else { return nil }
        for (paneId, terminalView) in platformViews {
            if responderView === terminalView || responderView.isDescendant(of: terminalView) {
                return paneId
            }
        }
        return nil
    }

    private struct MainThreadEventBox: @unchecked Sendable {
        let event: NSEvent?
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let boxed = MainThreadEventBox(event: event)
            return MainActor.assumeIsolated {
                guard let self else { return boxed }
                return MainThreadEventBox(event: self.handleKeyDownEvent(boxed.event!))
            }.event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    func handleKeyDownEvent(_ event: NSEvent) -> NSEvent? {
        let relevantModifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard isTornDown == false,
              preferences.terminal.pinPromptToBottom,
              event.type == .keyDown,
              relevantModifiers == .command,
              event.charactersIgnoringModifiers?.lowercased() == "k",
              let paneId = focusedPaneResolverForTests?() ?? focusedPaneId(for: NSApp?.keyWindow?.firstResponder)
        else {
            return event
        }
        clearScrollback(paneId: paneId)
        return nil
    }

    func selectedText(paneId: UUID) -> String? {
        viewStates[paneId]?.surface?.readSelection()
    }

    @discardableResult
    func paste(_ text: String, paneId: UUID) -> Bool {
        viewStates[paneId]?.paste(text: text) ?? false
    }

    @discardableResult
    func sendInterrupt(paneId: UUID) -> Bool {
        viewStates[paneId]?.sendKey(.c, modifiers: .ctrl) ?? false
    }

    // MARK: - Appearance & Settings Sync

    func syncAppearance(preferences customPreferences: AppPreferences? = nil, scheme: ThemeScheme? = nil) {
        let prefs = customPreferences ?? preferences
        let appearance = Self.makeAppearanceState(preferences: prefs, scheme: scheme)
        guard appearance.profile != lastAppliedAppearance else { return }
        lastAppliedAppearance = appearance.profile
        appearanceProfile = appearance.profile

        controller.setColorScheme(TerminalAppearanceMapper.ghosttyColorScheme(appearance.scheme))
        _ = controller.setTheme(appearance.theme)
        _ = controller.setTerminalConfiguration(appearance.configuration)
    }

    private static func makeAppearanceState(
        preferences: AppPreferences,
        scheme: ThemeScheme?
    ) -> (scheme: ThemeScheme, profile: TerminalAppearanceProfile, theme: TerminalTheme, configuration: TerminalConfiguration) {
        let resolvedScheme = scheme ?? TerminalAppearanceMapper.resolveScheme(preferences.colorScheme)
        let translucent = TerminalAppearanceMapper.resolveTranslucent(preferences)
        let profile = TerminalAppearanceMapper.makeProfile(
            theme: preferences.theme,
            scheme: resolvedScheme,
            preferences: preferences,
            translucent: translucent
        )
        let theme = TerminalAppearanceMapper.ghosttyTheme(
            for: profile.theme,
            preferences: preferences,
            translucent: translucent
        )
        let config = TerminalAppearanceMapper.ghosttyBaseConfiguration(for: profile)
        return (resolvedScheme, profile, theme, config)
    }

    // MARK: - Process Confirmation & Lifecycle Teardown

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

    // MARK: - Private Builders & Teardown

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
            shimDirectory: zshShimDirectory,
            pinPromptToBottom: true,
            command: pane.command
        )
    }

    private func buildState(for pane: TerminalPane) -> TerminalViewState {
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
                    targetTitle: self.registry.pane(id: paneId)?.displayTitle
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

    private func tearDown(paneId: UUID) {
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

    private func installAppearanceObservers() {
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

    private func removeAppearanceObservers() {
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
    private func persistMutation<T>(immediate: Bool = true, _ body: () -> T) -> T {
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

    private func targetPaneIds(for target: TerminalCloseTarget) -> [UUID] {
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
