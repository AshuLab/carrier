import Foundation
import Testing
@testable import CarrierCore

struct TerminalCoreTests {
    @Test func isolatesTabsByOwner() {
        var registry = TerminalRegistry()
        let s1 = TerminalOwner.session("s-1")
        let s2 = TerminalOwner.session("s-2")

        let tab1 = registry.openTab(owner: s1, spec: TerminalLaunchSpec(workingDirectory: "/tmp/s1"))
        let tab2 = registry.openTab(owner: s2, spec: TerminalLaunchSpec(workingDirectory: "/tmp/s2"))
        let quick = registry.openTab(owner: .quick, spec: TerminalLaunchSpec(workingDirectory: "/tmp/quick"))

        #expect(registry.tabs(for: s1).map(\.id) == [tab1.id])
        #expect(registry.tabs(for: s2).map(\.id) == [tab2.id])
        #expect(registry.tabs(for: .quick).map(\.id) == [quick.id])
        #expect(registry.activeTabId(for: s1) == tab1.id)
        #expect(registry.activeTabId(for: s2) == tab2.id)
        #expect(registry.activeTabId(for: .quick) == quick.id)
    }

    @Test func closeTabSelectsNeighborAndCloseAllClearsOnlyTargetOwner() {
        var registry = TerminalRegistry()
        let owner = TerminalOwner.session("s-1")
        let other = TerminalOwner.session("s-2")

        let a = registry.openTab(owner: owner, spec: TerminalLaunchSpec(workingDirectory: "/tmp/a"))
        let b = registry.openTab(owner: owner, spec: TerminalLaunchSpec(workingDirectory: "/tmp/b"))
        let c = registry.openTab(owner: owner, spec: TerminalLaunchSpec(workingDirectory: "/tmp/c"))
        let kept = registry.openTab(owner: other, spec: TerminalLaunchSpec(workingDirectory: "/tmp/kept"))

        #expect(registry.activeTabId(for: owner) == c.id)
        registry.selectTab(id: b.id, for: owner)
        #expect(registry.activeTabId(for: owner) == b.id)

        _ = registry.closeTab(id: b.id)
        #expect(registry.activeTabId(for: owner) == c.id)

        _ = registry.closeTab(id: c.id)
        #expect(registry.activeTabId(for: owner) == a.id)

        _ = registry.closeAll(for: owner)
        #expect(registry.tabs(for: owner).isEmpty)
        #expect(registry.tabs(for: other).map(\.id) == [kept.id])
    }

    @Test func reordersTabsWithinAndAcrossOwners() {
        var registry = TerminalRegistry()
        let owner = TerminalOwner.session("s-1")
        let t1 = registry.openTab(owner: owner, spec: TerminalLaunchSpec(workingDirectory: "/tmp/1"))
        let t2 = registry.openTab(owner: owner, spec: TerminalLaunchSpec(workingDirectory: "/tmp/2"))
        let t3 = registry.openTab(owner: owner, spec: TerminalLaunchSpec(workingDirectory: "/tmp/3"))

        let movedFirst = registry.moveTab(id: t3.id, toIndex: 0)
        #expect(movedFirst)
        #expect(registry.tabs(for: owner).map(\.id) == [t3.id, t1.id, t2.id])

        let movedAcross = registry.moveTab(id: t1.id, toOwner: .quick, atIndex: 0)
        #expect(movedAcross)
        #expect(registry.tabs(for: owner).map(\.id) == [t3.id, t2.id])
        #expect(registry.tabs(for: .quick).map(\.id) == [t1.id])
        #expect(registry.activeTabId(for: .quick) == t1.id)
    }

    @Test func splitsPaneAlongAllEdgesAndInheritsWorkingDirectory() {
        var registry = TerminalRegistry()
        let tab = registry.openTab(owner: .quick, spec: TerminalLaunchSpec(workingDirectory: "/Users/dev/carrier"))
        let rootPane = tab.activePaneId

        let rightPane = registry.splitPane(rootPane, edge: .trailing)
        #expect(rightPane != nil)
        #expect(rightPane?.workingDirectory == "/Users/dev/carrier")

        let topPane = registry.splitPane(rightPane!.id, edge: .top, spec: TerminalLaunchSpec(workingDirectory: "/tmp"))
        #expect(topPane?.workingDirectory == "/tmp")

        let leadingPane = registry.splitPane(rootPane, edge: .leading)
        let bottomPane = registry.splitPane(topPane!.id, edge: .bottom)
        #expect(leadingPane != nil)
        #expect(bottomPane != nil)

        let updated = registry.tab(id: tab.id)!
        #expect(updated.orderedPaneIds == [leadingPane!.id, rootPane, topPane!.id, bottomPane!.id, rightPane!.id])
        #expect(updated.activePaneId == bottomPane!.id)
    }

