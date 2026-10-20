import Foundation

// Starting Carrier from the app: the command line and environment it runs with, and the decision about how the start went.
// The spawn itself (its own session, stdin from /dev/null, output to the log) lives in the shell.

/// How long the socket has to answer after the process starts.
public let startTimeout: TimeInterval = 15

/// What the shell spawns: `node <carrier> --config <config path>` with the engine's PATH, its output going to `logPath`.
public struct StartCommand: Equatable {
    public let node: String
    public let arguments: [String]
    public let environment: [String: String]
    public let orchestratorDir: String
    public let logPath: String
    public let socketPath: String

    public var logsDir: String { (logPath as NSString).deletingLastPathComponent }
}

/// What the settings lack to start Carrier. The root is there because the log and the socket live under it.
public func startMissing(_ settings: SetupSettings) -> [String] {
    [("node", settings.node), ("carrier", settings.carrier), ("config path", settings.configPath), ("root", settings.root)]
        .filter { $0.1.isEmpty }.map(\.0)
}

/// nil when `startMissing` is not empty. `environment` is the app's own; only its PATH is replaced.
public func startCommand(settings: SetupSettings, environment: [String: String]) -> StartCommand? {
    guard startMissing(settings).isEmpty else { return nil }
    var environment = environment
    environment["PATH"] = enginePath(detected: settings.path, node: settings.node)
    let orchestrator = settings.root + "/orchestrator"
    return StartCommand(
        node: settings.node, arguments: [settings.carrier, "--config", settings.configPath], environment: environment,
        orchestratorDir: orchestrator, logPath: orchestrator + "/logs/app-start.log", socketPath: orchestrator + "/control.sock"
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

public func startFailureText(_ failure: StartFailure) -> String {
    switch failure {
    case .exited(let code): return "Carrier exited with code \(code) before it opened its control socket."
    case .noSocket: return "Carrier did not open its control socket within \(Int(startTimeout)) seconds. It may still be running."
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
