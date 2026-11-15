import Foundation
import Testing
@testable import CarrierCore

struct TerminalCoreTests {
    @Test func isolatesTabsByOwner() {
        var registry = TerminalRegistry()
        let s1 = TerminalOwner.session("s-1")
        let s2 = TerminalOwner.session("s-2")
        let standalone = TerminalOwner.terminal(UUID())

        let tab1 = registry.openTab(owner: s1, spec: TerminalLaunchSpec(workingDirectory: "/tmp/s1"))
        let tab2 = registry.openTab(owner: s2, spec: TerminalLaunchSpec(workingDirectory: "/tmp/s2"))
        let terminalTab = registry.openTab(owner: standalone, spec: TerminalLaunchSpec(workingDirectory: "/tmp/standalone"))

        #expect(registry.tabs(for: s1).map(\.id) == [tab1.id])
        #expect(registry.tabs(for: s2).map(\.id) == [tab2.id])
        #expect(registry.tabs(for: standalone).map(\.id) == [terminalTab.id])
        #expect(registry.activeTabId(for: s1) == tab1.id)
        #expect(registry.activeTabId(for: s2) == tab2.id)
        #expect(registry.activeTabId(for: standalone) == terminalTab.id)
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

        let otherOwner = TerminalOwner.terminal(UUID())
        let movedAcross = registry.moveTab(id: t1.id, toOwner: otherOwner, atIndex: 0)
        #expect(movedAcross)
        #expect(registry.tabs(for: owner).map(\.id) == [t3.id, t2.id])
        #expect(registry.tabs(for: otherOwner).map(\.id) == [t1.id])
        #expect(registry.activeTabId(for: otherOwner) == t1.id)
    }

