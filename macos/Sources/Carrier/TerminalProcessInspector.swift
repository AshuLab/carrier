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
    ]

    private let psExecutablePath: String
    private let timeoutSeconds: TimeInterval
    private let log: @Sendable (String) -> Void

    init(
        psExecutablePath: String = "/bin/ps",
        timeoutSeconds: TimeInterval = 1.5,
        log: @escaping @Sendable (String) -> Void = { FileHandle.standardError.write(Data("carrier: \($0)\n".utf8)) }
    ) {
        self.psExecutablePath = psExecutablePath
        self.timeoutSeconds = timeoutSeconds
        self.log = log
    }

    func inspectActiveCommands(in panes: [TerminalPaneInspectionInput]) async -> TerminalProcessInspectionResult {
        var paneIdsByShortTTY: [String: [UUID]] = [:]
        for pane in panes {
            guard let rawTTY = pane.platformView?.ttyName ?? pane.state.attachedPlatformView?.ttyName,
                  let shortTTY = Self.normalizeShortTTY(rawTTY)
            else {
                continue
            }
            paneIdsByShortTTY[shortTTY, default: []].append(pane.paneId)
        }
        guard paneIdsByShortTTY.isEmpty == false else {
            return TerminalProcessInspectionResult()
        }

        let shortTTYs = paneIdsByShortTTY.keys.sorted()
        let executable = psExecutablePath
        let timeout = timeoutSeconds
        let logger = log

        return await Task.detached(priority: .userInitiated) {
            Self.runBatchedPS(
                executablePath: executable,
                shortTTYs: shortTTYs,
                paneIdsByShortTTY: paneIdsByShortTTY,
                timeoutSeconds: timeout,
                log: logger
            )
        }.value
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
        log: @Sendable (String) -> Void
    ) -> TerminalProcessInspectionResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["-t", shortTTYs.joined(separator: ","), "-o", "tty=,comm="]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            done.signal()
        }

        do {
            try process.run()
        } catch {
            let message = "failed to inspect terminal processes with \(executablePath): \(error.localizedDescription)"
            log(message)
            return TerminalProcessInspectionResult(inspectionError: error.localizedDescription)
        }

        let waitResult = done.wait(timeout: .now() + max(timeoutSeconds, 0.1))
        if waitResult == .timedOut {
            process.terminate()
            _ = done.wait(timeout: .now() + 0.5)
            let message = "timed out inspecting terminal processes after \(timeoutSeconds)s"
            log(message)
            return TerminalProcessInspectionResult(inspectionError: message)
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        if process.terminationStatus != 0 {
            let stderrText = String(decoding: stderrData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if process.terminationStatus == 1 && stderrText.isEmpty {
                return TerminalProcessInspectionResult()
            }
            let reason = stderrText.isEmpty ? "exit status \(process.terminationStatus)" : stderrText
            log("process inspection returned non-zero status: \(reason)")
            return TerminalProcessInspectionResult(inspectionError: reason)
        }

        let output = String(decoding: stdoutData, as: UTF8.self)
        let parsed = parsePSOutput(output, paneIdsByShortTTY: paneIdsByShortTTY)
        return TerminalProcessInspectionResult(commandsByPane: parsed)
    }
}
