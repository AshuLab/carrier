import Foundation

// Starting the chat host from the app, the way `StartCarrier.swift` starts the engine: same command shape, same `PATH`, same
// outcome and alert. Only a session being started asks for it, never the app opening. The spawn lives in the shell.

/// `node <carrier> chat-host --config <config path>`, its log in `<root>/chat/logs/app-start.log`. nil when `startMissing` is not empty.
public func startChatHostCommand(settings: SetupSettings, root: String, environment: [String: String]) -> StartCommand? {
    guard let engine = startCommand(settings: settings, root: root, environment: environment) else { return nil }
    let chat = root + "/chat"
    return StartCommand(
        node: engine.node, arguments: [settings.carrier, "chat-host", "--config", settings.configPath], environment: engine.environment,
        orchestratorDir: chat, logPath: chat + "/logs/app-start.log", socketPath: chat + "/chat.sock"
    )
}

/// Whether to start the host now: a session is being started, the host does not answer, no start is running, and the app is
/// not under `--fixture` (its fake host answers, and a real one must never start there).
public func shouldStartChatHost(startingSession: Bool, hostAnswers: Bool, startRunning: Bool, fixture: Bool) -> Bool {
    startingSession && hostAnswers == false && startRunning == false && fixture == false
}
