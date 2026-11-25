import Foundation

// Starting Carrier (or the chat host) from the app, on `ProcessRunner`: the spawn, the wait for the socket or the exit, the retry when a tool
// was not found, and the log's tail. The decisions it makes are the functions of `StartCarrier.swift`.

/// What to tell the person when a start did not come up: the reason and the end of the start log.
public struct LaunchFailure: Equatable {
    public let reason: String
    public let tail: String
}

/// How a start that failed for a tool the PATH lacks is tried again: the settings now, the command they make, and where the new settings are kept.
public struct StartRetry {
    public var settings: () async -> SetupSettings
    public var command: (SetupSettings) -> StartCommand?
    public var save: (SetupSettings) async -> Void

    public init(settings: @escaping () async -> SetupSettings, command: @escaping (SetupSettings) -> StartCommand?, save: @escaping (SetupSettings) async -> Void) {
        (self.settings, self.command, self.save) = (settings, command, save)
    }
}

public struct CarrierLauncher {
    let runner: any ProcessRunner
    let socket: any HostSocket
    /// How long to wait between two looks at the socket and the exit.
    let poll: Duration

    public init(runner: any ProcessRunner, socket: any HostSocket, poll: Duration = .milliseconds(250)) {
        (self.runner, self.socket, self.poll) = (runner, socket, poll)
    }

    /// Spawns Carrier and waits for its socket; nil when it came up, else what to tell the person. When it exits because a tool was not
    /// found on the PATH (`spawn agent-forge ENOENT`) and `retry` can build the command for other settings, the shell is asked for its
    /// PATH once more, since a folder added after the app first asked never reached the engine, and the start is tried once more when
    /// that gives another command.
    public func launch(_ command: StartCommand, name: String = "Carrier", retry: StartRetry? = nil, bundle: Bundle? = nil, locale: Locale = .current) async -> LaunchFailure? {
        guard let first = await attempt(command, name: name, bundle: bundle, locale: locale) else { return nil }
        guard first.exited, let tool = missingTool(in: first.failure.tail), let retry else { return first.failure }
        guard let detection = await runner.detectShell() else { return first.failure.adding(toolNotFoundText(tool, shellAnswered: false, bundle: bundle, locale: locale)) }
        let fresh = redetected(await retry.settings(), with: detection)
        // compared with the command that failed, not with the saved settings: another start may have saved them since
        guard let next = retry.command(fresh), next != command else { return first.failure.adding(toolNotFoundText(tool, bundle: bundle, locale: locale)) }
        await retry.save(fresh)
        guard let second = await attempt(next, name: name, bundle: bundle, locale: locale) else { return nil }
        guard second.exited, let still = missingTool(in: second.failure.tail) else { return second.failure }
        return second.failure.adding(toolNotFoundText(still, bundle: bundle, locale: locale))
    }

    /// One spawn and its wait; `exited` is whether the process ended, as against not opening its socket in time.
    private func attempt(_ command: StartCommand, name: String, bundle: Bundle?, locale: Locale) async -> (failure: LaunchFailure, exited: Bool)? {
        let log = URL(fileURLWithPath: command.logPath)
        do {
            try prepareLogFolder(command)
            let process = try runner.spawnDetached(
                ProcessCommand(program: command.program, arguments: command.arguments, environment: command.environment), log: command.logPath)
            let began = Date()
            while true {
                switch startOutcome(exitCode: process.exitCode, socketAnswered: socket.answers(at: command.socketPath), elapsed: Date().timeIntervalSince(began)) {
                case .running?: return nil
                case .failed(let failure)?:
                    let exited = if case .exited = failure { true } else { false }
                    return (LaunchFailure(reason: startFailureText(failure, name: name, bundle: bundle, locale: locale), tail: tail(of: log, bundle: bundle, locale: locale)), exited)
                case nil: try? await Task.sleep(for: poll)
                }
            }
        } catch {
            FileHandle.standardError.write(Data("carrier: \(name) start failed: \(error)\n".utf8))
            return (LaunchFailure(reason: Copy.lifecycleStartFailedSpawn(name: name, reason: error.localizedDescription, bundle: bundle, locale: locale), tail: tail(of: log, bundle: bundle, locale: locale)), false)
        }
    }

    /// The orchestrator folder is for the user only, as the engine makes it; the logs folder is inside it.
    private func prepareLogFolder(_ command: StartCommand) throws {
        let files = FileManager.default
        try files.createDirectory(atPath: command.processDir, withIntermediateDirectories: true)
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: command.processDir)
        try files.createDirectory(atPath: command.logsDir, withIntermediateDirectories: true)
    }

    /// The end of the log, from its last 16 KB.
    private func tail(of log: URL, bundle: Bundle?, locale: Locale) -> String {
        guard let handle = try? FileHandle(forReadingFrom: log) else { return logTail(Data(), bundle: bundle, locale: locale) }
        defer { try? handle.close() }
        if let size = try? handle.seekToEnd(), size > 16_384 { try? handle.seek(toOffset: size - 16_384) } else { try? handle.seek(toOffset: 0) }
        return logTail((try? handle.readToEnd()) ?? Data(), bundle: bundle, locale: locale)
    }
}

private extension LaunchFailure {
    func adding(_ text: String) -> LaunchFailure { LaunchFailure(reason: reason + " " + text, tail: tail) }
}

public enum StartResult: Equatable {
    /// A start was under way, the engine has no `engine.json`, or there was no command: nothing was started.
    case notStarted
    case up
    case failed(LaunchFailure)
}

/// The Start Carrier action: one start at a time, only with an `engine.json`.
public final class CarrierStart: @unchecked Sendable {
    private let launcher: CarrierLauncher
    private let configPath: () -> String
    private let lock = NSLock()
    private var running = false
    /// Called, on the thread that changed it, when a start begins and when it ends.
    public var onStartingChange: ((Bool) -> Void)?

    public init(launcher: CarrierLauncher, configPath: @escaping () -> String = { configFilePath() }) {
        (self.launcher, self.configPath) = (launcher, configPath)
    }

    public var starting: Bool { lock.withLock { running } }

    /// Whether the Carrier folder has its `engine.json`; without it the engine does not start.
    public func configExists() -> Bool { FileManager.default.fileExists(atPath: configPath()) }

    public func start(_ command: StartCommand?, retry: StartRetry? = nil) async -> StartResult {
        guard configExists(), let command, begin() else { return .notStarted }
        defer { end() }
        if let failure = await launcher.launch(command, retry: retry) { return .failed(failure) }
        return .up
    }

    private func begin() -> Bool {
        guard lock.withLock({ guard running == false else { return false }; running = true; return true }) else { return false }
        onStartingChange?(true)
        return true
    }

    private func end() {
        lock.withLock { running = false }
        onStartingChange?(false)
    }
}
