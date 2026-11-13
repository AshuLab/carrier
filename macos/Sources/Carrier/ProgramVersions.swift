import CarrierCore
import Foundation

/// The versions the Programs group of the Engine page shows: what `carrier --version` and `node --version` print, nil while unread or when the
/// program does not answer.
struct ProgramVersions: Equatable {
    var carrier: String?
    var node: String?

    /// Runs both off the main thread, with the engine's `PATH` (a script `carrier` needs its `node`).
    static func read(_ setup: SetupController) async -> ProgramVersions {
        let settings = setup.settings
        let carrier = setup.carrier
        let environment = ProcessInfo.processInfo.environment.merging(["PATH": enginePath(detected: settings.path, node: settings.node)]) { _, new in new }
        return await Task.detached {
            var versions = ProgramVersions()
            if let carrier, carrierNeedsNode(carrier) == false || settings.node.isEmpty == false {
                let run = carrierProgram(carrier: carrier, node: settings.node, arguments: ["--version"])
                versions.carrier = output(run.program, run.arguments, environment)
            }
            if settings.node.isEmpty == false { versions.node = output(settings.node, ["--version"], environment) }
            return versions
        }.value
    }

    /// The first line the program printed, nil when it failed or did not end in time.
    private static func output(_ program: String, _ arguments: [String], _ environment: [String: String]) -> String? {
        guard let run = try? shortRun(program, arguments, environment: environment), run.status == 0 else { return nil }
        return run.text.split(whereSeparator: \.isNewline).first.map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

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
