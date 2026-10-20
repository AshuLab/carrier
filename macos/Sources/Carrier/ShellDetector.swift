import CarrierCore
import Foundation

/// The only code that starts the user's shell. `zsh -ilc` runs the whole .zshrc and takes about a second, so it is run
/// for a detection (first launch, or "Detect again"), never at any other time, and is killed after `limit` seconds.
enum ShellDetector {
    static let limit: TimeInterval = 10

    /// Blocks until the shell ends or is killed. Its output goes to a file, not a pipe, so a process the .zshrc leaves
    /// running with the pipe open cannot keep us waiting. nil when the shell gave no complete answer.
    static func run() -> Detection? {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("carrier-detect-\(UUID().uuidString).txt")
        guard FileManager.default.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600]),
              let sink = try? FileHandle(forWritingTo: output) else {
            log("could not create \(output.path)")
            return nil
        }
        defer { try? FileManager.default.removeItem(at: output) }

        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/zsh")
        shell.arguments = ["-ilc", detectionScript]
        shell.standardInput = FileHandle.nullDevice
        shell.standardOutput = sink
        shell.standardError = FileHandle.nullDevice
        let ended = DispatchSemaphore(value: 0)
        shell.terminationHandler = { _ in ended.signal() }
        do { try shell.run() } catch {
            log("could not start zsh: \(error)")
            return nil
        }
        if ended.wait(timeout: .now() + limit) == .timedOut {
            log("zsh did not finish in \(Int(limit)) s, killed")
            kill(shell.processIdentifier, SIGKILL)
            _ = ended.wait(timeout: .now() + 2)
        }
        try? sink.close()

        let text = String(decoding: (try? Data(contentsOf: output)) ?? Data(), as: UTF8.self)
        let detection = parseDetection(text)
        if detection == nil { log("no answer between the markers") }
        return detection
    }

    private static func log(_ message: String) {
        FileHandle.standardError.write(Data("carrier: detection: \(message)\n".utf8))
    }
}
