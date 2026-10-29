import Foundation

// Starting Carrier from the app: the command line and environment it runs with, and the decision about how the start went.
// The spawn itself (its own session, stdin from /dev/null, output to the log) lives in the shell.

/// How long the socket has to answer after the process starts.
public let startTimeout: TimeInterval = 15

/// What the shell spawns: `node <carrier> ...` with the engine's PATH and `CARRIER_HOME`, its output going to `logPath`. `orchestratorDir` is the
/// user-only folder the log's folder lives in (the engine's `engine/`, the chat host's `chat/`).
public struct StartCommand: Equatable {
    public let node: String
    public let arguments: [String]
    public let environment: [String: String]
    public let orchestratorDir: String
    public let logPath: String
    public let socketPath: String

    public var logsDir: String { (logPath as NSString).deletingLastPathComponent }
}

/// What the settings lack to start Carrier.
public func startMissing(_ settings: SetupSettings) -> [String] {
    [("node", settings.node), ("carrier", settings.carrier)].filter { $0.1.isEmpty }.map(\.0)
}

/// nil when `startMissing` is not empty. The engine finds its config, logs and socket from `CARRIER_HOME`, which is set to the
/// Carrier folder (the app's own environment's, else `~/.carrier`); the log and the socket are in the folder's `engine/`.
/// `environment` is the app's own; its PATH is replaced.
public func startCommand(settings: SetupSettings, environment: [String: String], home: String = NSHomeDirectory()) -> StartCommand? {
    guard startMissing(settings).isEmpty else { return nil }
    let folder = carrierFolder(environment: environment, home: home)
    var environment = environment
    environment["PATH"] = enginePath(detected: settings.path, node: settings.node)
    environment["CARRIER_HOME"] = folder
    let engine = folder + "/engine"
    return StartCommand(
        node: settings.node, arguments: [settings.carrier], environment: environment,
        orchestratorDir: engine, logPath: engine + "/logs/app-start.log", socketPath: engine + "/state/control.sock"
    )
}

public enum StartFailure: Equatable {
    case exited(Int32)
    case noSocket
}

public enum StartOutcome: Equatable {
    case running
    case failed(StartFailure)
}

/// How the start stands, from what is known now: the process's exit code (nil while it runs), whether the socket answers,
/// and the seconds since it was spawned. nil means keep waiting. A socket that answers wins over everything, also over an
/// exit: the process may have quit because another Carrier already held the folder, and that one is the running one.
public func startOutcome(exitCode: Int32?, socketAnswered: Bool, elapsed: TimeInterval) -> StartOutcome? {
    if socketAnswered { return .running }
    // also code 0: a Carrier that ended cleanly before opening its socket did not come up
    if let exitCode { return .failed(.exited(exitCode)) }
    return elapsed >= startTimeout ? .failed(.noSocket) : nil
}

public func startFailureText(_ failure: StartFailure, name: String = "Carrier") -> String {
    switch failure {
    case .exited(let code): return "\(name) exited with code \(code) before it opened its control socket."
    case .noSocket: return "\(name) did not open its control socket within \(Int(startTimeout)) seconds. It may still be running."
    }
}

/// The last `lines` lines of the start log, for the alert.
public func logTail(_ log: Data, lines: Int = 30) -> String {
    let text = String(decoding: log, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    let tail = text.split(separator: "\n", omittingEmptySubsequences: false).suffix(lines)
    return text.isEmpty ? "(the start log is empty)" : tail.joined(separator: "\n")
}

/// The Start Carrier menu item: it can be pressed only while Carrier is stopped, the settings are complete and no start is
/// under way; otherwise the title says what is missing or that it is starting.
public func startMenuState(state: ConnectionState, starting: Bool, missing: [String]) -> (title: String, enabled: Bool) {
    if starting { return ("Starting Carrier…", false) }
    guard state == .stopped else { return ("Start Carrier", false) }
    if missing.isEmpty { return ("Start Carrier", true) }
    return ("Start Carrier (missing: \(missing.joined(separator: ", ")))", false)
}

/// The user default behind "Start Carrier when the app opens"; false when unset.
public let startOnOpenKey = "engine.startOnOpen"

/// Whether opening the app starts Carrier: the person asked for it, the first state the monitor delivered is stopped, Start
/// Carrier is enabled, it is not `--fixture`, and this launch has not looked yet.
public func shouldStartOnOpen(enabled: Bool, firstState: ConnectionState, startReady: Bool, fixture: Bool, alreadyTried: Bool) -> Bool {
    enabled && firstState == .stopped && startReady && fixture == false && alreadyTried == false
}
