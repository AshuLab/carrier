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
    /// The installed `carrier` is asked its version once per launch.
    private var versionChecked = false

    /// At open, and again when the Settings window closes: starts the host if it does not answer. With `node` or `carrier`
    /// missing there is no alert, only `missing`; a start that fails keeps the alert.
    func checkAtOpen() { run(alertWhenMissing: false) { _ in } }

    /// A session is being started: `done` is called on the main thread with whether the host answers, so the session can go on;
    /// false after the alert.
    func ensureRunning(done: @escaping (Bool) -> Void) { run(alertWhenMissing: true, done: done) }

    private func run(alertWhenMissing: Bool, done: @escaping (Bool) -> Void) {
        let settings = SetupController.shared.settings
        let command = startChatHostCommand(settings: settings, environment: ProcessInfo.processInfo.environment)
        // the socket asked here and the one the start waits on are the same: the Carrier folder decides both
        let socket = command?.socketPath ?? chatSocketPath()
        let fixture = CommandLine.arguments.contains("--fixture")
        DispatchQueue.global().async {
            let answers = ControlClient.connect(path: socket) != nil
            DispatchQueue.main.async {
                let decision = chatHostAtOpen(
                    settings: settings, hostAnswers: answers, startRunning: self.starting, fixture: fixture
                )
                self.missing = if case .missing(let names) = decision { names } else { [] }
                if answers == false { self.restartAdvised = false }
                switch decision {
                case .leave:
                    if answers, self.versionChecked == false, self.starting == false, fixture == false, let command {
                        self.versionChecked = true
                        self.replaceIfOlder(command)
                    }
                    done(answers)
                case .missing(let names):
                    if alertWhenMissing {
                        let list = names.joined(separator: ", ")
                        FileHandle.standardError.write(Data("carrier: the chat host was not started, the settings lack: \(list)\n".utf8))
                        StartController.showAlert(title: "The chat host did not start", reason: "The settings lack: \(list).", tail: "")
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
                            done(failure == nil)
                        }
                    }
                }
            }
        }
    }

    /// A host that answers while the installed `carrier` is newer is replaced when no session is working or waiting, and otherwise
    /// left running with a notice. Anything that cannot be read leaves it alone, and says so in the log.
    private func replaceIfOlder(_ command: StartCommand) {
        Task.detached {
            guard let installed = Self.installedVersion(command) else { return }
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
            case .askRestart: await MainActor.run { self.restartAdvised = true }
            case .replace: await self.replace(command)
            }
        }
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
        await MainActor.run {
            self.starting = false
            if let failure { StartController.showAlert(title: "The chat host did not start", reason: failure.reason, tail: failure.tail) }
        }
    }

    /// What `carrier --version` prints; nil, with the reason in the log, when the command fails or prints something else.
    private static func installedVersion(_ command: StartCommand) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.node)
        process.arguments = [command.arguments[0], "--version"]
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
