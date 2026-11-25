import Foundation
import Observation

// The engine's setup in the Health tab (docs/specs/health-check-in-the-app.md): the checks of `carrier doctor --json`, run as a process with
// `CARRIER_HOME` when the tab opens and on Check again, never in the background (the doctor makes GitHub calls and mints tokens), and
// only with an `engine.json`. The process itself lives in the shell and is passed in, so the store is tested with a fake one.

/// One check of the doctor, as it prints it. The `fix` is shown as text and never run.
public struct DoctorCheck: Decodable, Equatable {
    public enum Status: String, Decodable, Equatable { case ok, warn, fail }

    public let name: String
    public let status: Status
    public let detail: String?
    public let fix: String?
    /// The text code and parameters of `detail` and of `fix`; nil on a check of a doctor that predates the codes, and on one that passed.
    public let detailCode: String?
    public let detailParams: [String: TextParam]?
    public let fixCode: String?
    public let fixParams: [String: TextParam]?
    /// Set with `profiles` on the checks about one repo; an older doctor leaves both out.
    public let repo: String?
    /// The names under `config.profiles` the check stands for.
    public let profiles: [String]?

    public init(
        name: String, status: Status, detail: String? = nil, fix: String? = nil, repo: String? = nil, profiles: [String]? = nil,
        detailCode: String? = nil, detailParams: [String: TextParam]? = nil, fixCode: String? = nil, fixParams: [String: TextParam]? = nil
    ) {
        self.name = name
        self.status = status
        self.detail = detail
        self.fix = fix
        (self.detailCode, self.detailParams, self.fixCode, self.fixParams) = (detailCode, detailParams, fixCode, fixParams)
        self.repo = repo
        self.profiles = profiles
    }

    /// `detail` and `fix` in the person's language: the copy of their code, else their words.
    public func shownDetail(bundle: Bundle? = nil, locale: Locale = .current) -> String? {
        detail.map { shownText($0, code: detailCode, params: detailParams, bundle: bundle, locale: locale) }
    }

    public func shownFix(bundle: Bundle? = nil, locale: Locale = .current) -> String? {
        fix.map { shownText($0, code: fixCode, params: fixParams, bundle: bundle, locale: locale) }
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
public func doctorState(from outcome: ProcessOutcome, bundle: Bundle? = nil, locale: Locale = .current) -> DoctorState {
    if let error = outcome.startError { return .unknown(Copy.healthDoctorNotStarted(error: error, bundle: bundle, locale: locale)) }
    if outcome.timedOut { return .unknown(Copy.healthDoctorTimedOut(seconds: Int(doctorTimeout), bundle: bundle, locale: locale)) }
    guard let checks = try? JSONDecoder().decode([DoctorCheck].self, from: Data(outcome.stdout.utf8)) else {
        // a config the engine refuses ends the command before any check, with "Invalid config <file>:" and a line per key on stderr
        if let start = outcome.stderr.range(of: "Invalid ") {
            return .refused(outcome.stderr[start.lowerBound...].trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return .unknown(outcome.exitCode.map { Copy.healthDoctorBadOutputExit(code: Int($0), bundle: bundle, locale: locale) } ?? Copy.healthDoctorBadOutput(bundle: bundle, locale: locale))
    }
    return checks.isEmpty ? .unknown(outcome.exitCode.map { Copy.healthDoctorNoChecksExit(code: Int($0), bundle: bundle, locale: locale) } ?? Copy.healthDoctorNoChecks(bundle: bundle, locale: locale)) : .checks(checks)
}

/// `carrier doctor --config <folder>/engine.json --json` (behind `node` for a script), with the engine's `PATH` and `CARRIER_HOME`; nil
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

    public func check(settings: SetupSettings, carrier: String?, environment: [String: String], configExists: Bool, bundle: Bundle? = nil, locale: Locale = .current) async {
        guard configExists, state != .running else { return }
        guard let command = doctorCommand(settings: settings, carrier: carrier, environment: environment) else {
            state = .unknown(Copy.healthDoctorNoCarrier(bundle: bundle, locale: locale))
            return
        }
        state = .running
        state = doctorState(from: await run(command), bundle: bundle, locale: locale)
    }
}
