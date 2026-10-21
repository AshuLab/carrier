import AppKit
import CarrierCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var fixtureServer: FixtureServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // before anything reads the socket path: the fake engine's home becomes CARRIER_HOME
        if let fixtures = Self.fixturesPath() { startFixtureMode(fixtures) }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        IconController.install(on: item)

        UserDefaults.standard.register(defaults: [showEpicsKey: true])
        let menu = NSMenu()
        menu.delegate = EpicMenuSection.shared
        // no action, so the menu leaves it disabled: a line to read, not a button
        let stateLine = menu.addItem(withTitle: ConnectionState.stopped.menuLine, action: nil, keyEquivalent: "")
        MenuControls.shared.install(in: menu, after: stateLine)
        menu.addItem(.separator())
        WindowController.shared.addMenuItem(to: menu)
        if fixtureServer != nil { EmptyStatesWindowController.shared.addMenuItem(to: menu) }
        SettingsWindowController.shared.addMenuItem(to: menu)
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
        watchCarrier(stateLine)
        SetupController.shared.detectIfFirstLaunch()

        if CommandLine.arguments.contains("--smoke-window") {
            WindowController.shared.open()
            // with a Carrier to ask (a fixture, say) an epic's view is shown, so its pipeline's scroll pocket is in the report
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { WindowController.shared.selectFirstEpic() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                print(WindowController.shared.structure)
                exit(0)
            }
        }
        if let path = Self.selfTestPath() {
            selfTest(logPath: path)
        }
    }

    /// Keeps the menu line current from a thread of its own; the title is set on the main queue, which also runs while the menu is open.
    private func watchCarrier(_ line: NSMenuItem) {
        let monitor = ControlMonitor(socketPath: controlSocketPath()) { state in
            DispatchQueue.main.async {
                IconController.shared?.show(state)
                line.title = state.menuLine
                MenuControls.shared.react(to: state)
                EpicMenuSection.shared.react(to: state)
                NotificationWatcher.app.react(to: state)
            }
        }
        Thread.detachNewThread { monitor.run() }
    }

    // A menu bar app keeps running with no windows.
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) { fixtureServer?.stop() }

    /// `--fixture [folder]`: the folder of golden files, by default the ones inside the app bundle. nil without the flag.
    private static func fixturesPath() -> String? {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--fixture") else { return nil }
        if args.indices.contains(flag + 1), args[flag + 1].hasPrefix("--") == false { return args[flag + 1] }
        return (Bundle.main.resourcePath ?? ".") + "/Fixtures"
    }

    /// Starts the fake engine and points the app at it; with no fixtures to serve the app exits rather than show a stopped Carrier.
    private func startFixtureMode(_ fixtures: String) {
        do {
            let server = try FixtureServer(fixtures: fixtures)
            setenv("CARRIER_HOME", server.home, 1)
            fixtureServer = server
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
        let steps: [(String, () -> String)] = [
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
            ("pause intake", { MenuControls.shared.selfTest(.pause) }),
            ("resume intake", { MenuControls.shared.selfTest(.resume) }),
            ("check GitHub now", { MenuControls.shared.selfTest(.checkNow) }),
            ("stop Carrier", { MenuControls.shared.selfTest(.stop) }),
            ("activation policy accessory", { "\(NSApp.activationPolicy() == .accessory)" }),
            ("setup", { SetupController.shared.summary }),
            ("open settings", { SettingsWindowController.shared.open(); return SettingsWindowController.shared.status }),
            ("close settings", { SettingsWindowController.shared.close(); return SettingsWindowController.shared.status }),
            ("app windows open", { "\(NSApp.windows.filter { $0.isVisible && $0.level != .statusBar }.count)" }),
            ("quit enabled", {
                guard let menu = self.statusItem?.menu else { return "false" }
                menu.update()
                return "\(menu.item(withTitle: "Quit")?.isEnabled == true)"
            }),
            ("open window", { WindowController.shared.open(); return WindowController.shared.status }),
            ("close window", { WindowController.shared.close(); return WindowController.shared.status }),
            ("reopen window", { WindowController.shared.open(); return WindowController.shared.status }),
            ("notifications", { SystemNotificationCentre.selfTestSummary }),
        ]
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
