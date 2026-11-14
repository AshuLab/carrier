import Foundation
import GhosttyTerminal

/// Input snapshot describing one terminal pane to inspect for running child commands.
struct TerminalPaneInspectionInput {
    let paneId: UUID
    let state: TerminalViewState
    let platformView: TerminalView?
}

/// Batch inspection outcome mapping pane ids to active non-shell commands and any inspection error.
struct TerminalProcessInspectionResult: Equatable, Sendable {
    let commandsByPane: [UUID: [String]]
    let inspectionError: String?

    init(commandsByPane: [UUID: [String]] = [:], inspectionError: String? = nil) {
        self.commandsByPane = commandsByPane
        self.inspectionError = inspectionError
    }
}

/// Seam for inspecting live child commands inside terminal panes without tying unit tests to real TTYs.
@MainActor
protocol TerminalProcessInspecting {
    func inspectActiveCommands(in panes: [TerminalPaneInspectionInput]) async -> TerminalProcessInspectionResult
}

/// Default process inspector backed by GhosttyKit's `ttyName` and an off-main-thread `/bin/ps` query.
@MainActor
struct GhosttyTerminalProcessInspector: TerminalProcessInspecting {
    nonisolated static let ignoredCommands: Set<String> = [
        "login",
        "zsh", "-zsh",
        "bash", "-bash",
        "fish", "-fish",
        "sh", "-sh",
        "nu", "-nu",
        "ksh", "-ksh",
        "dash", "-dash",
        "tcsh", "-tcsh",
        "csh", "-csh",
        "pwsh", "-pwsh",
        "ps",
        "<defunct>",
    ]

    private let psExecutablePath: String
    private let timeoutSeconds: TimeInterval
    private let ttyExists: @Sendable (String) -> Bool
    private let log: @Sendable (String) -> Void

