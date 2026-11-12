import AppKit
import CarrierCore
import Observation

/// Starts the chat host when the app opens and when a session is being started, the way `StartController` starts the engine
/// (and through its spawn, wait and alert). Called on the main thread; a second call while a start runs does nothing.
@Observable final class ChatHostStarter {
    static let shared = ChatHostStarter()

    private var starting = false
    /// What the settings lack while the host could not be started for it, which the Sessions section and the Sessions home say.
    private(set) var missing: [String] = []
    /// An older host is left running because a session is working: the Sessions section and the Sessions home say to restart it.
    private(set) var restartAdvised = false
    /// Where the upgrade of the installed `carrier` stands. A failure changed nothing and is not retried by itself: the Updates page has a button.
    private(set) var engineUpdate = EngineUpdateState.unknown
    /// Why the installed `carrier` older than the app could not be upgraded with Homebrew.
    var upgradeNotice: ChatHostNotice? { engineUpdate.notice }
    /// What the last version check used, so the button can look again.
    private var lastCheck: (command: StartCommand, homebrews: Bool)?
    /// The installed `carrier` is asked its version once per launch.
    private var versionChecked = false

    /// At open, and again when the Settings window closes: starts the host if it does not answer. With `node` or `carrier`
    /// missing there is no alert, only `missing`; a start that fails keeps the alert.
    func checkAtOpen(done: @escaping (Bool) -> Void = { _ in }) { run(alertWhenMissing: false, done: done) }

    /// A session is being started: `done` is called on the main thread with whether the host answers, so the session can go on;
    /// false after the alert.
    func ensureRunning(done: @escaping (Bool) -> Void) { run(alertWhenMissing: true, done: done) }

    private func run(alertWhenMissing: Bool, done: @escaping (Bool) -> Void) {
        let settings = SetupController.shared.settings, carrier = SetupController.shared.carrier
        let command = startChatHostCommand(settings: settings, carrier: carrier, environment: ProcessInfo.processInfo.environment)
        // the socket asked here and the one the start waits on are the same: the Carrier folder decides both
        let socket = command?.socketPath ?? chatSocketPath()
        let fixture = CommandLine.arguments.contains("--fixture")
        let homebrews = carrier == homebrewCarrier
        DispatchQueue.global().async {
            let answers = ControlClient.connect(path: socket) != nil
            DispatchQueue.main.async {
                let decision = chatHostAtOpen(
                    settings: settings, carrier: carrier, hostAnswers: answers, startRunning: self.starting, fixture: fixture
                )
                self.missing = if case .missing(let names) = decision { names } else { [] }
                if answers == false { self.restartAdvised = false }
                switch decision {
                case .leave:
                    if answers, self.versionChecked == false, self.starting == false, fixture == false, let command {
                        self.versionChecked = true
                        self.replaceIfOlder(command, homebrews: homebrews)
                    }
                    done(answers)
                case .missing(let names):
                    if alertWhenMissing {
                        let notice = chatHostNotice(missing: names)
                        FileHandle.standardError.write(Data("carrier: the chat host was not started, missing: \(names.joined(separator: ", "))\n".utf8))
                        StartController.showAlert(title: "The chat host did not start", reason: notice?.line ?? "", tail: "")
                    }
                    done(false)
                case .start:
                    guard let command else { done(false); return }
                    self.starting = true
                    DispatchQueue.global().async {
                        let failure = StartController.launch(command, name: "The chat host")
                        DispatchQueue.main.async {
                            self.starting = false
                            if let failure { StartController.showAlert(title: "The chat host did not start", reason: failure.reason, tail: failure.tail) }
                            // a host the app just started runs the installed `carrier`, which may be the one to upgrade
                            if failure == nil, self.versionChecked == false, fixture == false {
                                self.versionChecked = true
                                self.replaceIfOlder(command, homebrews: homebrews)
                            }
                            done(failure == nil)
                        }
                    }
                }
            }
        }
    }

    /// A host that answers while the installed `carrier` is newer is replaced when no session is working or waiting, and otherwise
    /// left running with a notice. Anything that cannot be read leaves it alone, and says so in the log. Before that, a Homebrew
    /// `carrier` older than the app is upgraded and its version read again. After the host, the engine gets the same comparison.
    private func replaceIfOlder(_ command: StartCommand, homebrews: Bool) {
        lastCheck = (command, homebrews)
        Task.detached {
            guard var installed = Self.installedVersion(command) else { return }
            let app = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            if homebrews, CommandLine.arguments.contains("--selftest") == false {
                if carrierIsOlder(installed: installed, app: app) {
                    await MainActor.run { self.engineUpdate = .running }
                    BrewRunner.startLog()
                    switch upgradeCarrier(installed: installed, app: app, brew: BrewRunner.run) {
                    case .notNeeded: await MainActor.run { self.engineUpdate = .upToDate }
                    case .upgraded:
                        guard let again = Self.installedVersion(command) else { return }
                        installed = again
                        await MainActor.run { self.engineUpdate = .updated }
                    case .failed(let notice):
                        FileHandle.standardError.write(Data("carrier: the installed carrier was not upgraded, see \(BrewRunner.logPath)\n".utf8))
                        await MainActor.run { self.engineUpdate = .failed(notice) }
                        return
                    }
                } else {
                    await MainActor.run { self.engineUpdate = .upToDate }
                }
            }
            await self.replaceHostIfOlder(command, installed: installed)
            await self.replaceEngineIfOlder(installed: installed)
        }
    }

