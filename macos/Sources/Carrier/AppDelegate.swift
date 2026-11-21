import AppKit
import CarrierCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let header = StatusHeaderView()
    private var fixtureServer: FixtureServer?
    /// Start on open looks once, at the first state the monitor delivers (main thread).
    private var triedStartOnOpen = false
    /// The combinations the main menu was built with (MainMenu.swift).
    var shortcutsInMenu: [KeyCombo?] = []
    private var isConfirmingTermination = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let launching = Signposts.launch.beginInterval("didFinishLaunching")
        defer { Signposts.launch.endInterval("didFinishLaunching", launching) }
        // once, the first time the main run loop is about to sleep: after Core Animation's commit observer (order 2_000_000), so close to the
        // first frame handed to the window server; compares the work deferred with main.async against it
        let firstCommit = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false, CFIndex.max) { _, _ in
            Signposts.launch.emitEvent("first commit")
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), firstCommit, .commonModes)
        // before the menu, whose "Check for Updates…" item is the updater controller's
        let updating = Signposts.launch.beginInterval("updater")
        AppUpdater.start()
        Signposts.launch.endInterval("updater", updating)
        installMainMenu()
        followColorScheme()
        // before anything reads the socket path: the fake engine's home becomes CARRIER_HOME
        if let fixtures = Self.fixturesPath() { startFixtureMode(fixtures) } else {
            // before the models and the terminal shim are written in it
            prepareAppCache(CarrierPlaces())
            // Apple's recognizer, which the box's microphone needs: it appears once the system has said which languages it supports; FluidAudio's and Whisper's follow
            Task {
                Signposts.launch.emitEvent("recognizers task")
                if let apple = await AppleRecognizer.make() { RecognizerRegistry.shared.register(apple) }
                RecognizerRegistry.shared.register(FluidAudioRecognizer(modelsRoot: dictationModelsRoot()))
                RecognizerRegistry.shared.register(WhisperKitRecognizer(modelsRoot: dictationModelsRoot()))
                // the chosen model loads in the background now, so the first dictation does not wait for it; a self-test or a smoke run loads nothing
                if Self.selfTestPath() == nil, CommandLine.arguments.contains("--smoke-window") == false { DictationController.shared.warmUp() }
            }
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        IconController.install(on: item)
        // a self-test or a smoke run keeps nothing awake and takes no key of the Mac
        if Self.selfTestPath() == nil, CommandLine.arguments.contains("--smoke-window") == false {
            KeepAwakeController.shared.onChange = { IconController.shared?.setAwake($0.holds) }
            KeepAwakeController.shared.start()
        }
        if isDevBuild { NSApp.dockTile.badgeLabel = "DEV" }

        UserDefaults.standard.register(defaults: [showEpicsKey: true])
        let menu = NSMenu()
        menu.delegate = EpicMenuSection.shared
        // the groups (Sessions, Terminals, Dictation: StatusMenuGroups) go before the Sleep row
        KeepAwakeMenu.shared.install(in: menu)
        menu.addItem(.separator())
        // the Carrier group: its title like the other groups', the state (a view of its own, not a title: a line with no action is drawn grey),
        // its controls and its latest epics, which EpicMenuSection puts before the separator that ends the group
        menu.addItem(.sectionHeader(title: "Carrier"))
        let stateLine = menu.addItem(withTitle: ConnectionState.stopped.menuLine, action: nil, keyEquivalent: "")
        stateLine.view = header
        header.show(ConnectionState.stopped.menuStatus)
        MenuControls.shared.install(in: menu)
        let groupEnd = NSMenuItem.separator()
        groupEnd.tag = EpicMenuSection.anchorTag
        menu.addItem(groupEnd)
        // the first touch of the window controller builds the panel's model, the epic store and the agent offers
        let windowController = Signposts.launch.beginInterval("window controller")
        WindowController.shared.addMenuItem(to: menu)
        Signposts.launch.endInterval("window controller", windowController)
        WindowController.shared.addSettingsItem(to: menu)
        WindowController.shared.addAboutItem(to: menu)
        let quit = menu.addItem(withTitle: "Quit Carrier", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        showIcon("power", on: quit)
        item.menu = menu
        statusItem = item
        watchCarrier(stateLine)
        SystemNotificationCentre.shared.attachDelegate()
        // the shortcut of the global dictation; a self-test or a smoke run takes no key of the Mac
        if Self.selfTestPath() == nil, CommandLine.arguments.contains("--smoke-window") == false {
            let dictation = Signposts.launch.beginInterval("dictation")
            GlobalDictationController.shared.start()
            DictationController.shared.startAudioSweep()
            Signposts.launch.endInterval("dictation", dictation)
        }
        // the Notifications page writes user defaults: the badge follows its switch at once
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            // every write to user defaults lands here: the events count them
            Signposts.render.emitEvent("defaults changed")
            NotificationWatcher.app.refreshBadge()
            // the Keybindings page writes user defaults: the menu carries the new keys at once
            self?.rebuildMainMenuIfShortcutsChanged()
        }
        // the host starts when the app opens, once the settings are known; the self-test only checks what would run
        let underSelfTest = CommandLine.arguments.contains("--selftest")
        SetupController.shared.detectIfFirstLaunch {
            guard underSelfTest == false else { return }
            // once the host answers (or was just started), ask how the machine is
            ChatHostStarter.shared.checkAtOpen { answers in
                WindowController.shared.chatHostChecked()
                // what each provider offers is read and kept now, so the first draft lists it at once
                if answers { Task { @MainActor in await AgentOfferStore.shared.warm(host: SocketChatHost()) } }
                Task { @MainActor in
                    await AppHealth.store.check(.open)
                    await AppHealth.providers.createFileIfMissing()
                    // with a file there it did not ask: ask now, so the Providers page opens with its tools already listed
                    if case .unasked = AppHealth.providers.outcome { await AppHealth.providers.load() }
                }
            }
        }

        if CommandLine.arguments.contains("--smoke-window") {
            WindowController.shared.open()
            // with a Carrier to ask (a fixture, say) an epic's view is shown, so its pipeline's scroll pocket is in the report
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { WindowController.shared.selectFirstEpic() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                print(WindowController.shared.structure)
                WindowController.shared.selectFirstSession()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
                Task { @MainActor in
                    print(await WindowController.shared.chatStructure())
                    print(await WindowController.shared.newSessionStructure())
                    WindowController.shared.selectArchive()
                }
            }
            // the Archive page on screen: its line and the layout again
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.5) {
                print(WindowController.shared.archiveStructure)
                Task { @MainActor in
                    print(await WindowController.shared.minimumSizeReport())
                    exit(0)
                }
            }
        }
        if let path = Self.selfTestPath() {
            selfTest(logPath: path)
        } else if CommandLine.arguments.contains("--smoke-window") == false {
            // an app opens on its window
            let opening = Signposts.launch.beginInterval("open window")
            WindowController.shared.open()
            Signposts.launch.endInterval("open window", opening)
        }
        // the reports belong to the real app: a fixture, a self-test and a smoke run leave none
        if Self.fixturesPath() == nil, Self.selfTestPath() == nil, CommandLine.arguments.contains("--smoke-window") == false {
            let metrics = Signposts.launch.beginInterval("metrics")
            MetricsSink.shared.start()
            Signposts.launch.endInterval("metrics", metrics)
        }
    }

    /// A click on the Dock icon with no window open opens it.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if flag == false { WindowController.shared.open() }
        return true
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? { dockMenu() }

    /// Keeps the menu line current from a thread of its own; the title is set on the main queue, which also runs while the menu is open.
    private func watchCarrier(_ line: NSMenuItem) {
        let monitor = ControlMonitor(socketPath: { controlSocketPath() }, pollEvery: { PollPace.shared.seconds }) { state in
            DispatchQueue.main.async {
                IconController.shared?.show(state)
                MainActor.assumeIsolated { KeepAwakeController.shared.epics(working: IconState(state).working) }
                line.title = state.menuLine
                self.header.show(state.menuStatus)
                MenuControls.shared.react(to: state)
                EpicMenuSection.shared.react(to: state)
                NotificationWatcher.app.react(to: state)
                self.startOnOpen(firstState: state)
            }
        }
        Thread.detachNewThread { monitor.run() }
        watchChatSessions()
        // the app lives on with its window closed, so a timer here is enough for the reminders
        let reminders = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in NotificationWatcher.app.remind() }
        // a reminder is not due to the second: the system may fold this wake-up into others
        reminders.tolerance = 10
        // the pace of the asks follows whether someone is looking: the app active with its window on screen
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { WindowController.shared.refreshPace() }
            }
        }
        // and whether the Mac is asleep, or in Low Power Mode, which asks even less often
        let workspace = NSWorkspace.shared.notificationCenter
        let sleeps: [(Notification.Name, Notification.Name, String)] = [
            (NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification, "screens"),
            (NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification, "system"),
            (NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification, "session"),
        ]
        for (start, end, reason) in sleeps {
            workspace.addObserver(forName: start, object: nil, queue: .main) { _ in MainActor.assumeIsolated { WindowController.shared.sleeping(reason, true) } }
            workspace.addObserver(forName: end, object: nil, queue: .main) { _ in MainActor.assumeIsolated { WindowController.shared.sleeping(reason, false) } }
        }
        NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { WindowController.shared.refreshPace() }
        }
    }

    /// The chat sessions notify with the window closed, so they are read for the life of the app, beside the engine's monitor. A host
    /// that does not answer (not started yet, or stopped) is not an event: the link tells it once, and the last list is kept and the next answer is compared to it.
    private func watchChatSessions() {
        let host = SocketChatHost()
        Task.detached {
            for await update in await host.sessionUpdates() {
                guard update.stale == false else {
                    // a host that is not there works on nothing: its last list must not keep the Mac awake
                    await MainActor.run { KeepAwakeController.shared.sessions(working: 0) }
                    continue
                }
                let rows = sessionRows(update.active)
                await MainActor.run {
                    NotificationWatcher.app.react(toSessions: rows)
                    StatusMenuGroups.shared.react(toSessions: rows)
                    KeepAwakeController.shared.sessions(working: rows.filter(\.isWorking).count)
                }
            }
        }
    }

    /// The person's standing choice: start Carrier once when the app opens and finds it stopped.
    private func startOnOpen(firstState state: ConnectionState) {
        let tried = triedStartOnOpen
        triedStartOnOpen = true
        guard shouldStartOnOpen(
            enabled: UserDefaults.standard.bool(forKey: startOnOpenKey), firstState: state,
            startReady: StartController.shared.missing.isEmpty && StartController.shared.refreshConfig(), fixture: fixtureServer != nil, alreadyTried: tried
        ) else { return }
        StartController.shared.start()
    }

    /// Coming back from Terminal, where the person may have just logged in or installed `carrier`, asks again. `carrier` is looked for on
    /// the disk each time, so a host that could not start for lack of it starts now, without a restart.
    func applicationDidBecomeActive(_ notification: Notification) {
        if ChatHostStarter.shared.missing.isEmpty {
            Task { @MainActor in await AppHealth.store.check(.active) }
        } else {
            ChatHostStarter.shared.checkAtOpen { _ in Task { @MainActor in await AppHealth.store.check(.active) } }
        }
    }

    // A menu bar app keeps running with no windows.
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard fixtureServer == nil, Self.selfTestPath() == nil else { return .terminateNow }
        return MainActor.assumeIsolated {
            guard isConfirmingTermination == false else { return .terminateCancel }
            guard let store = CarrierTerminalStore.sharedIfInitialized, store.hasLiveSurfaces else {
                return .terminateNow
            }
            isConfirmingTermination = true
            Task { @MainActor [weak self] in
                defer { self?.isConfirmingTermination = false }
                let question = await store.pendingConfirmation(for: .all)
                let shouldTerminate = question.map(ask) ?? true
                sender.reply(toApplicationShouldTerminate: shouldTerminate)
            }
            return .terminateLater
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { CarrierTerminalStore.sharedIfInitialized?.teardownAll() }
        fixtureServer?.stop()
    }

    /// `--fixture [folder]`: the folder of golden files, by default the ones inside the app bundle. nil without the flag.
    private static func fixturesPath() -> String? {
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
    private func startFixtureMode(_ fixtures: String) {
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
            UserDefaults.standard.set(storedPins(Set(server.pinnedSessionIds)), forKey: SidebarStore.pinnedKey)
            let recognizer = FixtureRecognizer(mode: Self.fixtureDictationMode)
            MainActor.assumeIsolated { RecognizerRegistry.shared.register(recognizer) }
        } catch {
            FileHandle.standardError.write(Data("carrier: --fixture failed: \(error)\n".utf8))
            exit(1)
        }
    }

    /// The value after `--selftest`, if there is one.
    private static func selfTestPath() -> String? {
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
    private func selfTest(logPath: String) {
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
                return "\(menu.item(withTitle: "Quit Carrier")?.isEnabled == true)"
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
                ("settings page \(page.rawValue)", { WindowController.shared.showSettings(page); return WindowController.shared.settingsStatus })
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
            steps.insert(contentsOf: pages + screens + roles, at: opened + 1)
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

/// Set by build-app.sh when no version is given: this is a development build, not the installed Carrier.
let isDevBuild = Bundle.main.object(forInfoDictionaryKey: "CarrierChannel") as? String == "dev"
