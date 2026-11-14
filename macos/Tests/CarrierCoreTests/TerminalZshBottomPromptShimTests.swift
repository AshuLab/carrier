import Foundation
import Testing
@testable import CarrierCore

struct TerminalZshBottomPromptShimTests {
    @Test func detectsZshAndSkipsNonZshShells() {
        let shimDir = URL(fileURLWithPath: "/tmp/carrier-shim", isDirectory: true)

        #expect(TerminalZshBottomPromptShim.isZshShell(nil))
        #expect(TerminalZshBottomPromptShim.isZshShell(""))
        #expect(TerminalZshBottomPromptShim.isZshShell("/bin/zsh"))
        #expect(TerminalZshBottomPromptShim.isZshShell("/opt/homebrew/bin/zsh"))
        #expect(TerminalZshBottomPromptShim.isZshShell("/bin/bash") == false)
        #expect(TerminalZshBottomPromptShim.isZshShell("/opt/homebrew/bin/fish") == false)

        let bashEnv = TerminalZshBottomPromptShim.mergedEnvironment(
            baseEnvVars: ["SHELL": "/bin/bash"],
            processEnvironment: ["ZDOTDIR": "/Users/me/.zsh"],
            shimDirectory: shimDir,
            pinPromptToBottom: true,
            command: nil
        )
        #expect(bashEnv == ["SHELL": "/bin/bash"])
    }

    @Test func preservesCustomUserZdotdirAndHonorsCommandAndToggleGates() {
        let shimDir = URL(fileURLWithPath: "/tmp/carrier-shim", isDirectory: true)

        let enabled = TerminalZshBottomPromptShim.mergedEnvironment(
            baseEnvVars: ["CUSTOM": "1"],
            processEnvironment: ["SHELL": "/bin/zsh", "ZDOTDIR": "/Users/dev/.config/zsh"],
            shimDirectory: shimDir,
            pinPromptToBottom: true,
            command: nil
        )
        #expect(enabled["ZDOTDIR"] == shimDir.path)
        #expect(enabled[TerminalZshBottomPromptShim.userZdotdirEnvKey] == "/Users/dev/.config/zsh")
        #expect(enabled["CUSTOM"] == "1")

        // Avoid recursive self-wrapping when inherited ZDOTDIR already points at the shim directory.
        let nonRecursive = TerminalZshBottomPromptShim.mergedEnvironment(
            baseEnvVars: [:],
            processEnvironment: ["SHELL": "/bin/zsh", "ZDOTDIR": shimDir.path],
            shimDirectory: shimDir,
            pinPromptToBottom: true,
            command: nil
        )
        #expect(nonRecursive["ZDOTDIR"] == shimDir.path)
        #expect(nonRecursive[TerminalZshBottomPromptShim.userZdotdirEnvKey] == nil)

        let withCommand = TerminalZshBottomPromptShim.mergedEnvironment(
            baseEnvVars: ["CUSTOM": "1"],
            processEnvironment: ["SHELL": "/bin/zsh", "ZDOTDIR": "/Users/dev/.config/zsh"],
            shimDirectory: shimDir,
            pinPromptToBottom: true,
            command: "echo hello"
        )
        #expect(withCommand == ["CUSTOM": "1"])

        let disabled = TerminalZshBottomPromptShim.mergedEnvironment(
            baseEnvVars: ["CUSTOM": "1"],
            processEnvironment: ["SHELL": "/bin/zsh", "ZDOTDIR": "/Users/dev/.config/zsh"],
            shimDirectory: shimDir,
            pinPromptToBottom: false,
            command: nil
        )
        #expect(disabled == ["CUSTOM": "1"])
    }