    @Test func splitsPaneAlongAllEdgesAndInheritsWorkingDirectory() {
        var registry = TerminalRegistry()
        let tab = registry.openTab(owner: .terminal(UUID()), spec: TerminalLaunchSpec(workingDirectory: "/Users/dev/carrier"))
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
        let tab = registry.openTab(owner: .terminal(UUID()), spec: TerminalLaunchSpec(workingDirectory: "/tmp"))
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
        let tabB = registry.openTab(owner: s1, spec: TerminalLaunchSpec(workingDirectory: "/tmp/b"))
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
        let detachedTab = registry.detachPaneToNewTab(p1, toOwner: .terminal(UUID()))
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

    @Test func renameTabOverridesTitleAndBlankClearsCustomTitle() {
        var registry = TerminalRegistry()
        let tab = registry.openTab(
            owner: .terminal(UUID()),
            spec: TerminalLaunchSpec(workingDirectory: "/tmp/project", title: "zsh")
        )
        #expect(registry.tab(id: tab.id)?.title == "zsh")

        registry.renameTab(id: tab.id, customTitle: "  Backend  ")
        #expect(registry.tab(id: tab.id)?.customTitle == "Backend")
        #expect(registry.tab(id: tab.id)?.title == "Backend")

        registry.renameTab(id: tab.id, customTitle: "   ")
        #expect(registry.tab(id: tab.id)?.customTitle == nil)
        #expect(registry.tab(id: tab.id)?.title == "zsh")
    }

    @Test func persistsAndRestoresWorkspaceWithValidationAndPruning() throws {
        var registry = TerminalRegistry()
        let validSession = TerminalOwner.session("sess-keep")
        let staleSession = TerminalOwner.session("sess-deleted")
        let standaloneOwner = TerminalOwner.terminal(UUID())

        let standaloneTab = registry.openTab(
            owner: standaloneOwner,
            spec: TerminalLaunchSpec(workingDirectory: "/existing/a", envVars: ["CARRIER_SECRET": "top-secret-value"], title: "Shell")
        )
        let standaloneRight = registry.splitPane(standaloneTab.activePaneId, edge: .trailing, ratio: 0.35)!
        registry.renamePane(standaloneRight.id, customTitle: "Logs")
        registry.updatePaneWorkingDirectory("/missing/worktree", forPane: standaloneRight.id)
        registry.toggleZoom(paneId: standaloneRight.id)

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

        // Re-saving over permissive 0644 permissions enforces 0600 again.
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path)
        #expect(store.save(registry.exportPersistedWorkspace()))
        let tightenedAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        #expect((tightenedAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)

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
        let restoredStandalone = restored.tabs(for: standaloneOwner).first
        #expect(restoredStandalone?.paneCount == 2)
        #expect(restoredStandalone?.panes[standaloneTab.activePaneId]?.envVars.isEmpty == true)
        #expect(restoredStandalone?.zoomedPaneId == standaloneRight.id)
        #expect(restored.pane(id: standaloneRight.id)?.customTitle == "Logs")
        #expect(restored.pane(id: standaloneRight.id)?.workingDirectory == "/fallback/home")
        if case .split(.horizontal, let ratio, _, _) = restoredStandalone?.root {
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
            owner: standaloneOwner,
            root: .leaf(pKey1),
            panes: [pKey1: TerminalPane(id: UUID(), workingDirectory: "/existing/a")],
            activePaneId: pKey1
        )
        let t2 = TerminalTab(
            id: UUID(),
            owner: standaloneOwner,
            root: .leaf(pKey2),
            panes: [pKey2: TerminalPane(id: pKey2, workingDirectory: "/existing/b")],
            activePaneId: pKey2
        )
        let dupPayload = PersistedTerminalWorkspace(workspaces: [
            TerminalWorkspace(owner: standaloneOwner, tabs: [t1], activeTabId: t1.id),
            TerminalWorkspace(owner: standaloneOwner, tabs: [t2], activeTabId: t2.id),
        ])
        var merged = TerminalRegistry(restoring: dupPayload, fallbackDirectory: "/fallback/home", directoryExists: existing.contains)
        #expect(merged.tabs(for: standaloneOwner).count == 2)
        #expect(merged.pane(id: pKey1)?.id == pKey1)
        let prunedEmpty = merged.pruneSessions(keeping: [])
        #expect(prunedEmpty.isEmpty)

        // Post-restore pruning removes unlisted sessions while preserving standalone terminal tabs.
        var postPrune = TerminalRegistry(restoring: loaded!, fallbackDirectory: "/fallback/home", directoryExists: existing.contains)
        let removedPaneIds = postPrune.pruneSessions(keeping: ["sess-keep"])
        #expect(removedPaneIds.count == 1)
        #expect(postPrune.tabs(for: staleSession).isEmpty)
        #expect(postPrune.tabs(for: validSession).count == 1)
        #expect(postPrune.tabs(for: standaloneOwner).count == 1)

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

        // Unsupported schema versions (including future incompatible body shapes) log why skipped and leave the file intact on disk.
        let futureData = Data(#"{"schemaVersion":999,"workspaces":[{"futureField":true}]}"#.utf8)
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
                    translucent: true,
                    monospace: MonospaceSettings(family: "JetBrains Mono", size: 13, ligatures: false),
                    terminalSettings: TerminalSettings(cursorStyle: .bar, cursorBlink: false, paddingX: 12, paddingY: 6, minimumContrast: 4.5)
                )
                #expect(profile.foreground.contrastRatio(with: profile.background) >= 7.0)
                #expect(profile.boldColor.contrastRatio(with: profile.background) >= 7.0)
                #expect(profile.selectionForeground.contrastRatio(with: profile.selectionBackground) >= 4.5)
                #expect(profile.cursorColor.contrastRatio(with: profile.background) >= 3.0)
                #expect(profile.cursorText.contrastRatio(with: profile.cursorColor) >= 4.5)
                #expect(profile.palette.count == 16)
                for index in (1...6) {
                    #expect(profile.palette[index].contrastRatio(with: profile.background) >= 3.5)
                    #expect(profile.palette[index + 8].contrastRatio(with: profile.background) >= 3.5)
                }
                #expect(profile.isSurfaceTranslucent == (theme == .carrier))
                #expect(profile.backgroundOpacity == (theme == .carrier ? 0.0 : 1.0))
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

                let solid = TerminalAppearanceProfile(
                    theme: theme,
                    scheme: scheme,
                    accent: .purple,
                    tint: .strong,
                    translucent: false
                )
                #expect(solid.isSurfaceTranslucent == false)
                #expect(solid.backgroundOpacity == 1.0)
                #expect(solid.chromeBackground == solid.background)
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

        // Newlines and control characters in font names are rejected so Ghostty config cannot be injected.
        #expect(TerminalSettings.cleanFontFamily("Menlo\ncommand = /bin/sh") == nil)
        #expect(TerminalSettings.cleanFontFamily("JetBrains Mono\u{0000}") == nil)
        #expect(TerminalSettings.cleanFontFamily(MonospaceSettings.systemFamily) == nil)
        let injected = TerminalSettings(fontFamilyOverride: "Menlo\ncommand = /bin/sh")
        #expect(injected.fontFamilyOverride == nil)
        #expect(injected.effectiveFontFamily(appMonospace: MonospaceSettings(family: "Menlo")) == "Menlo")
        #expect(injected.effectiveFontFamily(appMonospace: MonospaceSettings(family: "Bad\nFont")) == nil)
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

    @Test func terminalSidebarAndHomeFormattingHelpers() {
        #expect(abbreviatedTerminalPath("/Users/dev", home: "/Users/dev") == "~")
        #expect(abbreviatedTerminalPath("/Users/dev/", home: "/Users/dev") == "~/")
        #expect(abbreviatedTerminalPath("/Users/dev/src/app", home: "/Users/dev") == "~/src/app")
        #expect(abbreviatedTerminalPath("/tmp/work", home: "/Users/dev") == "/tmp/work")

        #expect(terminalsSubtitle(count: 0) == "No terminals")
        #expect(terminalsSubtitle(count: 1) == "1 terminal")
        #expect(terminalsSubtitle(count: 3) == "3 terminals")

        #expect(terminalDropZone(x: 10, y: 50, width: 100, height: 100) == .edge(.leading))
        #expect(terminalDropZone(x: 90, y: 50, width: 100, height: 100) == .edge(.trailing))
        #expect(terminalDropZone(x: 50, y: 10, width: 100, height: 100) == .edge(.top))
        #expect(terminalDropZone(x: 50, y: 90, width: 100, height: 100) == .edge(.bottom))
        #expect(terminalDropZone(x: 50, y: 50, width: 100, height: 100) == .swap)
        #expect(terminalDropZone(x: 0, y: 0, width: 0, height: 100) == .swap)
    }

    @Test func standaloneTerminalsKeepIndependentTabGroupsAndPersistOrder() throws {
        var registry = TerminalRegistry()
        let firstGroup = UUID()
        let secondGroup = UUID()

        let g1t1 = registry.openTab(
            owner: .terminal(firstGroup),
            spec: TerminalLaunchSpec(workingDirectory: "/existing/api", customTitle: "API")
        )
        let g1t2 = registry.openTab(
            owner: .terminal(firstGroup),
            spec: TerminalLaunchSpec(workingDirectory: "/existing/api/logs", title: "Logs")
        )
        _ = registry.splitPane(g1t2.activePaneId, edge: .trailing)

        let g2t1 = registry.openTab(
            owner: .terminal(secondGroup),
            spec: TerminalLaunchSpec(workingDirectory: "/existing/web", title: "Web")
        )

        let summaries = registry.standaloneTerminals()
        #expect(summaries.map(\.id) == [firstGroup, secondGroup])
        #expect(summaries[0].tabCount == 2)
        #expect(summaries[0].totalPaneCount == 3)
        #expect(summaries[0].title == "logs")
        #expect(summaries[0].countsSummary == "2 tabs · 3 panes")
        #expect(summaries[0].subtitle(home: "/existing") == "~/api/logs · 2 tabs · 3 panes")
        #expect(summaries[1].tabCount == 1)
        #expect(summaries[1].countsSummary == nil)
        #expect(summaries[1].subtitle(home: "/existing") == "~/web")

        #expect(filteredStandaloneTerminals(summaries, query: "   ").map(\.id) == [firstGroup, secondGroup])
        #expect(filteredStandaloneTerminals(summaries, query: "api").map(\.id) == [firstGroup])
        #expect(filteredStandaloneTerminals(summaries, query: "/existing/web").map(\.id) == [secondGroup])
        #expect(filteredStandaloneTerminals(summaries, query: "missing").isEmpty)

        // Persisting and restoring preserves standalone terminal groups and deterministic order even when no chat sessions match.
        let exported = registry.exportPersistedWorkspace()
        let encoded = try JSONEncoder().encode(exported)
        let decoded = try JSONDecoder().decode(PersistedTerminalWorkspace.self, from: encoded)
        let restored = TerminalRegistry(
            restoring: decoded,
            knownSessionIds: [],
            fallbackDirectory: "/fallback",
            directoryExists: { _ in true }
        )
        #expect(restored.terminalOrder == [firstGroup, secondGroup])
        #expect(restored.tabs(for: .terminal(firstGroup)).map(\.id) == [g1t1.id, g1t2.id])
        #expect(restored.tabs(for: .terminal(secondGroup)).map(\.id) == [g2t1.id])

        // Closing the final tab in a standalone group removes it from standaloneTerminals and terminalOrder.
        registry.closeAll(for: .terminal(firstGroup))
        #expect(registry.terminalOrder == [secondGroup])
        #expect(registry.standaloneTerminals().map(\.id) == [secondGroup])
    }

    @Test func epicOwnerRoundTripsDeterministicallyAndIsExcludedFromPersistence() throws {
        let epic41 = TerminalOwner.epic(repo: "org/repo", issue: 41)
        let epic42 = TerminalOwner.epic(repo: "org/repo", issue: 42)
        let encodedOwner = try JSONEncoder().encode(epic42)
        let decodedOwner = try JSONDecoder().decode(TerminalOwner.self, from: encodedOwner)
        #expect(decodedOwner == epic42)

        var registry = TerminalRegistry()
        _ = registry.openTab(owner: .session("s1"), spec: TerminalLaunchSpec(workingDirectory: "/existing/s1"))
        let epicTab = registry.openTab(
            owner: epic42,
            spec: TerminalLaunchSpec(
                workingDirectory: "/existing/epic",
                envVars: ["CLAUDE_CONFIG_DIR": "/secret/config"],
                command: "/bin/zsh -il -c 'claude --resume '\''sess-1'\'''",
                title: "Claude · Author"
            )
        )
        _ = registry.openTab(owner: epic41, spec: TerminalLaunchSpec(workingDirectory: "/existing/epic-41"))
        let firstStandaloneId = UUID()
        let secondStandaloneId = UUID()
        _ = registry.openTab(owner: .terminal(firstStandaloneId), spec: TerminalLaunchSpec(workingDirectory: "/existing/api", title: "API"))
        _ = registry.openTab(owner: .terminal(secondStandaloneId), spec: TerminalLaunchSpec(workingDirectory: "/existing/web", title: "Web"))

        #expect(registry.tabs(for: epic42).map(\.id) == [epicTab.id])
        #expect(
            registry.workspaces.map(\.owner) == [
                .terminal(firstStandaloneId),
                .terminal(secondStandaloneId),
                epic41,
                epic42,
                .session("s1"),
            ]
        )

        // Ephemeral epic resume tabs must not be persisted or restored across app launches.
        let exported = registry.exportPersistedWorkspace()
        #expect(exported.workspaces.contains { $0.owner == epic41 || $0.owner == epic42 } == false)

        var injectedWorkspace = exported
        injectedWorkspace.workspaces.append(
            TerminalWorkspace(owner: epic42, tabs: [epicTab], activeTabId: epicTab.id)
        )

        let restored = TerminalRegistry(
            restoring: injectedWorkspace,
            knownSessionIds: ["s1"],
            fallbackDirectory: "/fallback",
            directoryExists: { _ in true }
        )
        #expect(restored.tabs(for: epic42).isEmpty)
        #expect(restored.standaloneTerminals().map(\.id) == [firstStandaloneId, secondStandaloneId])
    }

