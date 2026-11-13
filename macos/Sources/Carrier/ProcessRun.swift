import Foundation

/// Runs a command that answers at once (`--version`) and gives back what it printed on stdout and how it ended. It is ended after `limit`
/// seconds and killed one second later; `timedOut` says so. Throws when it cannot start.
func shortRun(
    _ program: String, _ arguments: [String], environment: [String: String], limit: TimeInterval = 5
) throws -> (text: String, status: Int32, timedOut: Bool) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: program)
    process.arguments = arguments
    process.environment = environment
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice
    try process.run()
    // ponytail: a grandchild holding the pipe open could still block the read past the limit
    DispatchQueue.global().asyncAfter(deadline: .now() + limit) {
        guard process.isRunning else { return }
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
    }
    let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()
    return (text, process.terminationStatus, process.terminationReason == .uncaughtSignal)
}
