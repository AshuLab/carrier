import Foundation
import Observation

// The engine's setup in the Health tab (docs/specs/health-check-in-the-app.md): the checks of `carrier doctor --json`, run as a process with
// `CARRIER_HOME` when the tab opens and on Check again, never in the background (the doctor makes GitHub calls and mints tokens), and
// only with a `config.json`. The process itself lives in the shell and is passed in, so the store is tested with a fake one.

/// One check of the doctor, as it prints it. The `fix` is shown as text and never run.
public struct DoctorCheck: Decodable, Equatable {
    public enum Status: String, Decodable, Equatable { case ok, warn, fail }

    public let name: String
    public let status: Status
    public let detail: String?
    public let fix: String?

    public init(name: String, status: Status, detail: String? = nil, fix: String? = nil) {
        self.name = name
        self.status = status
        self.detail = detail
        self.fix = fix
    }
}

/// How long the doctor is given: its GitHub calls and probes take seconds on a normal machine, so this is generous.
public let doctorTimeout: TimeInterval = 90

/// What running a process came to.
public struct ProcessOutcome: Equatable {
    public var exitCode: Int32?
    public var stdout: String
    public var timedOut: Bool
    /// Why the process could not start; nil when it did.
    public var startError: String?

    public init(exitCode: Int32? = nil, stdout: String = "", timedOut: Bool = false, startError: String? = nil) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.timedOut = timedOut
        self.startError = startError
    }
}

public enum DoctorState: Equatable {
    case idle, running
    case checks([DoctorCheck])
    /// The doctor could not answer, and why. Never a pass.
    case unknown(String)
}

/// The doctor exits 1 when a check failed and still prints the checks, so the output decides and the exit code only explains.
public func doctorState(from outcome: ProcessOutcome) -> DoctorState {
    if let error = outcome.startError { return .unknown("carrier doctor could not start: \(error)") }
    if outcome.timedOut { return .unknown("carrier doctor did not finish in \(Int(doctorTimeout)) seconds and was stopped") }
    let exit = outcome.exitCode.map { " (exit \($0))" } ?? ""
    guard let checks = try? JSONDecoder().decode([DoctorCheck].self, from: Data(outcome.stdout.utf8)) else {
        return .unknown("carrier doctor printed something that is not its checks" + exit)
    }
    return checks.isEmpty ? .unknown("carrier doctor printed no checks" + exit) : .checks(checks)
}

/// `node <carrier> doctor --config <folder>/config.json --json`, with the engine's `PATH` and `CARRIER_HOME`; nil when the settings lack
/// `node` or `carrier`.
public func doctorCommand(settings: SetupSettings, environment: [String: String], home: String = NSHomeDirectory()) -> StartCommand? {
    guard let start = startCommand(settings: settings, environment: environment, home: home) else { return nil }
    return StartCommand(
        node: start.node, arguments: start.arguments + ["doctor", "--config", configFilePath(environment: environment, home: home), "--json"],
        environment: start.environment, processDir: start.processDir, logPath: start.logPath, socketPath: start.socketPath
    )
}

/// The last run of the doctor. It runs only when asked, with a config, and not again while one is running.
@MainActor @Observable public final class DoctorStore {
    public private(set) var state: DoctorState = .idle

    @ObservationIgnored private let run: @Sendable (StartCommand) async -> ProcessOutcome

    public init(run: @escaping @Sendable (StartCommand) async -> ProcessOutcome) { self.run = run }

    public func check(settings: SetupSettings, environment: [String: String], configExists: Bool) async {
        guard configExists, state != .running else { return }
        guard let command = doctorCommand(settings: settings, environment: environment) else {
            state = .unknown("node or carrier was not found: set their paths in the Engine tab")
            return
        }
        state = .running
        state = doctorState(from: await run(command))
    }
}
