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
        DispatchQueue.global().async {
            let answers = ControlClient.connect(path: socket) != nil
            DispatchQueue.main.async {
                let decision = chatHostAtOpen(
                    settings: settings, hostAnswers: answers, startRunning: self.starting, fixture: CommandLine.arguments.contains("--fixture")
                )
                self.missing = if case .missing(let names) = decision { names } else { [] }
                switch decision {
                case .leave: done(answers)
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
}
