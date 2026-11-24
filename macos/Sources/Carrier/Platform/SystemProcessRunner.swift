import CarrierCore
import Foundation

/// `ProcessRunner` on `Process`: the program runs off the caller's thread, its standard error is dropped (it may hold a token, nothing echoes it).
struct SystemProcessRunner: ProcessRunner {
    func run(_ command: ProcessCommand) async throws -> ProcessResult {
        try await Task.detached {
            let run = try shortRun(command.program, command.arguments, environment: command.environment, input: command.input, limit: command.limit)
            return ProcessResult(output: run.text, status: run.status, timedOut: run.timedOut)
        }.value
    }
}