    /// The Updates page's button after a failure: looks at the installed `carrier` again and upgrades it if it is still older.
    /// Nothing happens while an upgrade runs.
    func retryUpgrade() {
        guard engineUpdate.canRetry, let lastCheck else { return }
        replaceIfOlder(lastCheck.command, homebrews: lastCheck.homebrews)
    }

    private func replaceHostIfOlder(_ command: StartCommand, installed: String) async {
        guard let client = ControlClient.connect(path: command.socketPath) else { return }
        let running = (try? client.hello())?.version ?? ""
        client.close()
        let sessions: [ChatSession]
        do { sessions = try await SocketChatHost(socketPath: { command.socketPath }).list(archived: false) } catch {
            FileHandle.standardError.write(Data("carrier: the chat host was left alone, its sessions could not be listed: \(error)\n".utf8))
            return
        }
        // ponytail: a session that starts working between the list and the stop is closed with the host; a guard in the host if it bites
        switch hostReplacement(running: running, installed: installed, working: sessions.contains { $0.state != .idle }) {
        case .keep: break
        case .askRestart: await MainActor.run { restartAdvised = true }
        case .replace: await replace(command)
        }
    }

    /// An engine that is running and older than the installed `carrier` is replaced once it is free; one that is stopped stays so.
    /// A failed start shows the engine's own alert.
    private func replaceEngineIfOlder(installed: String) async {
        let result = await replaceEngine(
            socketPath: controlSocketPath(), installed: installed,
            beforeStop: { NotificationWatcher.app.expectStop() },
            start: { await withCheckedContinuation { next in DispatchQueue.main.async { StartController.shared.start { next.resume(returning: $0) } } } }
        )
        if case .failed(let reason) = result { FileHandle.standardError.write(Data("carrier: the older engine was not replaced: \(reason)\n".utf8)) }
    }

    /// Stops the host, waits for its socket to go, starts the installed one; a failed start keeps the alert. A start that is already
    /// running (the host went away while the version was read) leaves nothing to replace.
    private func replace(_ command: StartCommand) async {
        let free = await MainActor.run { () -> Bool in
            guard self.starting == false else { return false }
            self.starting = true
            return true
        }
        guard free else { return }
        var failure: (reason: String, tail: String)?
        do {
            try send(.stop, socketPath: command.socketPath)
            // ponytail: polls the socket for 15 s, as the engine's restart does
            let deadline = Date().addingTimeInterval(15)
            while ControlClient.connect(path: command.socketPath) != nil, Date() < deadline { try await Task.sleep(for: .milliseconds(250)) }
            failure = StartController.launch(command, name: "The chat host")
        } catch {
            FileHandle.standardError.write(Data("carrier: the older chat host was not replaced: \(error)\n".utf8))
        }
        let failed = failure
        await MainActor.run {
            self.starting = false
            if let failure = failed { StartController.showAlert(title: "The chat host did not start", reason: failure.reason, tail: failure.tail) }
        }
    }

    /// What `carrier --version` prints; nil, with the reason in the log, when the command fails or prints something else.
    static func installedVersion(_ command: StartCommand) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.program)
        // the chat host's own arguments end with its subcommand; what comes before it (the script, for a `node` start) stays
        process.arguments = command.arguments.dropLast() + ["--version"]
        process.environment = command.environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
            // ponytail: a `carrier` that hangs is ended after 5 s (killed 1 s later); a grandchild holding the pipe open could still block the read
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                guard process.isRunning else { return }
                process.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
            }
            let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            if process.terminationStatus == 0, versionNumbers(text) != nil { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
            let how = process.terminationReason == .uncaughtSignal ? "did not answer in 5 seconds and was ended" : "failed (exit \(process.terminationStatus)) or printed something else"
            FileHandle.standardError.write(Data("carrier: the chat host was left alone, `carrier --version` \(how)\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("carrier: the chat host was left alone, `carrier --version` could not run: \(error)\n".utf8))
        }
        return nil
    }
}