    @Test func terminalSettingsPageResetAndPickerOptionsPreserveAndRestoreSafely() throws {
        let suiteName = "com.ashulab.carrier.tests.terminal-settings.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let prefs = AppPreferences(defaults: defaults)
        prefs.theme = .ocean
        let custom = TerminalSettings(
            themeOverride: .midnight,
            fontFamilyOverride: "RemovedCustomFont",
            fontSizeOverride: 17,
            fontLigaturesOverride: false,
            fontThicken: true,
            cursorStyle: .underline,
            cursorBlink: false,
            paddingX: 16,
            paddingY: 12,
            minimumContrast: 4.5,
            dimInactivePanes: true,
            focusFollowsMouse: true,
            optionAsAlt: .right,
            copyOnSelect: true,
            scrollbackLimit: .mb100,
            confirmCloseRunningProcess: false,
            pinPromptToBottom: false
        )
        prefs.terminal = custom
        #expect(prefs.terminal == custom)

        #expect(
            TerminalOptionAsAlt.allCases.map(\.title) == ["Off", "Left Option", "Right Option", "Both"]
        )
        #expect(
            TerminalScrollbackLimit.allCases.map(\.title) == ["1 MB", "10 MB", "50 MB", "100 MB"]
        )
        #expect(
            TerminalSettings.availableFontFamilies(
                installed: ["JetBrains Mono", "Menlo"],
                currentOverride: prefs.terminal.fontFamilyOverride
            ) == ["RemovedCustomFont", "JetBrains Mono", "Menlo"]
        )
        #expect(
            TerminalSettings.availableFontFamilies(
                installed: ["JetBrains Mono", "Menlo"],
                currentOverride: "Menlo"
            ) == ["JetBrains Mono", "Menlo"]
        )
        #expect(TerminalSettings.availableFontSizes(currentOverride: prefs.terminal.fontSizeOverride) == Array(9...24))
        #expect(TerminalSettings.minimumContrastLabel(1.0) == "Off · 1.0 : 1")
        #expect(TerminalSettings.minimumContrastLabel(4.5) == "4.5 : 1")

        prefs.reset(.terminal)
        #expect(prefs.terminal == TerminalSettings())
        #expect(prefs.theme == .ocean)

        let lowContrastProfile = TerminalAppearanceProfile(
            theme: .carrier,
            scheme: .dark,
            terminalSettings: TerminalSettings(minimumContrast: 1.0)
        )
        let dim = lowContrastProfile.palette[8]
        #expect(lowContrastProfile.adjustedForMinimumContrast(dim) == dim)

        let strictProfile = TerminalAppearanceProfile(
            theme: .carrier,
            scheme: .dark,
            terminalSettings: TerminalSettings(minimumContrast: 7.0)
        )
        let boosted = strictProfile.adjustedForMinimumContrast(dim)
        #expect(boosted.contrastRatio(with: strictProfile.background) >= 7.0)
    }

    @Test func adjacentTabAndPaneNavigationWrapsCleanlyAndRelativeMoveObeysBounds() {
        var registry = TerminalRegistry()
        let owner = TerminalOwner.terminal(UUID())
        let t1 = registry.openTab(owner: owner, spec: TerminalLaunchSpec(workingDirectory: "/tmp/1"))
        let t2 = registry.openTab(owner: owner, spec: TerminalLaunchSpec(workingDirectory: "/tmp/2"))
        let t3 = registry.openTab(owner: owner, spec: TerminalLaunchSpec(workingDirectory: "/tmp/3"))

        #expect(registry.adjacentTabId(offset: 1, for: owner) == t1.id)
        #expect(registry.adjacentTabId(offset: -1, for: owner) == t2.id)
        #expect(registry.canMoveTab(id: t3.id, offset: 1) == false)
        #expect(registry.canMoveTab(id: t3.id, offset: -1) == true)
        #expect(registry.moveTabRelative(id: t3.id, offset: -1) == true)
        #expect(registry.tabs(for: owner).map(\.id) == [t1.id, t3.id, t2.id])

        let p1 = t1.activePaneId
        let p2 = registry.splitPane(p1, edge: .trailing)!.id
        let p3 = registry.splitPane(p2, edge: .bottom)!.id
        #expect(registry.adjacentPaneId(offset: 1, inTab: t1.id) == p1)
        #expect(registry.adjacentPaneId(offset: -1, inTab: t1.id) == p2)
        registry.selectPane(id: p2)
        #expect(registry.adjacentPaneId(offset: 1, inTab: t1.id) == p3)
    }
}
