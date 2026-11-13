import AppKit
import Foundation
import GhosttyTerminal
import SwiftUI
import Testing
@testable import Carrier
@testable import CarrierCore

@MainActor
private final class FakeProcessInspector: TerminalProcessInspecting {
    var runningByStateId: [ObjectIdentifier: [String]] = [:]

    func activeCommands(in state: TerminalViewState, platformView: TerminalView?) -> [String] {
        runningByStateId[ObjectIdentifier(state)] ?? []
    }
}

@MainActor
struct CarrierTerminalStoreTests {
    private func makeIsolatedPreferences() -> (preferences: AppPreferences, cleanup: () -> Void) {
        let suite = "carrier.store.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (AppPreferences(defaults: defaults), { defaults.removePersistentDomain(forName: suite) })
    }

    @Test func preservesPaneKeyedSurfaceCacheAcrossTabReorderAndPaneMoves() {
        let (prefs, cleanup) = makeIsolatedPreferences()
        defer { cleanup() }

        let store = CarrierTerminalStore(
            fileStore: TerminalWorkspaceFileStore(fileURL: nil),
            preferences: prefs,
            scheme: .dark
        )

        let session = TerminalOwner.session("s-cache")
        let t1 = store.openTab(for: session, workingDirectory: "/tmp")
        let p1 = t1.activePaneId
        let p2 = store.splitPane(p1, edge: .trailing)!.id
        let t2 = store.openTab(for: session, workingDirectory: "/tmp")
        let p3 = t2.activePaneId

        let s1 = store.state(for: p1)!
        let s2 = store.state(for: p2)!
        let s3 = store.state(for: p3)!
        let v1 = s1.makePlatformView!()
        let v2 = s2.makePlatformView!()

        store.setVisible(false, paneId: p2)
        #expect(s2.isSurfaceVisible == false)
        store.setVisible(true, paneId: p2)
        #expect(s2.isSurfaceVisible == true)

        // Overlapping mount/unmount from SwiftUI transitions keeps the surface visible until the last mount leaves.
        let mountA = store.beginVisibilityMount(for: p2)
        let mountB = store.beginVisibilityMount(for: p2)
        store.endVisibilityMount(mountA, for: p2)
        #expect(s2.isSurfaceVisible == true)
        store.endVisibilityMount(mountB, for: p2)
        #expect(s2.isSurfaceVisible == false)

        #expect(store.moveTab(t2.id, toIndex: 0))
        #expect(store.state(for: p1) === s1)
        #expect(store.state(for: p2) === s2)
        #expect(store.state(for: p3) === s3)
        #expect(store.platformView(for: p1) === v1)
        #expect(store.platformView(for: p2) === v2)

        #expect(store.movePane(p2, toTarget: p3, edge: .bottom))
        #expect(store.state(for: p2) === s2)
        #expect(store.platformView(for: p2) === v2)

        #expect(store.swapPanes(p1, p3))
        #expect(store.state(for: p1) === s1)
        #expect(store.state(for: p3) === s3)
    }

