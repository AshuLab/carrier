import Foundation
@testable import CarrierCore

/// A `ProcessRunner` that runs nothing: it keeps what it was asked and answers from what it was given.
/// `runResults` and `spawns` are answered in order, the last one again when they run out.
final class FakeProcessRunner: ProcessRunner, @unchecked Sendable {
    struct Spawn {
        var exitCode: Int32?
        /// What the program wrote to its log.
        var log = ""
    }

    private final class Spawned: SpawnedProcess, @unchecked Sendable {
        let exitCode: Int32?
        init(_ exitCode: Int32?) { self.exitCode = exitCode }
    }

    private let lock = NSLock()
    private var asked: [ProcessCommand] = []
    private var started: [(command: ProcessCommand, log: String)] = []
    private var detections = 0
    private let runResults: [Result<ProcessResult, Error>]
    private let spawns: [Spawn]
    private let detection: Detection?

    init(runs: [Result<ProcessResult, Error>] = [], spawns: [Spawn] = [], detection: Detection? = nil) {
        (runResults, self.spawns, self.detection) = (runs, spawns, detection)
    }

    var ran: [ProcessCommand] { lock.withLock { asked } }
    var spawned: [(command: ProcessCommand, log: String)] { lock.withLock { started } }
    var shellAsked: Int { lock.withLock { detections } }

    func run(_ command: ProcessCommand) async throws -> ProcessResult {
        let result = lock.withLock { () -> Result<ProcessResult, Error> in
            asked.append(command)
            return runResults[min(asked.count, runResults.count) - 1]
        }
        return try result.get()
    }

    func spawnDetached(_ command: ProcessCommand, log: String) throws -> any SpawnedProcess {
        let spawn = lock.withLock { () -> Spawn in
            started.append((command, log))
            return spawns[min(started.count, spawns.count) - 1]
        }
        try Data(spawn.log.utf8).write(to: URL(fileURLWithPath: log))
        return Spawned(spawn.exitCode)
    }

    func detectShell() async -> Detection? {
        lock.withLock { detections += 1 }
        return detection
    }
}
