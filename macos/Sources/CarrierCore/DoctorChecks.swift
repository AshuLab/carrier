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
    /// Set with `profiles` on the checks about one repo; an older doctor leaves both out.
    public let repo: String?
    /// The names under `config.profiles` the check stands for.
    public let profiles: [String]?

    public init(name: String, status: Status, detail: String? = nil, fix: String? = nil, repo: String? = nil, profiles: [String]? = nil) {
        self.name = name
        self.status = status
        self.detail = detail
        self.fix = fix
        self.repo = repo
        self.profiles = profiles
    }
}

/// How long the doctor is given: its GitHub calls and probes take seconds on a normal machine, so this is generous.
public let doctorTimeout: TimeInterval = 90

/// What running a process came to.
public struct ProcessOutcome: Equatable {
    public var exitCode: Int32?
    public var stdout: String
    /// what it printed on stderr: where the doctor says why it refused a config
    public var stderr: String
    public var timedOut: Bool
    /// Why the process could not start; nil when it did.
    public var startError: String?

    public init(exitCode: Int32? = nil, stdout: String = "", stderr: String = "", timedOut: Bool = false, startError: String? = nil) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
        self.startError = startError
    }
}

public enum DoctorState: Equatable {
    case idle, running
    case checks([DoctorCheck])
    /// The doctor could not answer, and why. Never a pass.
    case unknown(String)
    /// The doctor refused the config itself, with this reason (its words, the keys named).
    case refused(String)
}

/// The doctor exits 1 when a check failed and still prints the checks, so the output decides and the exit code only explains.
public func doctorState(from outcome: ProcessOutcome) -> DoctorState {
    if let error = outcome.startError { return .unknown("carrier doctor could not start: \(error)") }
    if outcome.timedOut { return .unknown("carrier doctor did not finish in \(Int(doctorTimeout)) seconds and was stopped") }
    let exit = outcome.exitCode.map { " (exit \($0))" } ?? ""
    guard let checks = try? JSONDecoder().decode([DoctorCheck].self, from: Data(outcome.stdout.utf8)) else {
        // a config the engine refuses ends the command before any check, with "Invalid config <file>:" and a line per key on stderr
        if let start = outcome.stderr.range(of: "Invalid ") {
            return .refused(outcome.stderr[start.lowerBound...].trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return .unknown("carrier doctor printed something that is not its checks" + exit)
    }
    return checks.isEmpty ? .unknown("carrier doctor printed no checks" + exit) : .checks(checks)
}

/// `carrier doctor --config <folder>/config.json --json` (behind `node` for a script), with the engine's `PATH` and `CARRIER_HOME`; nil
/// when `carrier`, or the `node` a script needs, is missing.
public func doctorCommand(settings: SetupSettings, carrier: String?, environment: [String: String], home: String = NSHomeDirectory()) -> StartCommand? {
    guard let start = startCommand(settings: settings, carrier: carrier, environment: environment, home: home) else { return nil }
    return StartCommand(
        program: start.program, arguments: start.arguments + ["doctor", "--config", configFilePath(environment: environment, home: home), "--json"],
        environment: start.environment, processDir: start.processDir, logPath: start.logPath, socketPath: start.socketPath
    )
}

/// The last run of the doctor. It runs only when asked, with a config, and not again while one is running.
@MainActor @Observable public final class DoctorStore {
    public private(set) var state: DoctorState = .idle

    @ObservationIgnored private let run: @Sendable (StartCommand) async -> ProcessOutcome

    public init(run: @escaping @Sendable (StartCommand) async -> ProcessOutcome) { self.run = run }

    public func check(settings: SetupSettings, carrier: String?, environment: [String: String], configExists: Bool) async {
        guard configExists, state != .running else { return }
        guard let command = doctorCommand(settings: settings, carrier: carrier, environment: environment) else {
            state = .unknown("carrier was not found (or node, for a carrier that is a script)")
            return
        }
        state = .running
        state = doctorState(from: await run(command))
    }
}
