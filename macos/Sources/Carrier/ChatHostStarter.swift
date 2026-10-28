import AppKit
import CarrierCore

/// Starts the chat host when a session is being started and it is not there, the way `StartController` starts the engine
/// (and through its spawn, wait and alert). Called on the main thread; a second call while a start runs does nothing.
final class ChatHostStarter {
    static let shared = ChatHostStarter()

    private var starting = false

    /// `done` is called on the main thread with whether the host answers, so the session can go on; false after the alert.
    func ensureRunning(done: @escaping (Bool) -> Void) {
        let settings = SetupController.shared.settings
        let root = configRoot(configPath: settings.configPath, home: NSHomeDirectory())
        let command = startChatHostCommand(settings: settings, root: root, environment: ProcessInfo.processInfo.environment)
        let socket = chatSocketPath()
        DispatchQueue.global().async {
            let answers = ControlClient.connect(path: socket) != nil
            DispatchQueue.main.async {
                let start = shouldStartChatHost(
                    startingSession: true, hostAnswers: answers, startRunning: self.starting, fixture: CommandLine.arguments.contains("--fixture")
                )
                guard start, let command else { done(answers); return }
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
