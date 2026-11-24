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
