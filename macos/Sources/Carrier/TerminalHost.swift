import AppKit
import CarrierCore
import Combine
import Foundation
import GhosttyTerminal
import Observation

private struct AppearanceCacheKey: Equatable {
    let profile: TerminalAppearanceProfile
}

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
    @ObservationIgnored let controller: TerminalController
    @ObservationIgnored private let fileStore: TerminalWorkspaceFileStore
    @ObservationIgnored private let preferences: AppPreferences
    @ObservationIgnored private let processInspector: any TerminalProcessInspecting
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
    @ObservationIgnored private var appearanceObserver: NSKeyValueObservation?
    @ObservationIgnored private var lastAppliedAppearance: AppearanceCacheKey?
    @ObservationIgnored private var hasLoadedOrMutatedPersistence: Bool
    @ObservationIgnored private var isTornDown = false

    /// Hook invoked when Ghostty itself requests closing a live surface (e.g., `close_surface` keybinding).
    @ObservationIgnored var onCloseConfirmationNeeded: (@MainActor (TerminalCloseTarget, Question) -> Bool)?

    init(
        fileStore: TerminalWorkspaceFileStore? = nil,
        preferences: AppPreferences = AppPreferences(),
        scheme: ThemeScheme? = nil,
        processInspector: (any TerminalProcessInspecting)? = nil,
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
        self.persistDebounceNanoseconds = persistDebounceNanoseconds

        let resolvedScheme = scheme ?? Self.resolveScheme(preferences.colorScheme)
        let profile = TerminalAppearanceProfile(
            theme: preferences.theme,
            scheme: resolvedScheme,
            accent: preferences.accent,
            tint: preferences.tint,
            monospace: preferences.monospace,
            terminalSettings: preferences.terminal
        )
        let theme = Self.ghosttyTheme(for: profile.theme, preferences: preferences)
        let config = Self.ghosttyBaseConfiguration(for: profile)
        self.controller = TerminalController(
            configSource: .none,
            theme: theme,
            terminalConfiguration: config
        )
        self.controller.setColorScheme(Self.ghosttyColorScheme(resolvedScheme))
        self.lastAppliedAppearance = AppearanceCacheKey(profile: profile)

        if let initialRegistry {
            self.registry = initialRegistry
            self.hasLoadedOrMutatedPersistence = true
        } else if let persisted = resolvedStore.load() {
            self.registry = TerminalRegistry(
                restoring: persisted,
                knownSessionIds: knownSessionIds,
                fallbackDirectory: fallbackDirectory
            )
            self.hasLoadedOrMutatedPersistence = true
        } else {
            self.registry = TerminalRegistry()
            self.hasLoadedOrMutatedPersistence = false
        }

        if observesSystemAppearance {
            installAppearanceObservers()
        }
    }

    isolated deinit {
        removeAppearanceObservers()
    }

    // MARK: - Queries

    var hasLiveSurfaces: Bool { viewStates.isEmpty == false || platformViews.isEmpty == false }
    func tabs(for owner: TerminalOwner) -> [TerminalTab] { registry.tabs(for: owner) }
    func activeTabId(for owner: TerminalOwner) -> UUID? { registry.activeTabId(for: owner) }
    func activeTab(for owner: TerminalOwner) -> TerminalTab? { registry.activeTab(for: owner) }
    func activePane(for owner: TerminalOwner) -> TerminalPane? { registry.activePane(for: owner) }
    func tab(id tabId: UUID) -> TerminalTab? { registry.tab(id: tabId) }
    func pane(id paneId: UUID) -> TerminalPane? { registry.pane(id: paneId) }

    // MARK: - Tab & Split Workspace Operations

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
        let tab = registry.openTab(owner: owner, spec: spec, activate: activate)
        hasLoadedOrMutatedPersistence = true
        saveWorkspaceNow()
        return tab
    }

    func selectTab(_ tabId: UUID, for owner: TerminalOwner? = nil) {
        registry.selectTab(id: tabId, for: owner)
        if let activePaneId = registry.tab(id: tabId)?.activePaneId {
            focus(paneId: activePaneId)
        }
        hasLoadedOrMutatedPersistence = true
        saveWorkspaceNow()
    }

    @discardableResult
    func moveTab(_ tabId: UUID, toIndex index: Int) -> Bool {
        let moved = registry.moveTab(id: tabId, toIndex: index)
        if moved {
            if let paneId = registry.tab(id: tabId)?.activePaneId {
                focus(paneId: paneId)
            }
            hasLoadedOrMutatedPersistence = true
            saveWorkspaceNow()
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
            if activate, let paneId = registry.tab(id: tabId)?.activePaneId {
                focus(paneId: paneId)
            }
            hasLoadedOrMutatedPersistence = true
            saveWorkspaceNow()
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
        if activate { focus(paneId: created.id) }
        hasLoadedOrMutatedPersistence = true
        saveWorkspaceNow()
        return created
    }

    func selectPane(_ paneId: UUID) {
        registry.selectPane(id: paneId)
        focus(paneId: paneId)
        hasLoadedOrMutatedPersistence = true
        saveWorkspaceNow()
    }

    func setSplitRatio(inTab tabId: UUID, at path: [SplitBranch], ratio: Double) {
        registry.setSplitRatio(inTab: tabId, at: path, ratio: ratio)
        hasLoadedOrMutatedPersistence = true
        schedulePersist()
    }

    func equalizeSplits(inTab tabId: UUID) {
        registry.equalizeSplits(inTab: tabId)
        hasLoadedOrMutatedPersistence = true
        saveWorkspaceNow()
    }

    func toggleZoom(paneId: UUID) {
        registry.toggleZoom(paneId: paneId)
        hasLoadedOrMutatedPersistence = true
        saveWorkspaceNow()
    }

    @discardableResult
    func movePane(_ sourcePaneId: UUID, toTarget targetPaneId: UUID, edge: SplitEdge, ratio: Double = 0.5) -> Bool {
        let moved = registry.movePane(sourcePaneId, toTarget: targetPaneId, edge: edge, ratio: ratio)
        if moved {
            focus(paneId: sourcePaneId)
            hasLoadedOrMutatedPersistence = true
            saveWorkspaceNow()
        }
        return moved
    }

    @discardableResult
    func swapPanes(_ firstPaneId: UUID, _ secondPaneId: UUID) -> Bool {
        let swapped = registry.swapPanes(firstPaneId, secondPaneId)
        if swapped {
            hasLoadedOrMutatedPersistence = true
            saveWorkspaceNow()
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
            if activate { focus(paneId: paneId) }
            hasLoadedOrMutatedPersistence = true
            saveWorkspaceNow()
        }
        return detached
    }

    func renamePane(_ paneId: UUID, customTitle: String?) {
        registry.renamePane(paneId, customTitle: customTitle)
        hasLoadedOrMutatedPersistence = true
        saveWorkspaceNow()
    }

    func pruneSessions(keeping knownSessionIds: Set<String>) {
        let removedPaneIds = registry.pruneSessions(keeping: knownSessionIds)
        guard removedPaneIds.isEmpty == false else { return }
        for paneId in removedPaneIds {
            tearDown(paneId: paneId)
        }
        hasLoadedOrMutatedPersistence = true
        saveWorkspaceNow()
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
        viewStates[paneId]?.performBindingAction("clear_screen") ?? false
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
        let resolvedScheme = scheme ?? Self.resolveScheme(prefs.colorScheme)
        syncAppearance(
            theme: prefs.theme,
            scheme: resolvedScheme,
            accent: prefs.accent,
            tint: prefs.tint,
            monospace: prefs.monospace,
            terminalSettings: prefs.terminal,
            preferencesForDarkLight: prefs
        )
    }

    func syncAppearance(
        theme: Theme,
        scheme: ThemeScheme,
        accent: AccentColor? = nil,
        tint: Tint = .off,
        monospace: MonospaceSettings = MonospaceSettings(),
        terminalSettings: TerminalSettings? = nil,
        preferencesForDarkLight: AppPreferences? = nil
    ) {
        let prefs = preferencesForDarkLight ?? preferences
        let settings = terminalSettings ?? prefs.terminal
        let profile = TerminalAppearanceProfile(
            theme: theme,
            scheme: scheme,
            accent: accent,
            tint: tint,
            monospace: monospace,
            terminalSettings: settings
        )
        let cacheKey = AppearanceCacheKey(profile: profile)
        guard cacheKey != lastAppliedAppearance else { return }
        lastAppliedAppearance = cacheKey

        let lightProfile = TerminalAppearanceProfile(
            theme: theme,
            scheme: .light,
            accent: accent,
            tint: tint,
            monospace: monospace,
            terminalSettings: settings
        )
        let darkProfile = TerminalAppearanceProfile(
            theme: theme,
            scheme: .dark,
            accent: accent,
            tint: tint,
            monospace: monospace,
            terminalSettings: settings
        )

        controller.setColorScheme(Self.ghosttyColorScheme(scheme))
        _ = controller.setTheme(
            TerminalTheme(
                light: Self.ghosttyColorConfiguration(for: lightProfile),
                dark: Self.ghosttyColorConfiguration(for: darkProfile)
            )
        )
        _ = controller.setTerminalConfiguration(Self.ghosttyBaseConfiguration(for: profile))
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
        guard registry.pane(id: paneId) != nil else { return false }
        if force == false, await pendingConfirmation(for: .pane(paneId)) != nil {
            return false
        }
        return forceClosePane(id: paneId)
    }

    @discardableResult
    func forceClosePane(id paneId: UUID) -> Bool {
        guard registry.closePane(id: paneId) != nil else { return false }
        tearDown(paneId: paneId)
        hasLoadedOrMutatedPersistence = true
        saveWorkspaceNow()
        return true
    }

    @discardableResult
    func closeTab(id tabId: UUID, force: Bool = false) async -> Bool {
        guard registry.tab(id: tabId) != nil else { return false }
        if force == false, await pendingConfirmation(for: .tab(tabId)) != nil {
            return false
        }
        return forceCloseTab(id: tabId)
    }

    @discardableResult
    func forceCloseTab(id tabId: UUID) -> Bool {
        guard let tab = registry.tab(id: tabId) else { return false }
        let paneIds = tab.orderedPaneIds
        _ = registry.closeTab(id: tabId)
        for paneId in paneIds {
            tearDown(paneId: paneId)
        }
        hasLoadedOrMutatedPersistence = true
        saveWorkspaceNow()
        return true
    }

    @discardableResult
    func closeAll(for owner: TerminalOwner, force: Bool = false) async -> Bool {
        let paneIds = registry.allPaneIds(for: owner)
        guard paneIds.isEmpty == false else { return true }
        if force == false, await pendingConfirmation(for: .owner(owner)) != nil {
            return false
        }
        return forceCloseAll(for: owner)
    }

    @discardableResult
    func forceCloseAll(for owner: TerminalOwner) -> Bool {
        let paneIds = registry.allPaneIds(for: owner)
        guard paneIds.isEmpty == false else { return true }
        _ = registry.closeAll(for: owner)
        for paneId in paneIds {
            tearDown(paneId: paneId)
        }
        hasLoadedOrMutatedPersistence = true
        saveWorkspaceNow()
        return true
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

        let livePaneIds = Array(Set(viewStates.keys).union(platformViews.keys))
        for paneId in livePaneIds {
            tearDown(paneId: paneId)
        }
    }

    func saveWorkspaceNow() {
        persistTask?.cancel()
        persistTask = nil
        _ = fileStore.save(registry.exportPersistedWorkspace())
    }

    // MARK: - Private Builders & Teardown

    private func buildState(for pane: TerminalPane) -> TerminalViewState {
        let paneId = pane.id
        let state = TerminalViewState(controller: controller)
        state.configuration = TerminalSurfaceOptions(
            backend: .exec,
            workingDirectory: pane.workingDirectory,
            envVars: pane.envVars,
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
                guard let self, self.registry.pane(id: paneId) != nil else { return }
                guard processAlive, self.preferences.terminal.confirmCloseRunningProcess else {
                    _ = self.forceClosePane(id: paneId)
                    return
                }
                let question = await self.pendingConfirmation(for: .pane(paneId)) ?? terminalConfirmationQuestion(
                    for: .pane(paneId),
                    running: [],
                    targetTitle: self.registry.pane(id: paneId)?.displayTitle
                )
                let approved = self.onCloseConfirmationNeeded?(.pane(paneId), question) ?? false
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
                self?.registry.updatePaneWorkingDirectory(cwd, forPane: paneId)
                self?.hasLoadedOrMutatedPersistence = true
                self?.schedulePersist()
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
        appearanceObserver?.invalidate()
        appearanceObserver = nil
    }

    private func schedulePersist() {
        guard fileStore.fileURL != nil else { return }
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

    private static func ghosttyTheme(for theme: Theme, preferences: AppPreferences) -> TerminalTheme {
        let light = TerminalAppearanceProfile(
            theme: theme,
            scheme: .light,
            accent: preferences.accent,
            tint: preferences.tint,
            monospace: preferences.monospace,
            terminalSettings: preferences.terminal
        )
        let dark = TerminalAppearanceProfile(
            theme: theme,
            scheme: .dark,
            accent: preferences.accent,
            tint: preferences.tint,
            monospace: preferences.monospace,
            terminalSettings: preferences.terminal
        )
        return TerminalTheme(
            light: ghosttyColorConfiguration(for: light),
            dark: ghosttyColorConfiguration(for: dark)
        )
    }

    private static func ghosttyColorConfiguration(for profile: TerminalAppearanceProfile) -> TerminalConfiguration {
        TerminalConfiguration { builder in
            builder.withBackground(profile.background.hexString)
            builder.withForeground(profile.foreground.hexString)
            builder.withSelectionBackground(profile.selectionBackground.hexString)
            builder.withSelectionForeground(profile.selectionForeground.hexString)
            builder.withCursorColor(profile.cursorColor.hexString)
            builder.withMinimumContrast(profile.minimumContrast)
        }
    }

    private static func ghosttyBaseConfiguration(for profile: TerminalAppearanceProfile) -> TerminalConfiguration {
        TerminalConfiguration { builder in
            builder.withWindowPaddingX(Int(profile.paddingX.rounded()))
            builder.withWindowPaddingY(Int(profile.paddingY.rounded()))
            builder.withCursorStyle(ghosttyCursorStyle(profile.cursorStyle))
            builder.withCursorStyleBlink(profile.cursorBlink)
            builder.withFontSize(Float(profile.fontSize))
            if let fontFamily = profile.fontFamily {
                builder.withFontFamily(fontFamily)
            }
            builder.withCustom("font-feature", profile.ligatures ? "calt,liga" : "-calt,-liga,-dlig")
        }
    }

    private static func ghosttyCursorStyle(_ choice: TerminalCursorStyleChoice) -> TerminalCursorStyle {
        switch choice {
        case .block: .block
        case .bar: .bar
        case .underline: .underline
        }
    }

    private static func ghosttyColorScheme(_ scheme: ThemeScheme) -> TerminalColorScheme {
        switch scheme {
        case .light: .light
        case .dark: .dark
        }
    }

    private static func resolveScheme(_ choice: ColorSchemeChoice) -> ThemeScheme {
        switch choice {
        case .light: return .light
        case .dark: return .dark
        case .system:
            let name = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
            return name == .aqua ? .light : .dark
        }
    }
}