    @Test func clampsSplitRatiosAndEqualizes() {
        var registry = TerminalRegistry()
        let tab = registry.openTab(owner: .quick, spec: TerminalLaunchSpec(workingDirectory: "/tmp"))
        let first = tab.activePaneId
        let second = registry.splitPane(first, edge: .trailing, ratio: 0.99)!
        let third = registry.splitPane(second.id, edge: .bottom, ratio: 0.01)!

        var updated = registry.tab(id: tab.id)!
        if case .split(.horizontal, let rootRatio, _, let secondSubtree) = updated.root {
            #expect(abs(rootRatio - SplitNode.maxRatio) < 0.0001)
            if case .split(.vertical, let innerRatio, _, _) = secondSubtree {
                #expect(abs(innerRatio - SplitNode.minRatio) < 0.0001)
            } else {
                Issue.record("Expected inner vertical split")
            }
        } else {
            Issue.record("Expected root horizontal split")
        }

        registry.setSplitRatio(inTab: tab.id, at: [], ratio: .nan)
        updated = registry.tab(id: tab.id)!
        if case .split(_, let rootRatio, _, _) = updated.root {
            #expect(rootRatio == 0.5)
        }

        registry.setSplitRatio(inTab: tab.id, at: [.second], ratio: 0.25)
        registry.equalizeSplits(inTab: tab.id)
        updated = registry.tab(id: tab.id)!
        if case .split(_, let rootRatio, _, .split(_, let nestedRatio, _, _)) = updated.root {
            #expect(rootRatio == 0.5)
            #expect(nestedRatio == 0.5)
        } else {
            Issue.record("Expected equalized tree for \(third.id)")
        }
    }

    @Test func togglesZoomClosesPaneWithFallbackAndMovesOrSwapsPanes() {
        var registry = TerminalRegistry()
        let s1 = TerminalOwner.session("s-1")
        let tabA = registry.openTab(owner: s1, spec: TerminalLaunchSpec(workingDirectory: "/tmp/a"))
        let p1 = tabA.activePaneId

        // Single-pane zoom stays off.
        registry.toggleZoom(paneId: p1)
        #expect(registry.tab(id: tabA.id)?.zoomedPaneId == nil)

        let p2 = registry.splitPane(p1, edge: .trailing)!.id
        let p3 = registry.splitPane(p2, edge: .bottom)!.id
        registry.toggleZoom(paneId: p2)
        #expect(registry.tab(id: tabA.id)?.zoomedPaneId == p2)

        registry.toggleZoom(paneId: p2)
        #expect(registry.tab(id: tabA.id)?.zoomedPaneId == nil)

        // Intra-tab move: move p3 next to leading edge of p1.
        let movedIntra = registry.movePane(p3, toTarget: p1, edge: .leading, ratio: 0.3)
        #expect(movedIntra)
        #expect(registry.tab(id: tabA.id)?.orderedPaneIds == [p3, p1, p2])

        // Swap inside same tab.
        let swappedIntra = registry.swapPanes(p3, p2)
        #expect(swappedIntra)
        #expect(registry.tab(id: tabA.id)?.orderedPaneIds == [p2, p1, p3])

        // Move across tabs and swap across tabs.
        let tabB = registry.openTab(owner: .quick, spec: TerminalLaunchSpec(workingDirectory: "/tmp/b"))
        let q1 = tabB.activePaneId
        let movedInter = registry.movePane(p3, toTarget: q1, edge: .bottom)
        #expect(movedInter)
        #expect(registry.tab(id: tabA.id)?.orderedPaneIds == [p2, p1])
        #expect(registry.tab(id: tabB.id)?.orderedPaneIds == [q1, p3])

        let swappedInter = registry.swapPanes(p1, q1)
        #expect(swappedInter)
        #expect(registry.tab(id: tabA.id)?.orderedPaneIds == [p2, q1])
        #expect(registry.tab(id: tabB.id)?.orderedPaneIds == [p1, p3])

        // Detach pane to a brand new tab.
        let detachedTab = registry.detachPaneToNewTab(p1, toOwner: .quick)
        #expect(detachedTab != nil)
        #expect(registry.tab(id: tabB.id)?.orderedPaneIds == [p3])
        #expect(detachedTab?.orderedPaneIds == [p1])

        // Close active pane promotes sibling and falls back focus; closing last pane closes the tab.
        registry.selectPane(id: q1)
        let firstClose = registry.closePane(id: q1)
        #expect(firstClose?.closedTabId == nil)
        #expect(registry.tab(id: tabA.id)?.activePaneId == p2)
        let secondClose = registry.closePane(id: p2)
        #expect(secondClose?.closedTabId == tabA.id)
        #expect(registry.tab(id: tabA.id) == nil)
    }

