import CarrierCore
import Darwin
import Foundation

/// `ProcessRunner` on `Process`: the program runs off the caller's thread, its standard error is dropped (it may hold a token, nothing echoes it).
struct SystemProcessRunner: ProcessRunner {
    func run(_ command: ProcessCommand) async throws -> ProcessResult {
        try await Task.detached {
            let run = try shortRun(command.program, command.arguments, environment: command.environment, input: command.input, limit: command.limit)
            return ProcessResult(output: run.text, status: run.status, timedOut: run.timedOut)
        }.value
    }

    func detectShell() async -> Detection? {
        await Task.detached { ShellDetector.run() }.value
    }

    /// Its own session (so it outlives the app and has no terminal), stdin from /dev/null, stdout and stderr to the log,
    /// nothing else inherited from the app.
    func spawnDetached(_ command: ProcessCommand, log: String) throws -> any SpawnedProcess {
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, log, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        posix_spawn_file_actions_adddup2(&actions, 1, 2)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        var defaults = sigset_t()
        sigfillset(&defaults)
        var none = sigset_t()
        sigemptyset(&none)
        posix_spawnattr_setsigdefault(&attributes, &defaults)
        posix_spawnattr_setsigmask(&attributes, &none)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))

        let argv = ([command.program] + command.arguments).map { strdup($0) } + [nil]
        let envp = command.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { (argv + envp).forEach { free($0) } }

        var pid: pid_t = 0
        let result = posix_spawn(&pid, command.program, &actions, &attributes, argv, envp)
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: result) ?? .EIO) }
        let spawned = SpawnedExit()
        // the app is the parent: the exit has to be collected, whenever it comes
        Thread.detachNewThread { spawned.set(Self.wait(for: pid)) }
        return spawned
    }

    /// Blocks until the process ends; a signal counts as 128 plus its number, as a shell reports it.
    private static func wait(for pid: pid_t) -> Int32 {
        var status: Int32 = 0
        while waitpid(pid, &status, 0) < 0 {
            guard errno == EINTR else { return -1 }
        }
        let signal = status & 0x7f
        return signal == 0 ? (status >> 8) & 0xff : 128 + signal
    }
}

/// Set by the thread that waits for the process, read by the one that watches for the socket.
private final class SpawnedExit: SpawnedProcess, @unchecked Sendable {
    private let lock = NSLock()
    private var code: Int32?
    var exitCode: Int32? { lock.lock(); defer { lock.unlock() }; return code }
    func set(_ code: Int32) { lock.lock(); self.code = code; lock.unlock() }
}
