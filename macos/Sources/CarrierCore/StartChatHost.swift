import Foundation

// Starting the chat host from the app, the way `StartCarrier.swift` starts the engine: same command shape, same `PATH`, same
// outcome and alert. The app opening asks for it, and so does a session being started. The spawn lives in the shell.

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

/// What the app does about the chat host when it opens, and when a session is being started: nothing (it answers, a start is
/// running, or the app is under `--fixture`, whose fake host answers and a real one must never start there), start it, or
/// say what the settings lack.
public enum ChatHostAtOpen: Equatable {
    case leave, start, missing([String])
}

public func chatHostAtOpen(settings: SetupSettings, hostAnswers: Bool, startRunning: Bool, fixture: Bool) -> ChatHostAtOpen {
    guard hostAnswers == false, startRunning == false, fixture == false else { return .leave }
    let missing = chatHostMissing(settings)
    return missing.isEmpty ? .start : .missing(missing)
}

/// What the Sessions section and the Sessions home say while the host cannot be started for lack of `node` or `carrier`.
public struct ChatHostNotice: Equatable {
    public var title: String
    public var line: String
}

/// nil when nothing is missing.
public func chatHostNotice(missing: [String]) -> ChatHostNotice? {
    guard missing.isEmpty == false else { return nil }
    let names = missing.joined(separator: " and ")
    return ChatHostNotice(
        title: "The chat host cannot start",
        line: "The app did not find \(names). Install it or set its path in Settings."
    )
}
