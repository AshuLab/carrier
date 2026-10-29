import Foundation

// Starting the chat host from the app, the way `StartCarrier.swift` starts the engine: same command shape, same `PATH`, same
// outcome and alert. Only a session being started asks for it, never the app opening. The spawn lives in the shell.

/// What the settings lack to start the chat host: it needs no config path.
public func chatHostMissing(_ settings: SetupSettings) -> [String] {
    [("node", settings.node), ("carrier", settings.carrier)].filter { $0.1.isEmpty }.map(\.0)
}

/// `node <carrier> chat-host` with `CARRIER_HOME` set to the Carrier folder, its log in `<folder>/chat/logs/app-start.log`.
/// nil when `chatHostMissing` is not empty.
public func startChatHostCommand(settings: SetupSettings, environment: [String: String], home: String = NSHomeDirectory()) -> StartCommand? {
    guard chatHostMissing(settings).isEmpty else { return nil }
    let folder = carrierFolder(environment: environment, home: home)
    var environment = environment
    environment["PATH"] = enginePath(detected: settings.path, node: settings.node)
    environment["CARRIER_HOME"] = folder
    let chat = folder + "/chat"
    return StartCommand(
        node: settings.node, arguments: [settings.carrier, "chat-host"], environment: environment,
        orchestratorDir: chat, logPath: chat + "/logs/app-start.log", socketPath: chat + "/state/chat.sock"
    )
}

/// Whether to start the host now: a session is being started, the host does not answer, no start is running, and the app is
/// not under `--fixture` (its fake host answers, and a real one must never start there).
public func shouldStartChatHost(startingSession: Bool, hostAnswers: Bool, startRunning: Bool, fixture: Bool) -> Bool {
    startingSession && hostAnswers == false && startRunning == false && fixture == false
}