    init(
        psExecutablePath: String = "/bin/ps",
        timeoutSeconds: TimeInterval = 1.5,
        ttyExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: "/dev/\($0)") },
        log: @escaping @Sendable (String) -> Void = { FileHandle.standardError.write(Data("carrier: \($0)\n".utf8)) }
    ) {
        self.psExecutablePath = psExecutablePath
        self.timeoutSeconds = timeoutSeconds
        self.ttyExists = ttyExists
        self.log = log
    }

    func inspectActiveCommands(in panes: [TerminalPaneInspectionInput]) async -> TerminalProcessInspectionResult {
        var paneIdsByShortTTY: [String: [UUID]] = [:]
        var verifiedExistingByTTY: [String: Bool] = [:]
        for pane in panes {
            guard let rawTTY = pane.platformView?.ttyName ?? pane.state.attachedPlatformView?.ttyName,
                  let shortTTY = Self.normalizeShortTTY(rawTTY)
            else {
                continue
            }
            let exists = verifiedExistingByTTY[shortTTY] ?? {
                let present = ttyExists(shortTTY)
                verifiedExistingByTTY[shortTTY] = present
                return present
            }()
            guard exists else { continue }
            paneIdsByShortTTY[shortTTY, default: []].append(pane.paneId)
        }
        guard paneIdsByShortTTY.isEmpty == false else {
            return TerminalProcessInspectionResult()
        }

        let shortTTYs = paneIdsByShortTTY.keys.sorted()
        return await Self.runBatchedPS(
            executablePath: psExecutablePath,
            shortTTYs: shortTTYs,
            paneIdsByShortTTY: paneIdsByShortTTY,
            timeoutSeconds: timeoutSeconds,
            log: log
        )
    }

    nonisolated static func normalizeShortTTY(_ rawTTY: String) -> String? {
        let trimmed = rawTTY.trimmingCharacters(in: .whitespacesAndNewlines)
        let shortTTY = trimmed.hasPrefix("/dev/") ? String(trimmed.dropFirst(5)) : trimmed
        return shortTTY.isEmpty ? nil : shortTTY
    }

    nonisolated static func parsePSOutput(
        _ output: String,
        paneIdsByShortTTY: [String: [UUID]]
    ) -> [UUID: [String]] {
        var commandsByPane: [UUID: [String]] = [:]
        var seenByPane: [UUID: Set<String>] = [:]

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.isEmpty == false else { continue }
            guard let splitIndex = line.firstIndex(where: \.isWhitespace) else { continue }

            let ttyToken = String(line[..<splitIndex])
            let commandToken = line[splitIndex...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let shortTTY = normalizeShortTTY(ttyToken),
                  commandToken.isEmpty == false,
                  let matchingPaneIds = paneIdsByShortTTY[shortTTY]
            else {
                continue
            }

            let base = (commandToken as NSString).lastPathComponent
            guard ignoredCommands.contains(commandToken) == false,
                  ignoredCommands.contains(base) == false
            else {
                continue
            }

            for paneId in matchingPaneIds {
                if seenByPane[paneId, default: []].insert(base).inserted {
                    commandsByPane[paneId, default: []].append(base)
                }
            }
        }
        return commandsByPane
    }

    nonisolated static func runBatchedPS(
        executablePath: String,
        shortTTYs: [String],
        paneIdsByShortTTY: [String: [UUID]],
        timeoutSeconds: TimeInterval,
        log: @escaping @Sendable (String) -> Void
    ) async -> TerminalProcessInspectionResult {
        final class DrainState: @unchecked Sendable {
            private let lock = NSLock()
            var stdoutData = Data()
            var stderrData = Data()
            private var completed = false
            private let continuation: CheckedContinuation<TerminalProcessInspectionResult, Never>

            init(continuation: CheckedContinuation<TerminalProcessInspectionResult, Never>) {
                self.continuation = continuation
            }

            func finish(with result: TerminalProcessInspectionResult) {
                lock.lock()
                let shouldResume = completed == false
                completed = true
                lock.unlock()
                if shouldResume {
                    continuation.resume(returning: result)
                }
            }
        }

        let effectiveTimeout = max(timeoutSeconds, 0.1)
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = ["-t", shortTTYs.joined(separator: ","), "-o", "tty=,comm="]

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let state = DrainState(continuation: continuation)
            let pipeGroup = DispatchGroup()
            let drainQueue = DispatchQueue.global(qos: .userInitiated)

            let timeoutWork = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                }
                let message = "timed out inspecting terminal processes after \(timeoutSeconds)s"
                log(message)
                state.finish(with: TerminalProcessInspectionResult(inspectionError: message))
            }

            process.terminationHandler = { terminated in
                pipeGroup.notify(queue: drainQueue) {
                    timeoutWork.cancel()
                    if terminated.terminationStatus != 0 {
                        let stderrText = String(decoding: state.stderrData, as: UTF8.self)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if terminated.terminationStatus == 1 && stderrText.isEmpty {
                            state.finish(with: TerminalProcessInspectionResult())
                            return
                        }
                        let reason = stderrText.isEmpty ? "exit status \(terminated.terminationStatus)" : stderrText
                        log("process inspection returned non-zero status: \(reason)")
                        state.finish(with: TerminalProcessInspectionResult(inspectionError: reason))
                        return
                    }

                    let output = String(decoding: state.stdoutData, as: UTF8.self)
                    let parsed = parsePSOutput(output, paneIdsByShortTTY: paneIdsByShortTTY)
                    state.finish(with: TerminalProcessInspectionResult(commandsByPane: parsed))
                }
            }

            pipeGroup.enter()
            pipeGroup.enter()

            do {
                try process.run()
            } catch {
                pipeGroup.leave()
                pipeGroup.leave()
                timeoutWork.cancel()
                let message = "failed to inspect terminal processes with \(executablePath): \(error.localizedDescription)"
                log(message)
                state.finish(with: TerminalProcessInspectionResult(inspectionError: error.localizedDescription))
                return
            }

            // Drain stdout and stderr concurrently so output above the pipe buffer never deadlocks.
            drainQueue.async {
                state.stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                pipeGroup.leave()
            }
            drainQueue.async {
                state.stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                pipeGroup.leave()
            }

            drainQueue.asyncAfter(deadline: .now() + effectiveTimeout, execute: timeoutWork)
        }
    }
}
