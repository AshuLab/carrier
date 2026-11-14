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
    var inspectionError: String?
    var delayNanoseconds: UInt64 = 0

    func inspectActiveCommands(in panes: [TerminalPaneInspectionInput]) async -> TerminalProcessInspectionResult {
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if let inspectionError {
            return TerminalProcessInspectionResult(inspectionError: inspectionError)
        }
        var mapped: [UUID: [String]] = [:]
        for pane in panes {
            if let cmds = runningByStateId[ObjectIdentifier(pane.state)], cmds.isEmpty == false {
                mapped[pane.paneId] = cmds
            }
        }
        return TerminalProcessInspectionResult(commandsByPane: mapped)
    }
}

@MainActor
private func waitUntil(timeoutSeconds: TimeInterval = 1.0, _ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while condition() == false {
        if Date() >= deadline { return false }
        await Task.yield()
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    return true
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
        state.isSurfaceVisible = true
        let view = state.makePlatformView!()
        view.controller = store.controller
        #expect(state.onClose != nil)
        #expect(state.onOpenURL != nil)
        #expect(state.makePlatformView != nil)
        #expect(view.controller != nil)

        // Quit teardown must flush workspace to disk AND detach live state/callbacks/platform views.
        store.teardownAll()
        #expect(store.state(for: leftId) == nil)
        #expect(store.platformView(for: leftId) == nil)
        #expect(state.onClose == nil)
        #expect(state.onOpenURL == nil)
        #expect(state.makePlatformView == nil)
        #expect(state.isSurfaceVisible == false)
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

    @Test func gatesCloseAndQuitOnRunningProcessConfirmationWithForceAndPrefOverrides() async {
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
        let busyPane = store.splitPane(idlePane, edge: .trailing, customTitle: "Dev server")!.id

        let idleState = store.state(for: idlePane)!
        let busyState = store.state(for: busyPane)!
        let busyView = busyState.makePlatformView!()
        busyView.controller = store.controller
        inspector.runningByStateId[ObjectIdentifier(busyState)] = ["vite", "vitest"]

        // Idle pane closes cleanly without confirmation.
        #expect(await store.pendingConfirmation(for: .pane(idlePane)) == nil)
        #expect(await store.closePane(id: idlePane, force: false))
        #expect(store.pane(id: idlePane) == nil)
        #expect(store.state(for: idlePane) == nil)
        #expect(idleState.onClose == nil)

        // Busy pane, tab, owner, delete context, and app quit all produce consistent confirmations and refuse non-forced closes.
        let paneQuestion = await store.pendingConfirmation(for: .pane(busyPane))
        #expect(paneQuestion?.title == "Close \u{201C}Dev server\u{201D}?")
        #expect(paneQuestion?.message.contains("vite") == true)
        #expect(paneQuestion?.message.contains("vitest") == true)

        let tabQuestion = await store.pendingConfirmation(for: .tab(tab.id))
        #expect(tabQuestion?.title == "Close tab \u{201C}Dev server\u{201D}?")
        #expect(tabQuestion?.message.contains("Closing this tab will terminate them.") == true)

        let deleteQuestion = await store.pendingConfirmation(for: .owners([session]), removalKind: .delete)
        #expect(deleteQuestion?.title.contains("Delete session") == true)
        #expect(deleteQuestion?.message.contains("Deleting this session") == true)

        let clearQuestion = await store.pendingConfirmation(for: .owners([session, .quick]), removalKind: .clear)
        #expect(clearQuestion?.title == "Delete archived sessions with a running terminal?")
        #expect(clearQuestion?.confirm == "Delete all")

        #expect(await store.pendingConfirmation(for: .owner(session)) != nil)
        #expect(await store.pendingConfirmation(for: .all)?.confirm == "Quit")

        #expect(await store.closePane(id: busyPane, force: false) == false)
        #expect(await store.closeTab(id: tab.id, force: false) == false)
        #expect(await store.closeAll(for: session, force: false) == false)
        #expect(store.pane(id: busyPane) != nil)
        #expect(busyView.controller != nil)

        // Switching confirmation off allows closing even with running command reported.
        var settings = prefs.terminal
        settings.confirmCloseRunningProcess = false
        prefs.terminal = settings
        #expect(await store.pendingConfirmation(for: .pane(busyPane)) == nil)

        // Inspector failure fails safe conservatively without leaking raw process error details into user copy.
        settings.confirmCloseRunningProcess = true
        prefs.terminal = settings
        inspector.runningByStateId = [:]
        inspector.inspectionError = "ps failed"
        let errorQuestion = await store.pendingConfirmation(for: .pane(busyPane))
        #expect(errorQuestion?.message.contains("Could not verify running commands") == true)
        #expect(errorQuestion?.message.contains("ps failed") == false)
        let quitErrorQuestion = await store.pendingConfirmation(for: .all)
        #expect(quitErrorQuestion?.title == "Quit Carrier?")
        let archiveErrorQuestion = await store.pendingConfirmation(for: .owners([session]), removalKind: .archive)
        #expect(archiveErrorQuestion?.title == "Archive session?")

        // Many running commands summarize to at most 3 and use the singular/plural pronoun consistently.
        inspector.inspectionError = nil
        inspector.runningByStateId[ObjectIdentifier(busyState)] = ["cmd-a", "cmd-b", "cmd-c", "cmd-d", "cmd-e"]
        let manyCommandsQuestion = await store.pendingConfirmation(for: .owners([session]), removalKind: .archive)
        #expect(manyCommandsQuestion?.title.hasPrefix("Archive session with running terminal") == true)
        #expect(manyCommandsQuestion?.confirm == "Archive")
        #expect(manyCommandsQuestion?.message.contains("and 2 more") == true)
        #expect(manyCommandsQuestion?.message.contains("terminate them.") == true)

        // Single running command uses singular pronoun cleanly and clips overlong titles.
        let longTitle = String(repeating: "A", count: 80)
        let longCopy = terminalConfirmationQuestion(
            for: .tab(tab.id),
            running: [TerminalActiveProcess(paneId: busyPane, paneTitle: longTitle, commands: ["vite"])],
            targetTitle: longTitle
        )
        #expect(longCopy.title.count < 70)
        #expect(longCopy.title.contains("\u{2026}") == true)
        #expect(longCopy.message.contains("terminate it.") == true)

        // Non-forced closePane / closeTab / closeAll honor onCloseConfirmationNeeded approval/denial.
        var promptedTargets: [TerminalCloseTarget] = []
        store.onCloseConfirmationNeeded = { target, _ in
            promptedTargets.append(target)
            return false
        }
        #expect(await store.closePane(id: busyPane, force: false) == false)
        #expect(await store.closeTab(id: tab.id, force: false) == false)
        #expect(await store.closeAll(for: session, force: false) == false)
        #expect(promptedTargets == [.pane(busyPane), .tab(tab.id), .owner(session)])

        // Forced close tears down state, callbacks, and view synchronously.
        #expect(await store.closeAll(for: session, force: true))
        #expect(store.tabs(for: session).isEmpty)
        #expect(store.state(for: busyPane) == nil)
        #expect(store.platformView(for: busyPane) == nil)
        #expect(busyState.onClose == nil)
        #expect(busyView.controller == nil)
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

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CARRIER_IT_TERMINAL"] != nil))
    func liveGhosttySurfaceSupportsSearchInterruptAndProcessDetection() async throws {
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
        window.contentView = NSHostingView(rootView: CarrierTerminalView(store: store, paneId: paneId, autoFocus: true))
        window.orderBack(nil)
        defer {
            _ = store.forceCloseAll(for: .quick)
            window.orderOut(nil)
        }

        // Wait up to 3s for Ghostty surface & PTY initialization.
        let surfaceReady = await waitUntil(timeoutSeconds: 3.0) {
            state.surface != nil && state.attachedPlatformView?.ttyName != nil
        }
        #expect(surfaceReady)

        // Wait for user shell startup (.zshrc prompt hooks) to reach an idle prompt.
        var reachedIdle = false
        for _ in 0..<25 {
            if await store.pendingConfirmation(for: .pane(paneId)) == nil {
                reachedIdle = true
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        #expect(reachedIdle)

        // Paste command + Enter and wait on scrollback output instead of a blind sleep.
        #expect(store.paste("echo CARRIER_SEARCH_NEEDLE_42", paneId: paneId))
        #expect(state.sendKey(.enter))
        var needleVisible = false
        for _ in 0..<25 {
            _ = state.performBindingAction("select_all")
            if store.selectedText(paneId: paneId)?.contains("CARRIER_SEARCH_NEEDLE_42") == true {
                needleVisible = true
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        #expect(needleVisible)

        _ = store.startSearch(paneId: paneId)
        #expect(store.search("CARRIER_SEARCH_NEEDLE_42", paneId: paneId))
        #expect(store.navigateSearch(next: true, paneId: paneId))
        _ = store.endSearch(paneId: paneId)

        // Spawn a foreground sleep child process and confirm detection catches it cleanly.
        #expect(store.paste("sleep 3", paneId: paneId))
        #expect(state.sendKey(.enter))
        var detected = false
        for _ in 0..<25 {
            if let question = await store.pendingConfirmation(for: .pane(paneId)),
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

        // Start a child process, capture its PID, force-close the workspace, and confirm child process exits.
        #expect(store.paste("sleep 30", paneId: paneId))
        #expect(state.sendKey(.enter))
        var runningChildPid: pid_t?
        if let tty = store.platformView(for: paneId)?.ttyName, tty.isEmpty == false {
            for _ in 0..<25 {
                if let pid = Self.findChildPID(named: "sleep", tty: tty) {
                    runningChildPid = pid
                    break
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        let capturedPid = try #require(runningChildPid)
        #expect(await store.closeAll(for: .quick, force: true))
        let exited = await waitUntil(timeoutSeconds: 3.0) {
            Darwin.kill(capturedPid, 0) != 0 && errno == ESRCH
        }
        #expect(exited)
    }

    private static func findChildPID(named command: String, tty: String) -> pid_t? {
        let shortTTY = tty.hasPrefix("/dev/") ? String(tty.dropFirst(5)) : tty
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "pid=", "-o", "comm=", "-t", shortTTY]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2, let pid = Int32(parts[0]) else { continue }
            let name = URL(fileURLWithPath: String(parts[1])).lastPathComponent
            if name == command {
                return pid
            }
        }
        return nil
    }

    @Test func parsesBatchedPSOutputAndLogsInspectorErrors() async throws {
        let paneA = UUID()
        let paneB = UUID()
        let output = """
          ttys001 -zsh
          ttys001 /bin/dash
          ttys001 /usr/local/bin/ksh
          ttys001 pwsh
          ttys001 <defunct>
          ttys001 vite
          ttys001 node
          ttys002 -tcsh
          ttys002 python3
          ttys002 csh
        """
        let parsed = GhosttyTerminalProcessInspector.parsePSOutput(
            output,
            paneIdsByShortTTY: ["ttys001": [paneA], "ttys002": [paneB]]
        )
        #expect(parsed[paneA] == ["vite", "node"])
        #expect(parsed[paneB] == ["python3"])

        final class LockedLogs: @unchecked Sendable {
            private let lock = NSLock()
            private var items: [String] = []
            func append(_ message: String) {
                lock.lock()
                items.append(message)
                lock.unlock()
            }
            var count: Int {
                lock.lock()
                defer { lock.unlock() }
                return items.count
            }
        }

        let logged = LockedLogs()
        let failingResult = await GhosttyTerminalProcessInspector.runBatchedPS(
            executablePath: "/nonexistent/ps-binary",
            shortTTYs: ["ttys001"],
            paneIdsByShortTTY: ["ttys001": [paneA]],
            timeoutSeconds: 0.5,
            log: { logged.append($0) }
        )
        #expect(failingResult.inspectionError != nil)
        #expect(logged.count == 1)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("carrier-ps-timeout-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let sleepScriptURL = tempDir.appendingPathComponent("slow-ps.sh")
        try "#!/bin/sh\nsleep 2\n".write(to: sleepScriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sleepScriptURL.path)

        let timedOutLogs = LockedLogs()
        let timeoutResult = await GhosttyTerminalProcessInspector.runBatchedPS(
            executablePath: sleepScriptURL.path,
            shortTTYs: ["ttys001"],
            paneIdsByShortTTY: ["ttys001": [paneA]],
            timeoutSeconds: 0.1,
            log: { timedOutLogs.append($0) }
        )
        #expect(timeoutResult.inspectionError?.contains("timed out") == true)
        #expect(timedOutLogs.count == 1)

        let missingTTYInspector = GhosttyTerminalProcessInspector(
            psExecutablePath: "/nonexistent/ps-binary",
            timeoutSeconds: 0.5,
            ttyExists: { _ in false },
            log: { logged.append($0) }
        )
        let dummyState = TerminalViewState(controller: TerminalController(configSource: .none))
        let view = TerminalView()
        let result = await missingTTYInspector.inspectActiveCommands(in: [
            TerminalPaneInspectionInput(paneId: paneA, state: dummyState, platformView: view)
        ])
        // Without a ttyName, no ps invocation occurs; empty input is a clean no-op.
        #expect(result.inspectionError == nil)
        #expect(logged.count == 1)
    }

    @Test func handlesSurfaceCloseCallbackAndPrunesOrPreservesUnknownSchema() async throws {
        let (prefs, cleanup) = makeIsolatedPreferences()
        defer { cleanup() }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("carrier-store-lifecycle-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let fileURL = terminalWorkspaceURL(carrierFolder: tempDir.path)

        // Future schema on disk must remain untouched even when the downgraded run opens tabs and tears down.
        let futureJSON = Data(#"{"schemaVersion":999,"workspaces":[]}"#.utf8)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try futureJSON.write(to: fileURL)

        let futureStore = CarrierTerminalStore(
            fileStore: TerminalWorkspaceFileStore(fileURL: fileURL, log: { _ in }),
            preferences: prefs,
            scheme: .dark,
            fallbackDirectory: "/tmp"
        )
        _ = futureStore.openTab(for: .quick, workingDirectory: "/tmp")
        futureStore.teardownAll()
        #expect(try Data(contentsOf: fileURL) == futureJSON)

        // Corrupt JSON is backed up before recovering persistence for new tabs.
        let corruptJSON = Data("{not-json".utf8)
        try corruptJSON.write(to: fileURL)
        let recoveredStore = CarrierTerminalStore(
            fileStore: TerminalWorkspaceFileStore(fileURL: fileURL, log: { _ in }),
            preferences: prefs,
            scheme: .dark,
            fallbackDirectory: "/tmp"
        )
        let healedTab = recoveredStore.openTab(for: .quick, workingDirectory: "/tmp")
        recoveredStore.teardownAll()
        let dirItems = try FileManager.default.contentsOfDirectory(atPath: fileURL.deletingLastPathComponent().path)
        let backupFile = try #require(dirItems.first { $0.hasPrefix("terminals.json.bak.") })
        #expect(try Data(contentsOf: fileURL.deletingLastPathComponent().appendingPathComponent(backupFile)) == corruptJSON)
        let healedLoaded = TerminalWorkspaceFileStore(fileURL: fileURL, log: { _ in }).load()
        #expect(healedLoaded?.workspaces.first?.tabs.first?.id == healedTab.id)

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

        // processAlive == true without ps match still prompts fallback instead of silently force-closing.
        s1.onClose?(true)
        #expect(await waitUntil { confirmPrompts.count == 1 })
        #expect(store.pane(id: p1) != nil)

        approveClose = true
        s1.onClose?(true)
        #expect(await waitUntil { store.pane(id: p1) == nil })
        #expect(store.state(for: p1) == nil)
        #expect(s1.onClose == nil)

        // Repeated onClose callback for an already-closed pane does not re-prompt.
        let promptsAfterFirstClose = confirmPrompts.count
        s1.onClose?(true)
        await Task.yield()
        #expect(confirmPrompts.count == promptsAfterFirstClose)

        // processAlive == false closes immediately without prompting.
        let t3 = store.openTab(for: keepSession, workingDirectory: "/tmp")
        let s3 = store.state(for: t3.activePaneId)!
        let beforePrompts = confirmPrompts.count
        s3.onClose?(false)
        #expect(await waitUntil { store.pane(id: t3.activePaneId) == nil })
        #expect(confirmPrompts.count == beforePrompts)

        // pruneSessions tears down unlisted sessions synchronously.
        store.pruneSessions(keeping: ["s-keep"])
        #expect(store.tabs(for: dropSession).isEmpty)
        #expect(store.state(for: p2) == nil)
        #expect(store.platformView(for: p2) == nil)
        #expect(s2.onClose == nil)
        #expect(v2.controller == nil)

        store.teardownAll()
    }

    @Test func reconcileKnownSessionsRequiresTwoConsecutiveMissesAndProtectsLocalTabs() {
        let (prefs, cleanup) = makeIsolatedPreferences()
        defer { cleanup() }

        let store = CarrierTerminalStore(
            fileStore: TerminalWorkspaceFileStore(fileURL: nil),
            preferences: prefs,
            scheme: .dark
        )
        let s1 = TerminalOwner.session("s-one")
        let s2 = TerminalOwner.session("s-two")
        _ = store.openTab(for: s1, workingDirectory: "/tmp")
        _ = store.openTab(for: s2, workingDirectory: "/tmp")

        // First poll missing s2 (stale snapshot or concurrent session creation race) keeps s2 alive.
        store.reconcileKnownSessions(["s-one"])
        #expect(store.tabs(for: s1).count == 1)
        #expect(store.tabs(for: s2).count == 1)

        // When s2 appears in the next poll, its strike resets cleanly.
        store.reconcileKnownSessions(["s-one", "s-two"])
        store.reconcileKnownSessions(["s-one"])
        #expect(store.tabs(for: s2).count == 1)

        // A second consecutive authoritative miss prunes s2 while preserving s1 and quick tabs.
        store.reconcileKnownSessions(["s-one"])
        #expect(store.tabs(for: s1).count == 1)
        #expect(store.tabs(for: s2).isEmpty)
    }

    @Test func concurrentOnCloseCallbacksCoalesceIntoSingleConfirmationPrompt() async {
        let (prefs, cleanup) = makeIsolatedPreferences()
        defer { cleanup() }

        let inspector = FakeProcessInspector()
        inspector.delayNanoseconds = 60_000_000
        let store = CarrierTerminalStore(
            fileStore: TerminalWorkspaceFileStore(fileURL: nil),
            preferences: prefs,
            scheme: .dark,
            processInspector: inspector
        )
        let tab = store.openTab(for: .quick, workingDirectory: "/tmp")
        let paneId = tab.activePaneId
        let state = store.state(for: paneId)!
        inspector.runningByStateId[ObjectIdentifier(state)] = ["node"]

        var prompts: [Question] = []
        store.onCloseConfirmationNeeded = { _, question in
            prompts.append(question)
            return false
        }

        // Overlapping close triggers on the same pane while inspection is in flight must produce only one prompt.
        state.onClose?(true)
        state.onClose?(true)
        #expect(await waitUntil { prompts.count == 1 })
        try? await Task.sleep(nanoseconds: 120_000_000)
        #expect(prompts.count == 1)
        #expect(store.pane(id: paneId) != nil)

        store.teardownAll()
    }
}
