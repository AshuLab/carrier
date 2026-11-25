import AppKit
import CarrierCore

/// The app's two ways to run without a person: `--fixture` (the fake engine and the golden files) and `--selftest` (the menu's actions fired from code).
extension AppDelegate {
    /// `--fixture [folder]`: the folder of golden files, by default the ones inside the app bundle. nil without the flag.
    static func fixturesPath() -> String? {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--fixture") else { return nil }
        if args.indices.contains(flag + 1), args[flag + 1].hasPrefix("--") == false { return args[flag + 1] }
        return (Bundle.main.resourcePath ?? ".") + "/Fixtures"
    }

    /// How the fixture's recognizer behaves: `--fixture-dictation-at-the-end` gives its text only when the person stops, and
    /// `--fixture-dictation-fails` fails to start with a cause, so every state of the box can be seen.
    private static var fixtureDictationMode: FixtureRecognizer.Mode {
        let args = CommandLine.arguments
        if args.contains("--fixture-dictation-at-the-end") { return .atTheEnd }
        if args.contains("--fixture-dictation-fails") { return .failsToStart }
        return .live
    }

    /// Starts the fake engine and points the app at it; with no fixtures to serve the app exits rather than show a stopped Carrier.
    func startFixtureMode(_ fixtures: String) {
        do {
            let server = try FixtureServer(fixtures: fixtures, longTranscript: CommandLine.arguments.contains("--fixture-long-transcript"))
            setenv("CARRIER_HOME", server.home, 1)
            // the Agents page lists the bots of this registry: names and GitHub App ids, never a key (no picture is fetched under --fixture)
            setenv("AGENT_FORGE_CONFIG", server.home + "/agent-forge.json", 1)
            fixtureServer = server
            // what the person has seen and pinned is the app's own: the sessions the list marks start unread (never seen) and pinned
            var seen = SessionSeen.stored()
            seen.markUnread(server.unreadSessionIds)
            seen.store()
            SidebarStore().pinned = Set(server.pinnedSessionIds)
            let recognizer = FixtureRecognizer(mode: Self.fixtureDictationMode)
            MainActor.assumeIsolated { RecognizerRegistry.shared.register(recognizer) }
        } catch {
            FileHandle.standardError.write(Data("carrier: --fixture failed: \(error)\n".utf8))
            exit(1)
        }
    }

    /// The value after `--selftest`, if there is one.
    static func selfTestPath() -> String? {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--selftest") else { return nil }
        guard args.indices.contains(flag + 1) else {
            FileHandle.standardError.write(Data("carrier: --selftest needs a file path\n".utf8))
            return nil
        }
        return args[flag + 1]
    }

    /// Chooses "About Carrier" in the menu as a click would, and reports whether the About panel came up.
    private func chooseAbout() -> String {
        guard let menu = statusItem?.menu, let index = menu.items.firstIndex(where: { $0.title == "About Carrier" }) else { return "no About item" }
        menu.performActionForItem(at: index)
        return "about panel \(NSApp.windows.contains { $0.className.contains("About") && $0.isVisible } ? "shown" : "hidden")"
    }

