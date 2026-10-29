import AppKit
import CarrierCore

/// The menu's controls: pause or resume intake, check GitHub now, stop Carrier. All on the main thread, except the
/// sending, which blocks on the socket and so runs on a queue of its own.
/// The symbol beside a menu item, in `color` when it has one. macOS 27 hides menu item images unless each item asks to show its own.
func showIcon(_ symbol: String, on item: NSMenuItem, color: NSColor? = nil) {
    let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    item.image = color.map { image?.withSymbolConfiguration(.init(paletteColors: [$0])) } ?? image
    if #available(macOS 27.0, *) { item.preferredImageVisibility = .visible }
}

final class MenuControls: NSObject, NSMenuItemValidation {
    static let shared = MenuControls()

    private var socketPath: String { controlSocketPath() }
    private let pauseItem = NSMenuItem(title: "Pause intake", action: #selector(pauseOrResume), keyEquivalent: "")
    private let checkItem = NSMenuItem(title: "Check GitHub now", action: #selector(checkNow), keyEquivalent: "")
    private let stopItem = NSMenuItem(title: "Stop Carrier", action: #selector(stopCarrier), keyEquivalent: "")
    private let startMenuItem = NSMenuItem(title: "Start Carrier", action: #selector(startCarrier), keyEquivalent: "")
    private var state = ConnectionState.stopped
    private var wasPausedAtSelfTest = false
    private var reviewTabCheck = CheckThrottle()

    /// Adds the four items at the end of `menu`; `react` shows the ones that make sense.
    func install(in menu: NSMenu) {
        for (item, symbol) in [(startMenuItem, "play.fill"), (pauseItem, "pause.fill"), (checkItem, "arrow.clockwise"), (stopItem, "stop.fill")] {
            item.target = self
            showIcon(symbol, on: item)
            menu.addItem(item)
        }
        react(to: state)
    }

    /// The latest state of Carrier: Start shows while it is not running, the other three while it is, and the pause item says
    /// what clicking it would do.
    func react(to state: ConnectionState) {
        self.state = state
        let running = isRunning
        startMenuItem.isHidden = running
        for item in [pauseItem, checkItem, stopItem] { item.isHidden = running == false }
        pauseItem.title = paused ? "Resume intake" : "Pause intake"
        showIcon(paused ? "play.fill" : "pause.fill", on: pauseItem)
    }

    /// Enabled only while Carrier is running and compatible; a stopped or incompatible one has nothing to listen.
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item === startMenuItem {
            // the settings can change while the menu is closed, so the title is worked out each time it opens
            let start = startMenuState(state: state, starting: StartController.shared.starting, missing: StartController.shared.missing,
                configExists: StartController.shared.refreshConfig())
            item.title = start.title
            return start.enabled
        }
        if case .running = state { return true }
        return false
    }

    private var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    private var paused: Bool {
        if case .running(let snapshot) = state { return snapshot.paused }
        return false
    }

    @objc private func startCarrier() { StartController.shared.start() }

    @objc func pauseOrResume() { sendInBackground(paused ? .resume : .pause) }

    @objc func checkNow() { sendInBackground(.checkNow) }

    /// The Review tab opened: its threads are as old as the last poll, so GitHub is checked now (at most every thirty seconds).
    func reviewTabOpened() {
        guard case .running = state, reviewTabCheck.take() else { return }
        checkNow()
    }

    @objc func stopCarrier() {
        guard case .running(let snapshot) = state else { return }
        if asksBeforeStopping(snapshot, switchOn: UserDefaults.standard.object(forKey: confirmStopKey) as? Bool ?? true) {
            guard confirmStop(interrupting: snapshot.runningEpics) else { return }
        }
        NotificationWatcher.app.expectStop()
        sendInBackground(.stop)
    }

    private func confirmStop(interrupting running: Int) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Stop Carrier?"
        alert.informativeText = "\(running) \(running == 1 ? "epic" : "epics") will be interrupted. "
            + "\(running == 1 ? "It resumes" : "They resume") on the next start, but what \(running == 1 ? "it was" : "they were") doing right now is lost."
        alert.addButton(withTitle: "Stop Carrier")
        alert.addButton(withTitle: "Cancel")
        // an accessory app is not frontmost, and its alert would open behind the other windows
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func sendInBackground(_ command: Command) {
        let path = socketPath
        DispatchQueue.global().async {
            do { try send(command, socketPath: path) } catch {
                FileHandle.standardError.write(Data("carrier: \(command.rawValue) failed: \(error)\n".utf8))
            }
        }
    }

    /// What the self-test logs for one action. Pause and resume are sent, resume putting back what was there before the
    /// test; check now is sent; stop is only checked, like Quit: sent, it would end the Carrier under test.
    func selfTest(_ command: Command) -> String {
        // the start is only checked, like stop: pressing it would start the real Carrier
        let start = command == .stop ? "; " + StartController.shared.selfTest(state: state) : ""
        guard case .running(let snapshot) = state else { return "disabled, Carrier is not running" + start }
        var command = command
        switch command {
        case .pause: wasPausedAtSelfTest = snapshot.paused
        case .resume: command = wasPausedAtSelfTest ? .pause : .resume
        case .stop: return "enabled, would ask first: \(snapshot.stopNeedsConfirmation), epics running: \(snapshot.runningEpics)" + start
        case .checkNow: break
        }
        do {
            try send(command, socketPath: socketPath)
            return "sent \(command.rawValue)"
        } catch {
            return "\(command.rawValue) failed: \(error)"
        }
    }
}
