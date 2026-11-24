import Foundation

// Starting Carrier from the app: the command line and environment it runs with, and the decision about how the start went.
// The spawn itself (its own session, stdin from /dev/null, output to the log) lives in the shell.

/// How long the socket has to answer after the process starts.
public let startTimeout: TimeInterval = 15

/// What the shell spawns: `carrier ...` (or `node <carrier> ...` for a script) with the engine's PATH and `CARRIER_HOME`, its output going to `logPath`. `processDir` is the
/// user-only folder the log's folder lives in (the engine's `engine/`, the chat host's `chat/`).
public struct StartCommand: Equatable {
    public let program: String
    public let arguments: [String]
    public let environment: [String: String]
    public let processDir: String
    public let logPath: String
    public let socketPath: String

    public var logsDir: String { (logPath as NSString).deletingLastPathComponent }
}

/// What Carrier lacks to start: `carrier` itself, or the `node` a script needs.
public func startMissing(_ settings: SetupSettings, carrier: String?) -> [String] {
    guard let carrier else { return ["carrier"] }
    return carrierNeedsNode(carrier) && settings.node.isEmpty ? ["node"] : []
}

/// nil when `startMissing` is not empty. The engine finds its config, logs and socket from `CARRIER_HOME`, which is set to the
/// Carrier folder (the app's own environment's, else `~/.carrier`); the log and the socket are in the folder's `engine/`.
/// `environment` is the app's own; its PATH is replaced.
public func startCommand(settings: SetupSettings, carrier: String?, environment: [String: String], home: String = NSHomeDirectory()) -> StartCommand? {
    guard let carrier, startMissing(settings, carrier: carrier).isEmpty else { return nil }
    let folder = carrierFolder(environment: environment, home: home)
    var environment = environment
    environment["PATH"] = enginePath(detected: settings.path, node: settings.node)
    environment["CARRIER_HOME"] = folder
    let places = CarrierPlaces(environment: environment, home: home)
    let run = carrierProgram(carrier: carrier, node: settings.node, arguments: [])
    return StartCommand(
        program: run.program, arguments: run.arguments, environment: environment,
        processDir: places.engine, logPath: places.engineStartLog, socketPath: places.controlSocket
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

/// The tool a start log says could not be run: the `agent-forge` of `spawn agent-forge ENOENT`, which Node prints when the PATH it was
/// given has no such program. nil when the log has no such line. The name is the program as written, never a path.
public func missingTool(in log: String) -> String? {
    guard let found = log.range(of: #"spawn ([\w.@+-]+) ENOENT"#, options: .regularExpression) else { return nil }
    return String(log[found].dropFirst("spawn ".count).dropLast(" ENOENT".count))
}

/// The settings to try a start again with, after a start failed for a tool that was not found: what the shell says now. A value it did
/// not find stays as it was, so an answer that is partial (a `.zshrc` that loads `node` lazily) never removes one that worked.
public func redetected(_ settings: SetupSettings, with detection: Detection) -> SetupSettings {
    SetupSettings(node: detection.node ?? settings.node, path: detection.path ?? settings.path)
}

/// What the alert adds when a start failed for a tool and the shell was asked for its PATH again: that it has no such tool either, or that
/// it did not answer (`shellAnswered` false), so the person knows whether the PATH was read.
public func toolNotFoundText(_ tool: String, shellAnswered: Bool = true) -> String {
    shellAnswered
        ? "\(tool) is not on the PATH of your shell either, which was read again just now. Install it, or add its folder to the PATH of your shell, and start again."
        : "\(tool) was not found, and the shell gave no answer when asked for its PATH again. Press Detect in Settings to try once more."
}

/// The last `lines` lines of the start log, for the alert.
public func logTail(_ log: Data, lines: Int = 30) -> String {
    let text = String(decoding: log, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    let tail = text.split(separator: "\n", omittingEmptySubsequences: false).suffix(lines)
    return text.isEmpty ? "(the start log is empty)" : tail.joined(separator: "\n")
}

/// What the Carrier home and the Carrier section of the sidebar say while `<folder>/engine.json` does not exist; nil once it does.
/// It has no action: the config is made by the native setup wizard, which is its own epic.
public func engineNotConfiguredNotice(configExists: Bool) -> String? {
    configExists ? nil : "The engine is not configured: there is no engine.json in the Carrier folder."
}

/// The Start Carrier menu item: it can be pressed only while Carrier is stopped, the engine is configured, the settings are
/// complete and no start is under way; otherwise the title says what is missing or that it is starting.
public func startMenuState(state: ConnectionState, starting: Bool, missing: [String], configExists: Bool) -> (title: String, enabled: Bool) {
    if starting { return ("Starting Carrier…", false) }
    guard state == .stopped else { return ("Start Carrier", false) }
    if configExists == false { return ("Start Carrier (engine not configured)", false) }
    if missing.isEmpty { return ("Start Carrier", true) }
    return ("Start Carrier (missing: \(missing.joined(separator: ", ")))", false)
}

/// Whether opening the app starts Carrier: the person asked for it, the first state the monitor delivered is stopped, Start
/// Carrier is enabled, it is not `--fixture`, and this launch has not looked yet.
public func shouldStartOnOpen(enabled: Bool, firstState: ConnectionState, startReady: Bool, fixture: Bool, alreadyTried: Bool) -> Bool {
    enabled && firstState == .stopped && startReady && fixture == false && alreadyTried == false
}