    /// Runs the menu's actions from code, one a second, and logs each step. Quit is only checked, never fired: it would end
    /// the process, and the last line has to say the process was still alive.
    func selfTest(logPath: String) {
        try? FileManager.default.removeItem(atPath: logPath)
        let log = StepLog(path: logPath)
        func write(_ step: String) {
            do { try log.append(step) } catch {
                FileHandle.standardError.write(Data("carrier: selftest log failed: \(error)\n".utf8))
            }
        }
        var steps: [(String, () -> String)] = [
            ("icon state", { IconController.shared?.summary ?? "no icon" }),
            ("icon hit test passes clicks", { "\(IconController.shared.map { $0.host.hitTest(NSPoint(x: 2, y: 2)) == nil } ?? false)" }),
            ("status item present", { "\(self.statusItem != nil)" }),
            ("menu titles", { (self.statusItem?.menu?.items.map(\.title) ?? []).joined(separator: ", ") }),
            ("epics in the menu", {
                guard let menu = self.statusItem?.menu else { return "no menu" }
                // what the delegate does when the menu opens
                EpicMenuSection.shared.menuNeedsUpdate(menu)
                return menu.items.filter { $0.tag == EpicMenuSection.tag }.map { $0.title.replacingOccurrences(of: "\n", with: " / ") }.joined(separator: ", ")
            }),
            ("icon styles", {
                guard let icon = IconController.shared else { return "no icon" }
                // what the Menu bar tab does: write the preference, the icon follows with no relaunch
                let store = AppPreferences(), saved = store.style
                defer { store.style = saved; icon.reloadSettings() }
                return IconStyle.allCases.map { style in
                    store.style = style
                    icon.reloadSettings()
                    return icon.summary
                }.joined(separator: " | ")
            }),
            ("pause intake", { MenuControls.shared.selfTest(.pause) }),
            ("resume intake", { MenuControls.shared.selfTest(.resume) }),
            ("check GitHub now", { MenuControls.shared.selfTest(.checkNow) }),
            ("stop Carrier", { MenuControls.shared.selfTest(.stop) }),
            ("activation policy accessory", { "\(NSApp.activationPolicy() == .accessory)" }),
            ("setup", { SetupController.shared.summary }),
            ("open settings", { WindowController.shared.showSettings(); return WindowController.shared.settingsStatus }),
            ("close settings", { WindowController.shared.closeSettings(); return WindowController.shared.settingsStatus }),
            ("app windows open", { "\(NSApp.windows.filter { $0.isVisible && $0.level != .statusBar }.count)" }),
            ("quit enabled", {
                guard let menu = self.statusItem?.menu else { return "false" }
                menu.update()
                return "\(menu.items.first { $0.action == #selector(NSApplication.terminate(_:)) }?.isEnabled == true)"
            }),
            ("open window", { WindowController.shared.open(); return WindowController.shared.status }),
            ("close window", { WindowController.shared.close(); return WindowController.shared.status }),
            ("reopen window", { WindowController.shared.open(); return WindowController.shared.status }),
            ("rings, window open", { MainActor.assumeIsolated { RingHostView.summary } }),
            ("rings, window closed", { WindowController.shared.close(); return MainActor.assumeIsolated { RingHostView.summary } }),
            ("choose About Carrier", { self.chooseAbout() }),
            ("notifications", { SystemNotificationCentre.selfTestSummary }),
        ]
        // every page of Settings is drawn, a second each: a page that cannot be drawn (a missing environment object) ends the process here
        if let opened = steps.firstIndex(where: { $0.0 == "open settings" }) {
            let pages: [(String, () -> String)] = SettingsPage.allCases.map { page in
                ("settings page \(page.title)", { WindowController.shared.showSettings(page); return WindowController.shared.settingsStatus })
            }
            // and every screen of the Dictation page, which is a place of its own
            let screens: [(String, () -> String)] = DictationScreen.allCases.map { screen in
                ("settings dictation \(screen.rawValue)", {
                    WindowController.shared.showSettings(place: SettingsPlace(.dictation, path: [screen.rawValue])); return WindowController.shared.settingsStatus
                })
            }
            // and the screen of each role of the Agents page
            let roles: [(String, () -> String)] = AgentRole.allCases.map { role in
                ("settings agents \(role.rawValue)", {
                    WindowController.shared.showSettings(place: SettingsPlace(.agents, path: [role.rawValue])); return WindowController.shared.settingsStatus
                })
            }
            // and the screen of the first project and its actions, when the Carrier folder has one (a fixture does)
            let projects: [(String, () -> String)] = ((try? ProjectsFile.current().read()) ?? []).prefix(1).flatMap { project in
                [
                    ("settings projects screen", {
                        WindowController.shared.showSettings(place: SettingsPlace(.projects, path: [project.path])); return WindowController.shared.settingsStatus
                    }),
                    ("settings projects actions", {
                        WindowController.shared.showSettings(place: SettingsPlace(.projects, path: [project.path, ProjectsTabView.actionsPath])); return WindowController.shared.settingsStatus
                    }),
                ]
            }
            steps.insert(contentsOf: pages + screens + roles + projects, at: opened + 1)
        }
        write("start")
        for (index, step) in steps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1 + Double(index)) {
                write("\(step.0): \(step.1())")
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1 + Double(steps.count) + 2) {
            write("end: process still alive 2 s after the last step")
        }
    }
}
