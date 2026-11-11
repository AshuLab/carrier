import CarrierCore
import Foundation

/// Runs `brew` for the Carrier upgrade with its output appended to one log in the engine's logs folder, next to `app-start.log`.
/// Blocks until `brew` ends: call it off the main thread.
enum BrewRunner {
    static var logPath: String { engineFolder() + "/logs/app-upgrade.log" }

    /// A new job starts a new log.
    static func startLog() {
        try? FileManager.default.createDirectory(atPath: (logPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: logPath, contents: nil, attributes: [.posixPermissions: 0o600])
    }

    static func run(_ command: BrewCommand) -> BrewOutcome {
        guard FileManager.default.isExecutableFile(atPath: brewPath) else { return .brewMissing }
        guard let log = FileHandle(forWritingAtPath: logPath) else { return .failed("The log \(logPath) could not be opened.") }
        defer { try? log.close() }
        _ = try? log.seekToEnd()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: brewPath)
        process.arguments = command.arguments
        process.environment = ProcessInfo.processInfo.environment.merging(command.environment) { _, new in new }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = log
        process.standardError = log
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return .failed("`brew` could not run: \(error.localizedDescription)")
        }
        return process.terminationStatus == 0 ? .done : .failed(tail())
    }

    /// The last lines of the log, from its last 16 KB.
    private static func tail() -> String {
        guard let handle = FileHandle(forReadingAtPath: logPath) else { return logTail(Data(), lines: 5) }
        defer { try? handle.close() }
        if let size = try? handle.seekToEnd(), size > 16_384 { try? handle.seek(toOffset: size - 16_384) } else { try? handle.seek(toOffset: 0) }
        return logTail((try? handle.readToEnd()) ?? Data(), lines: 5)
    }
}