    @Test func persistsAndRestoresWorkspaceWithValidationAndPruning() throws {
        var registry = TerminalRegistry()
        let validSession = TerminalOwner.session("sess-keep")
        let staleSession = TerminalOwner.session("sess-deleted")

        let quickTab = registry.openTab(
            owner: .quick,
            spec: TerminalLaunchSpec(workingDirectory: "/existing/a", envVars: ["CARRIER_SECRET": "top-secret-value"], title: "Shell")
        )
        let quickRight = registry.splitPane(quickTab.activePaneId, edge: .trailing, ratio: 0.35)!
        registry.renamePane(quickRight.id, customTitle: "Logs")
        registry.updatePaneWorkingDirectory("/missing/worktree", forPane: quickRight.id)
        registry.toggleZoom(paneId: quickRight.id)

        _ = registry.openTab(owner: validSession, spec: TerminalLaunchSpec(workingDirectory: "/existing/b"))
        _ = registry.openTab(owner: staleSession, spec: TerminalLaunchSpec(workingDirectory: "/existing/c"))

        let tempFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("carrier-terminal-persist-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempFolder) }

        let fileURL = terminalWorkspaceURL(carrierFolder: tempFolder.path)
        final class LockedLogs: @unchecked Sendable {
            private let lock = NSLock()
            private var items: [String] = []
            func append(_ message: String) {
                lock.lock()
                items.append(message)
                lock.unlock()
            }
            var values: [String] {
                lock.lock()
                defer { lock.unlock() }
                return items
            }
            var count: Int { values.count }
        }
        let loggedMessages = LockedLogs()
        let store = TerminalWorkspaceFileStore(fileURL: fileURL, log: { loggedMessages.append($0) })
        #expect(store.save(registry.exportPersistedWorkspace()))

        // Persistence must strip envVars on disk and restrict file permissions to 0600.
        let persistedText = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(persistedText.contains("top-secret-value") == false)
        #expect(persistedText.contains("CARRIER_SECRET") == false)
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let permissions = attributes[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)

        let loaded = store.load()
        #expect(loaded != nil)
        #expect(loggedMessages.values.isEmpty)

        let existing = Set(["/existing/a", "/existing/b", "/existing/c", "/fallback/home"])
        let restored = TerminalRegistry(
            restoring: loaded!,
            knownSessionIds: ["sess-keep"],
            fallbackDirectory: "/fallback/home",
            directoryExists: existing.contains
        )

        #expect(restored.tabs(for: staleSession).isEmpty)
        #expect(restored.tabs(for: validSession).count == 1)
        let restoredQuick = restored.tabs(for: .quick).first
        #expect(restoredQuick?.paneCount == 2)
        #expect(restoredQuick?.panes[quickTab.activePaneId]?.envVars.isEmpty == true)
        #expect(restoredQuick?.zoomedPaneId == quickRight.id)
        #expect(restored.pane(id: quickRight.id)?.customTitle == "Logs")
        #expect(restored.pane(id: quickRight.id)?.workingDirectory == "/fallback/home")
        if case .split(.horizontal, let ratio, _, _) = restoredQuick?.root {
            #expect(abs(ratio - 0.35) < 0.0001)
        } else {
            Issue.record("Expected restored split ratio")
        }

        // Unknown schema versions decode safely to an empty registry.
        let future = PersistedTerminalWorkspace(schemaVersion: 999, workspaces: loaded!.workspaces)
        let futureRestored = TerminalRegistry(restoring: future, fallbackDirectory: "/fallback/home", directoryExists: existing.contains)
        #expect(futureRestored.allTabs.isEmpty)

        // Duplicate owners in persisted data merge without orphaning tabs, and mismatched pane ids reconcile to their leaf key.
        let pKey1 = UUID()
        let pKey2 = UUID()
        let t1 = TerminalTab(
            id: UUID(),
            owner: .quick,
            root: .leaf(pKey1),
            panes: [pKey1: TerminalPane(id: UUID(), workingDirectory: "/existing/a")],
            activePaneId: pKey1
        )
        let t2 = TerminalTab(
            id: UUID(),
            owner: .quick,
            root: .leaf(pKey2),
            panes: [pKey2: TerminalPane(id: pKey2, workingDirectory: "/existing/b")],
            activePaneId: pKey2
        )
        let dupPayload = PersistedTerminalWorkspace(workspaces: [
            TerminalWorkspace(owner: .quick, tabs: [t1], activeTabId: t1.id),
            TerminalWorkspace(owner: .quick, tabs: [t2], activeTabId: t2.id),
        ])
        var merged = TerminalRegistry(restoring: dupPayload, fallbackDirectory: "/fallback/home", directoryExists: existing.contains)
        #expect(merged.tabs(for: .quick).count == 2)
        #expect(merged.pane(id: pKey1)?.id == pKey1)
        let prunedEmpty = merged.pruneSessions(keeping: [])
        #expect(prunedEmpty.isEmpty)

        // Post-restore pruning removes unlisted sessions while preserving quick tabs.
        var postPrune = TerminalRegistry(restoring: loaded!, fallbackDirectory: "/fallback/home", directoryExists: existing.contains)
        let removedPaneIds = postPrune.pruneSessions(keeping: ["sess-keep"])
        #expect(removedPaneIds.count == 1)
        #expect(postPrune.tabs(for: staleSession).isEmpty)
        #expect(postPrune.tabs(for: validSession).count == 1)
        #expect(postPrune.tabs(for: .quick).count == 1)

        // Corrupt JSON logs the failure and backs up the corrupt file instead of dropping it silently.
        let corruptBytes = Data("{corrupt".utf8)
        try corruptBytes.write(to: fileURL)
        #expect(store.loadResult() == .rejected(.corrupt(backedUp: true)))
        #expect(loggedMessages.count == 1)
        let folderContents = try FileManager.default.contentsOfDirectory(atPath: fileURL.deletingLastPathComponent().path)
        let backupName = try #require(folderContents.first { $0.hasPrefix("terminals.json.bak.") })
        let backupURL = fileURL.deletingLastPathComponent().appendingPathComponent(backupName)
        #expect(try Data(contentsOf: backupURL) == corruptBytes)
        #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)

        // Unsupported schema versions log why the file was skipped and leave it intact on disk.
        let futureData = try JSONEncoder().encode(future)
        try futureData.write(to: fileURL)
        #expect(store.loadResult() == .rejected(.unsupportedSchema(999)))
        #expect(loggedMessages.count == 2)
        #expect(try Data(contentsOf: fileURL) == futureData)

        // Disabled fileURL performs no I/O.
        let disabled = TerminalWorkspaceFileStore(fileURL: nil)
        #expect(disabled.save(future) == false)
        #expect(disabled.load() == nil)
    }

    @Test func resolveWorkingDirectoryUsesExistingPathOrFallsBack() throws {
        let existing = Set(["/tmp/repo", "/Users/dev"])
        #expect(
            resolveWorkingDirectory(" /tmp/repo ", fallback: "/Users/dev", directoryExists: existing.contains) == "/tmp/repo"
        )
        #expect(
            resolveWorkingDirectory("/tmp/missing", fallback: "/Users/dev", directoryExists: existing.contains) == "/Users/dev"
        )
        #expect(
            resolveWorkingDirectory("   ", fallback: "/Users/dev", directoryExists: existing.contains) == "/Users/dev"
        )

        // Default directory check rejects unreadable/untraversable directories unless root.
        let restrictedDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("carrier-unreadable-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: restrictedDir, withIntermediateDirectories: true)
        defer {
            _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: restrictedDir.path)
            try? FileManager.default.removeItem(at: restrictedDir)
        }
        #expect(isAccessibleTerminalDirectory(restrictedDir.path))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: restrictedDir.path)
        if geteuid() != 0 {
            #expect(resolveWorkingDirectory(restrictedDir.path, fallback: "/tmp") == "/tmp")
        }
    }

    @Test func allNineThemesMaintainHighContrastInLightAndDarkSchemes() {
        for theme in Theme.allCases {
            for scheme in ThemeScheme.allCases {
                let profile = TerminalAppearanceProfile(
                    theme: theme,
                    scheme: scheme,
                    tint: .subtle,
                    monospace: MonospaceSettings(family: "JetBrains Mono", size: 13, ligatures: false),
                    terminalSettings: TerminalSettings(cursorStyle: .bar, cursorBlink: false, paddingX: 12, paddingY: 6, minimumContrast: 4.5)
                )
                #expect(profile.foreground.contrastRatio(with: profile.background) >= 7.0)
                #expect(profile.selectionForeground.contrastRatio(with: profile.selectionBackground) >= 4.5)
                #expect(profile.cursorColor.contrastRatio(with: profile.background) >= 3.0)
                #expect(profile.background.hexString.hasPrefix("#"))
                #expect(profile.foreground.hexString.count == 7)
                #expect(profile.fontFamily == "JetBrains Mono")
                #expect(profile.fontSize == 13)
                #expect(profile.ligatures == false)
                #expect(profile.cursorStyle == .bar)
                #expect(profile.cursorBlink == false)
                #expect(profile.paddingX == 12)
                #expect(profile.paddingY == 6)
                #expect(profile.minimumContrast == 4.5)
            }
        }
    }

    @Test func terminalSettingsInheritMonospaceAndRoundTripInAppPreferences() {
        let suiteName = "carrier.terminal.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let prefs = AppPreferences(defaults: defaults)
        let defaultSettings = prefs.terminal
        #expect(defaultSettings.themeOverride == nil)
        #expect(defaultSettings.cursorStyle == .block)
        #expect(defaultSettings.cursorBlink == true)
        #expect(defaultSettings.confirmCloseRunningProcess == true)
        #expect(defaultSettings.effectiveFontFamily(appMonospace: MonospaceSettings()) == nil)

        prefs.terminal = TerminalSettings(
            themeOverride: .ocean,
            fontFamilyOverride: "SF Mono",
            fontSizeOverride: 30,
            fontLigaturesOverride: false,
            cursorStyle: .underline,
            cursorBlink: false,
            paddingX: -5,
            paddingY: 40,
            minimumContrast: 5.5,
            confirmCloseRunningProcess: false
        )

        let stored = prefs.terminal
        #expect(stored.themeOverride == .ocean)
        #expect(stored.fontFamilyOverride == "SF Mono")
        #expect(stored.fontSizeOverride == 24)
        #expect(stored.fontLigaturesOverride == false)
        #expect(stored.cursorStyle == .underline)
        #expect(stored.cursorBlink == false)
        #expect(stored.paddingX == 0)
        #expect(stored.paddingY == 32)
        #expect(stored.minimumContrast == 5.5)
        #expect(stored.confirmCloseRunningProcess == false)

        prefs.resetTerminal()
        #expect(prefs.terminal == TerminalSettings())
    }

    @Test func urlAllowlistAllowsOnlyHTTPAndHTTPSWithHost() {
        #expect(isAllowedTerminalURL("https://github.com/AshuLab/carrier"))
        #expect(isAllowedTerminalURL("http://localhost:3000"))
        #expect(isAllowedTerminalURL("https://user:secret@github.com/AshuLab/carrier") == false)
        #expect(isAllowedTerminalURL("https://token@github.com") == false)
        #expect(isAllowedTerminalURL("file:///Users/dev/file.swift") == false)
        #expect(isAllowedTerminalURL("file:///Applications/Calculator.app") == false)
        #expect(isAllowedTerminalURL("mailto:dev@carrier.local") == false)
        #expect(isAllowedTerminalURL("smb://fileserver/share") == false)
        #expect(isAllowedTerminalURL("http://") == false)
        #expect(isAllowedTerminalURL("javascript:alert(1)") == false)
        #expect(isAllowedTerminalURL("itms-services://bad") == false)
    }
}
