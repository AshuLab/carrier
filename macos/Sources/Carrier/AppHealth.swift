import Foundation
import CarrierCore

/// The one health the app holds: the draft reads it, and what asks again (Check again) goes through it.
enum AppHealth {
    @MainActor static let store = HealthStore(host: SocketChatHost())
    /// The engine's setup: runs only when the Health tab opens and on Check again.
    @MainActor static let doctor = DoctorStore(run: runProcess)
}

/// Runs `command` (`node <carrier> ...` with its environment) off the main thread and returns what it printed; ended after `doctorTimeout`
/// (killed a second later). The output of the doctor is the JSON on stdout; stderr is dropped.
@Sendable func runProcess(_ command: StartCommand) async -> ProcessOutcome {
    await Task.detached { () -> ProcessOutcome in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.node)
        process.arguments = command.arguments
        process.environment = command.environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return ProcessOutcome(startError: "\(error)") }
        // ponytail: a grandchild holding the pipe open could still block the read past the limit
        let timedOut = Atomic()
        DispatchQueue.global().asyncAfter(deadline: .now() + doctorTimeout) {
            guard process.isRunning else { return }
            timedOut.set()
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
        }
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return ProcessOutcome(exitCode: process.terminationStatus, stdout: text, timedOut: timedOut.value)
    }.value
}

private final class Atomic: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set() { lock.withLock { flag = true } }
    var value: Bool { lock.withLock { flag } }
}
