import AppKit
import CarrierCore
import Combine
import Foundation
import GhosttyTerminal

/// The store's per-pane Ghostty views, search, input and appearance sync.
extension CarrierTerminalStore {
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

    func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let boxed = MainThreadEventBox(event: event)
            return MainActor.assumeIsolated {
                guard let self else { return boxed }
                return MainThreadEventBox(event: self.handleKeyDownEvent(boxed.event!))
            }.event
        }
    }

    func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    func handleKeyDownEvent(_ event: NSEvent) -> NSEvent? {
        let relevantModifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard isTornDown == false,
              event.type == .keyDown,
              relevantModifiers == .command,
              event.charactersIgnoringModifiers?.lowercased() == "k",
              preferences.terminal.pinPromptToBottom,
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
        let look = Self.appearanceLook(preferences: prefs, scheme: scheme)
        // most changes to the defaults are not the terminal's: they stop here, before the theme and the configuration are built
        guard look.profile != lastAppliedAppearance else { return }
        lastAppliedAppearance = look.profile
        appearanceProfile = look.profile

        let drawn = Self.ghosttyAppearance(look, preferences: prefs)
        controller.setColorScheme(TerminalAppearanceMapper.ghosttyColorScheme(look.scheme))
        _ = controller.setTheme(drawn.theme)
        _ = controller.setTerminalConfiguration(drawn.configuration)
    }

    /// The theme and the configuration Ghostty is given for a look: built only once the profile is known to have changed.
    private static func ghosttyAppearance(
        _ look: (scheme: ThemeScheme, profile: TerminalAppearanceProfile, translucent: Bool),
        preferences: AppPreferences
    ) -> (theme: TerminalTheme, configuration: TerminalConfiguration) {
        (
            TerminalAppearanceMapper.ghosttyTheme(for: look.profile.theme, preferences: preferences, translucent: look.translucent),
            TerminalAppearanceMapper.ghosttyBaseConfiguration(for: look.profile)
        )
    }

    /// The scheme, the profile and whether the terminal is translucent: what decides whether anything changed.
    private static func appearanceLook(
        preferences: AppPreferences,
        scheme: ThemeScheme?
    ) -> (scheme: ThemeScheme, profile: TerminalAppearanceProfile, translucent: Bool) {
        let resolvedScheme = scheme ?? TerminalAppearanceMapper.resolveScheme(preferences.colorScheme)
        let translucent = TerminalAppearanceMapper.resolveTranslucent(preferences)
        let profile = TerminalAppearanceMapper.makeProfile(
            theme: preferences.theme,
            scheme: resolvedScheme,
            preferences: preferences,
            translucent: translucent
        )
        return (resolvedScheme, profile, translucent)
    }

    static func makeAppearanceState(
        preferences: AppPreferences,
        scheme: ThemeScheme?
    ) -> (scheme: ThemeScheme, profile: TerminalAppearanceProfile, theme: TerminalTheme, configuration: TerminalConfiguration) {
        let look = appearanceLook(preferences: preferences, scheme: scheme)
        let drawn = ghosttyAppearance(look, preferences: preferences)
        return (look.scheme, look.profile, drawn.theme, drawn.configuration)
    }
}