    @Test func closesTearDownPlatformViewsAndSaveWorkspaceToTempFile() {
        let (prefs, cleanup) = makeIsolatedPreferences()
        defer { cleanup() }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("carrier-store-persist-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let fileURL = terminalWorkspaceURL(carrierFolder: tempDir.path)

        let store = CarrierTerminalStore(
            fileStore: TerminalWorkspaceFileStore(fileURL: fileURL),
            preferences: prefs,
            scheme: .dark,
            fallbackDirectory: "/tmp"
        )

        let keepSession = TerminalOwner.session("session-keep")
        let dropSession = TerminalOwner.session("session-drop")
        let tab = store.openTab(for: keepSession, workingDirectory: "/tmp", title: "Main")
        let leftId = tab.activePaneId
        let right = store.splitPane(leftId, edge: .trailing, ratio: 0.4)!
        store.renamePane(right.id, customTitle: "Runner")
        _ = store.openTab(for: dropSession, workingDirectory: "/tmp")

        let state = store.state(for: leftId)!
        let view = state.makePlatformView!()
        view.controller = store.controller
        #expect(view.controller != nil)

        // Quit teardown must flush workspace to disk AND detach live platform views.
        store.teardownAll()
        #expect(view.controller == nil)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        // Reloading with knownSessionIds prunes removed sessions and keeps remaining split layout.
        let reloaded = CarrierTerminalStore(
            fileStore: TerminalWorkspaceFileStore(fileURL: fileURL),
            preferences: prefs,
            scheme: .dark,
            knownSessionIds: ["session-keep"],
            fallbackDirectory: "/tmp"
        )
        #expect(reloaded.tabs(for: dropSession).isEmpty)
        let restoredTabs = reloaded.tabs(for: keepSession)
        #expect(restoredTabs.count == 1)
        #expect(restoredTabs[0].paneCount == 2)
        #expect(reloaded.pane(id: right.id)?.customTitle == "Runner")
    }

    @Test func gatesCloseAndQuitOnRunningProcessConfirmationWithForceAndPrefOverrides() {
        let (prefs, cleanup) = makeIsolatedPreferences()
        defer { cleanup() }

        let inspector = FakeProcessInspector()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("carrier-store-close-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let fileURL = terminalWorkspaceURL(carrierFolder: tempDir.path)

        let store = CarrierTerminalStore(
            fileStore: TerminalWorkspaceFileStore(fileURL: fileURL),
            preferences: prefs,
            scheme: .dark,
            processInspector: inspector,
            fallbackDirectory: "/tmp"
        )

        let session = TerminalOwner.session("busy-session")
        let tab = store.openTab(for: session, workingDirectory: "/tmp")
        let idlePane = tab.activePaneId
        let busyPane = store.splitPane(idlePane, edge: .trailing)!.id

        let idleState = store.state(for: idlePane)!
        let busyState = store.state(for: busyPane)!
        let busyView = busyState.makePlatformView!()
        busyView.controller = store.controller
        inspector.runningByStateId[ObjectIdentifier(busyState)] = ["vite", "vitest"]

        // Idle pane closes cleanly without confirmation.
        #expect(store.pendingConfirmation(for: .pane(idlePane)) == nil)
        #expect(store.closePane(id: idlePane, force: false))
        #expect(store.pane(id: idlePane) == nil)
        #expect(store.state(for: idlePane) == nil)

        // Busy pane, tab, owner, and app quit all produce confirmations and refuse non-forced closes.
        let paneQuestion = store.pendingConfirmation(for: .pane(busyPane))
        #expect(paneQuestion?.message.contains("vite") == true)
        #expect(paneQuestion?.message.contains("vitest") == true)
        #expect(store.pendingConfirmation(for: .tab(tab.id)) != nil)
        #expect(store.pendingConfirmation(for: .owner(session)) != nil)
        #expect(store.pendingConfirmation(for: .all)?.confirm == "Quit")

        #expect(store.closePane(id: busyPane, force: false) == false)
        #expect(store.closeTab(id: tab.id, force: false) == false)
        #expect(store.closeAll(for: session, force: false) == false)
        #expect(store.pane(id: busyPane) != nil)
        #expect(busyView.controller != nil)

        // Switching confirmation off allows closing even with running command reported.
        var settings = prefs.terminal
        settings.confirmCloseRunningProcess = false
        prefs.terminal = settings
        #expect(store.pendingConfirmation(for: .pane(busyPane)) == nil)

        // Forced close tears down the view synchronously.
        settings.confirmCloseRunningProcess = true
        prefs.terminal = settings
        #expect(store.closeAll(for: session, force: true))
        #expect(store.tabs(for: session).isEmpty)
        #expect(busyView.controller == nil)
        _ = idleState
    }

    @Test func syncsTerminalSettingsAndThemesIntoGhosttyController() {
        let (prefs, cleanup) = makeIsolatedPreferences()
        defer { cleanup() }

        let store = CarrierTerminalStore(
            fileStore: TerminalWorkspaceFileStore(fileURL: nil),
            preferences: prefs,
            scheme: .dark
        )

        var terminal = prefs.terminal
        terminal.themeOverride = .forest
        terminal.cursorStyle = .bar
        terminal.cursorBlink = false
        terminal.paddingX = 14
        terminal.paddingY = 12
        terminal.minimumContrast = 4.5
        terminal.fontFamilyOverride = "Menlo"
        terminal.fontSizeOverride = 15
        terminal.fontLigaturesOverride = false
        prefs.terminal = terminal

        store.syncAppearance(preferences: prefs, scheme: .light)
        let rendered = store.controller.renderedConfig
        #expect(rendered.contains("cursor-style = bar"))
        #expect(rendered.contains("cursor-style-blink = false"))
        #expect(rendered.contains("window-padding-x = 14"))
        #expect(rendered.contains("window-padding-y = 12"))
        #expect(rendered.contains("minimum-contrast = 4.5"))
        #expect(rendered.contains("font-family = Menlo"))
        #expect(rendered.contains("font-size = 15"))
    }

    @Test func liveGhosttySurfaceSupportsSearchInterruptAndProcessDetection() async {
        let (prefs, cleanup) = makeIsolatedPreferences()
        defer { cleanup() }

        let store = CarrierTerminalStore(
            fileStore: TerminalWorkspaceFileStore(fileURL: nil),
            preferences: prefs,
            scheme: .dark
        )

        let tab = store.openTab(for: .quick, workingDirectory: "/tmp")
        let paneId = tab.activePaneId
        let state = store.state(for: paneId)!

        let window = NSWindow(
            contentRect: NSRect(x: -4000, y: -4000, width: 640, height: 360),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: CarrierTerminalView(store: store, paneId: paneId))
        window.orderBack(nil)
        defer {
            store.closeAll(for: .quick, force: true)
            window.orderOut(nil)
        }

        // Wait up to 3s for Ghostty surface & PTY initialization.
        for _ in 0..<30 {
            if state.surface != nil, state.attachedPlatformView?.ttyName != nil {
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        #expect(state.surface != nil)

        // Wait briefly for user shell startup (.zshrc prompt hooks) to reach an idle prompt.
        for _ in 0..<25 {
            if store.pendingConfirmation(for: .pane(paneId)) == nil {
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        #expect(store.pendingConfirmation(for: .pane(paneId)) == nil)

        // Paste command + Enter (zsh bracketed paste holds newlines in the edit buffer until Enter).
        #expect(store.paste("echo CARRIER_SEARCH_NEEDLE_42", paneId: paneId))
        #expect(state.sendKey(.enter))
        try? await Task.sleep(nanoseconds: 350_000_000)

        _ = store.startSearch(paneId: paneId)
        #expect(store.search("CARRIER_SEARCH_NEEDLE_42", paneId: paneId))
        #expect(store.navigateSearch(next: true, paneId: paneId))
        _ = store.endSearch(paneId: paneId)
        #expect(state.performBindingAction("select_all"))
        #expect(store.selectedText(paneId: paneId)?.contains("CARRIER_SEARCH_NEEDLE_42") == true)

        // Spawn a foreground sleep child process and confirm detection catches it cleanly.
        #expect(store.paste("sleep 3", paneId: paneId))
        #expect(state.sendKey(.enter))
        var detected = false
        for _ in 0..<25 {
            if let question = store.pendingConfirmation(for: .pane(paneId)),
               question.message.contains("sleep") {
                detected = true
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        #expect(detected)

        // Send Ctrl+C to terminate sleep and verify clearScrollback dispatches cleanly.
        #expect(store.sendInterrupt(paneId: paneId))
        #expect(store.clearScrollback(paneId: paneId))
    }

    @Test func handlesSurfaceCloseCallbackAndPrunesOrPreservesUnknownSchema() async throws {
        let (prefs, cleanup) = makeIsolatedPreferences()
        defer { cleanup() }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("carrier-store-lifecycle-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let fileURL = terminalWorkspaceURL(carrierFolder: tempDir.path)

        // Future schema on disk must remain untouched when store never loads or mutates workspace state.
        let futureJSON = Data(#"{"schemaVersion":999,"workspaces":[]}"#.utf8)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try futureJSON.write(to: fileURL)

        let untouchedStore = CarrierTerminalStore(
            fileStore: TerminalWorkspaceFileStore(fileURL: fileURL),
            preferences: prefs,
            scheme: .dark,
            fallbackDirectory: "/tmp"
        )
        untouchedStore.teardownAll()
        #expect(try Data(contentsOf: fileURL) == futureJSON)

        // Store with live sessions handles state.onClose(processAlive: true/false) and pruneSessions.
        let store = CarrierTerminalStore(
            fileStore: TerminalWorkspaceFileStore(fileURL: nil),
            preferences: prefs,
            scheme: .dark,
            observesSystemAppearance: true
        )
        let keepSession = TerminalOwner.session("s-keep")
        let dropSession = TerminalOwner.session("s-drop")
        let t1 = store.openTab(for: keepSession, workingDirectory: "/tmp")
        let t2 = store.openTab(for: dropSession, workingDirectory: "/tmp")
        let p1 = t1.activePaneId
        let p2 = t2.activePaneId

        let s1 = store.state(for: p1)!
        let s2 = store.state(for: p2)!
        let v2 = s2.makePlatformView!()
        v2.controller = store.controller

        var confirmPrompts: [Question] = []
        var approveClose = false
        store.onCloseConfirmationNeeded = { _, question in
            confirmPrompts.append(question)
            return approveClose
        }

        // processAlive == true without ps match still prompts generic fallback instead of silently force-closing.
        s1.onClose?(true)
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(confirmPrompts.count == 1)
        #expect(store.pane(id: p1) != nil)

        approveClose = true
        s1.onClose?(true)
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(store.pane(id: p1) == nil)

        // Repeated onClose callback for an already-closed pane does not re-prompt.
        let promptsAfterFirstClose = confirmPrompts.count
        s1.onClose?(true)
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(confirmPrompts.count == promptsAfterFirstClose)

        // processAlive == false closes immediately without prompting.
        let t3 = store.openTab(for: keepSession, workingDirectory: "/tmp")
        let s3 = store.state(for: t3.activePaneId)!
        let beforePrompts = confirmPrompts.count
        s3.onClose?(false)
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(confirmPrompts.count == beforePrompts)
        #expect(store.pane(id: t3.activePaneId) == nil)

        // pruneSessions tears down unlisted sessions synchronously.
        store.pruneSessions(keeping: ["s-keep"])
        #expect(store.tabs(for: dropSession).isEmpty)
        #expect(v2.controller == nil)

        store.teardownAll()
    }
}
