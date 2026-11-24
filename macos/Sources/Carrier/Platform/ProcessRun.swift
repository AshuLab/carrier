import Foundation

/// Runs a command that answers at once (`--version`) and gives back what it printed on stdout and how it ended. It is ended after `limit`
/// seconds and killed one second later; `timedOut` says so. `input` is written to its standard input, which is then closed. Throws when it cannot start.
func shortRun(
    _ program: String, _ arguments: [String], environment: [String: String], input: Data? = nil, limit: TimeInterval = 5
) throws -> (text: String, status: Int32, timedOut: Bool) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: program)
    process.arguments = arguments
    process.environment = environment
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    let stdin = input.map { _ in Pipe() }
    process.standardInput = stdin ?? FileHandle.nullDevice
    try process.run()
    if let stdin, let input {
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)  // a program that ended without reading is a write that fails, not a signal that ends the app
        // ponytail: written before the output is read, so an input larger than the pipe (64 KB) against a program that answers first would block
        try? stdin.fileHandleForWriting.write(contentsOf: input)
        try? stdin.fileHandleForWriting.close()
    }
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
