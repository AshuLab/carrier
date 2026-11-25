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
        let signpost = Signposts.launch.beginInterval("terminal store")
        defer { Signposts.launch.endInterval("terminal store", signpost) }
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

    var registry: TerminalRegistry
    var appearanceProfile: TerminalAppearanceProfile
    @ObservationIgnored let controller: TerminalController
    @ObservationIgnored let fileStore: TerminalWorkspaceFileStore
    @ObservationIgnored let preferences: AppPreferences
    @ObservationIgnored let processInspector: any TerminalProcessInspecting
    @ObservationIgnored let zshShimDirectory: URL
    @ObservationIgnored let processEnvironment: [String: String]
    @ObservationIgnored let persistDebounceNanoseconds: UInt64

    /// Cached Ghostty surface state per `paneId` (reordering tabs or moving panes preserves live shells).
    @ObservationIgnored var viewStates: [UUID: TerminalViewState] = [:]
    /// Cached Ghostty AppKit views per `paneId`.
    @ObservationIgnored var platformViews: [UUID: TerminalView] = [:]
    /// Active SwiftUI mounts per `paneId` to avoid races during overlapping transitions.
    @ObservationIgnored var visibleMountsByPane: [UUID: Set<UUID>] = [:]
    @ObservationIgnored var cancellables: [UUID: Set<AnyCancellable>] = [:]
    @ObservationIgnored var persistTask: Task<Void, Never>?
    @ObservationIgnored var defaultsObserver: NSObjectProtocol?
    @ObservationIgnored var accessibilityObserver: NSObjectProtocol?
    @ObservationIgnored var appearanceObserver: NSKeyValueObservation?
    @ObservationIgnored var keyMonitor: Any?
    @ObservationIgnored var lastAppliedAppearance: TerminalAppearanceProfile?
    @ObservationIgnored var hasLoadedOrMutatedPersistence: Bool
    @ObservationIgnored var persistenceWriteBlocked = false
    @ObservationIgnored var missingSessionsInPreviousPoll: Set<String> = []
    @ObservationIgnored var pendingCloseTargets: Set<TerminalCloseTarget> = []
    @ObservationIgnored var isTornDown = false
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
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment,
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
        self.processEnvironment = processEnvironment
        let derivedCarrierFolder: URL = {
            guard isEphemeralRun == false, let dir = resolvedStore.fileURL?.deletingLastPathComponent() else {
                return FileManager.default.temporaryDirectory.appendingPathComponent(
                    "carrier-ephemeral-terminal-\(ProcessInfo.processInfo.processIdentifier)",
                    isDirectory: true
                )
            }
            let app = dir.deletingLastPathComponent() // the store is <folder>/app/state/terminals.json
            return dir.lastPathComponent == "state" && app.lastPathComponent == "app" ? app.deletingLastPathComponent() : dir
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
}