    @Test func persistsPinPromptToBottomPreferenceWithTrueDefault() {
        let suite = "pin-prompt-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let prefs = AppPreferences(defaults: defaults)
        #expect(prefs.terminal.pinPromptToBottom == true)

        var updated = prefs.terminal
        updated.pinPromptToBottom = false
        prefs.terminal = updated
        #expect(AppPreferences(defaults: defaults).terminal.pinPromptToBottom == false)

        prefs.resetTerminal()
        #expect(AppPreferences(defaults: defaults).terminal.pinPromptToBottom == true)
    }

    @Test func realZshPtyLoadsUserDotfilesRestoresZdotdirAndAnchorsBottomWithoutClearErrors() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("carrier-zsh-pty-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let shimDir = root.appendingPathComponent("shim", isDirectory: true)
        let userDir = root.appendingPathComponent("user", isDirectory: true)
        try FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)

        // Include a `clear` alias to confirm shim's `unalias clear` prevents zsh function parse errors.
        try "export CARRIER_TEST_ENV=1\n".write(
            to: userDir.appendingPathComponent(".zshenv"),
            atomically: true,
            encoding: .utf8
        )
        try "export CARRIER_TEST_LOGIN_ENV=1\n".write(
            to: userDir.appendingPathComponent(".zprofile"),
            atomically: true,
            encoding: .utf8
        )
        try """
        export CARRIER_TEST_RC=1
        alias clear='echo user-clear'
        PROMPT=$'%~\\n> '
        """.write(
            to: userDir.appendingPathComponent(".zshrc"),
            atomically: true,
            encoding: .utf8
        )
        try "export CARRIER_TEST_LOGIN_END=1\n".write(
            to: userDir.appendingPathComponent(".zlogin"),
            atomically: true,
            encoding: .utf8
        )

        try TerminalZshBottomPromptShim.prepareDirectory(shimDir)

        let env = TerminalZshBottomPromptShim.mergedEnvironment(
            baseEnvVars: [
                "HOME": userDir.path,
                "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin",
                "TERM": "xterm-256color",
            ],
            processEnvironment: ["SHELL": "/bin/zsh", "ZDOTDIR": userDir.path],
            shimDirectory: shimDir,
            pinPromptToBottom: true,
            command: nil
        )

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        process.arguments = ["-q", "/dev/null", "/bin/zsh", "-il"]
        process.environment = env
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stdoutPipe

        let collector = OutputCollector()
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty == false {
                collector.append(data)
            }
        }
        defer {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            if process.isRunning { process.terminate() }
        }

        try process.run()

        func send(_ command: String, waitSeconds: TimeInterval = 0.25) {
            if let data = command.data(using: .utf8) {
                stdinPipe.fileHandleForWriting.write(data)
            }
            Thread.sleep(forTimeInterval: waitSeconds)
        }

        Thread.sleep(forTimeInterval: 0.45)
        send("echo \"VARS:$CARRIER_TEST_ENV:$CARRIER_TEST_LOGIN_ENV:$CARRIER_TEST_RC:$CARRIER_TEST_LOGIN_END:$ZDOTDIR\"\n")
        send("clear\n")
        send("echo typed", waitSeconds: 0.15)
        send("\u{0C}", waitSeconds: 0.3)
        send(" && echo AFTER_CTRLL\n")
        send("exit\n", waitSeconds: 0.2)
        try? stdinPipe.fileHandleForWriting.close()
        process.waitUntilExit()

        let text = String(decoding: collector.snapshot(), as: UTF8.self)
        #expect(text.contains("parse error") == false)
        #expect(text.contains("VARS:1:1:1:1:\(userDir.path)"))
        #expect(text.contains("\u{1B}[?2026h\u{1B}[H\u{1B}[2J\u{1B}[999;1H\u{1B}[?2026l"))
        #expect(text.contains("\u{1B}[?2026h\u{1B}[3J\u{1B}[H\u{1B}[2J\u{1B}[999;1H\u{1B}[?2026l"))
        #expect(text.contains("\u{1B}[?2026h\u{1B}[H\u{1B}[2J\u{1B}[999;1H"))
        #expect(text.contains("AFTER_CTRLL"))
    }
}

private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}
