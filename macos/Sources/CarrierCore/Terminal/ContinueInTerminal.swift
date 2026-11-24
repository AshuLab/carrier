import Foundation

// Continue in Terminal (docs/adr/0007, docs/research/interactive-resume.md): the engine's descriptor is validated against
// allowlists and every value is single-quoted. Epic Continue in Terminal runs `cd '<folder>' && <harness> ...` inside Carrier's
// embedded Ghostty drawer with failing closed on directory or exit errors; Health/Forge flows still open one-use 0700 scripts.

public enum ResumeRejection: Error, Equatable {
    case unknownHarness
    case badSessionId
    case badFolder
    case folderOutsideEngine
    case badConfigDir
}

/// A descriptor that passed `validateResume`; `cwd` is the resolved folder (symlinks followed), inside the engine's folder.
public struct ValidResume: Equatable {
    public var harness: String
    public var sessionId: String
    public var cwd: String
    public var configDir: String?
}

private func isIdentifier(_ id: String) -> Bool {
    // ASCII letters, digits, `_` and `-`, starting with a letter or digit (never a dash: it would read as an option).
    let bytes = Array(id.utf8)
    guard (1...128).contains(bytes.count), let first = bytes.first, first != 0x2D, first != 0x5F else { return false }
    return bytes.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A) || $0 == 0x5F || $0 == 0x2D }
}

/// An absolute path with no `..` component and no control character (a NUL cannot go through a shell at all), as a resolved
/// path when it exists and is a folder; nil otherwise.
private func existingFolder(_ path: String) -> String? {
    guard path.hasPrefix("/"), !path.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }),
        !path.split(separator: "/", omittingEmptySubsequences: false).contains("..")
    else { return nil }
    guard let resolved = realpath(path, nil) else { return nil }
    defer { free(resolved) }
    var isFolder = ObjCBool(false)
    let result = String(cString: resolved)
    return FileManager.default.fileExists(atPath: result, isDirectory: &isFolder) && isFolder.boolValue ? result : nil
}

/// The allowlist: the three harnesses, a strict id, an existing folder inside the engine's folder `engine` (after resolving symlinks) and, when
/// given, an existing configuration folder. Antigravity has no configuration variable, so its `configDir` is dropped.
public func validateResume(_ descriptor: ResumeDescriptor, engine: String) -> Result<ValidResume, ResumeRejection> {
    guard ["claude", "codex", "agy"].contains(descriptor.harness) else { return .failure(.unknownHarness) }
    guard isIdentifier(descriptor.sessionId) else { return .failure(.badSessionId) }
    guard let folder = existingFolder(descriptor.cwd) else { return .failure(.badFolder) }
    guard let base = existingFolder(engine), folder.hasPrefix(base == "/" ? "/" : base + "/") else { return .failure(.folderOutsideEngine) }
    var configDir: String?
    if let given = descriptor.configDir, descriptor.harness != "agy" {
        guard let config = existingFolder(given) else { return .failure(.badConfigDir) }
        configDir = config
    }
    return .success(ValidResume(harness: descriptor.harness, sessionId: descriptor.sessionId, cwd: folder, configDir: configDir))
}

/// Validated launch specification for opening a resumable epic session in the embedded terminal drawer.
public struct EmbeddedResumeLaunch: Equatable, Sendable {
    public let workingDirectory: String
    /// Interactive login shell command so user PATH entries resolve harness binaries and exiting closes the pane cleanly.
    public let command: String
}

private func resumeConfigEnvironmentVariable(for harness: String) -> String? {
    [("claude", "CLAUDE_CONFIG_DIR"), ("codex", "CODEX_HOME")].first { $0.0 == harness }?.1
}

private func resumeRunCommand(_ resume: ValidResume) -> String {
    let id = shellQuote(resume.sessionId)
    return switch resume.harness {
    case "codex": "codex resume \(id)"
    case "agy": "agy --conversation \(id)"
    default: "claude --resume \(id)"
    }
}

/// The two steps of the command, every value single-quoted: `cd '<folder>'` and `CLAUDE_CONFIG_DIR='<dir>' claude --resume '<id>'`.
private func resumeSteps(_ resume: ValidResume) -> (cd: String, run: String) {
    let environment = resumeConfigEnvironmentVariable(for: resume.harness)
        .flatMap { name in resume.configDir.map { "\(name)=\(shellQuote($0)) " } } ?? ""
    return ("cd \(shellQuote(resume.cwd))", environment + resumeRunCommand(resume))
}

/// Builds the folder and login-shell command for Carrier's embedded Ghostty drawer.
/// The shell script `cd`s explicitly with inline scoped config variables so inaccessible folders fail closed
/// and user shell startup files cannot override `CLAUDE_CONFIG_DIR` or `CODEX_HOME`, while holding
/// non-zero failures open until the user presses Return so errors stay visible.
public func embeddedResumeLaunch(_ resume: ValidResume) -> EmbeddedResumeLaunch {
    let steps = resumeSteps(resume)
    let shellBody = "(\(steps.cd) && \(steps.run)) || { code=$?; builtin printf '\\nContinue in Terminal exited with status %s.' \"$code\"; if [[ -t 0 ]]; then builtin printf ' Press Return to close...'; IFS= read -r _; fi; exit $code; }"
    return EmbeddedResumeLaunch(
        workingDirectory: resume.cwd,
        command: "/bin/zsh -il -c \(shellQuote(shellBody))"
    )
}

/// The command of the mockup's block: `cd '<folder>' && CLAUDE_CONFIG_DIR='<dir>' claude --resume '<id>'`.
public func resumeCommand(_ resume: ValidResume) -> String {
    let steps = resumeSteps(resume)
    return "\(steps.cd) && \(steps.run)"
}

public enum ContinueError: Error, Equatable {
    case notWritten
}

/// Writes `script(path)` as a one-use file (mode 0700, unpredictable name, created exclusively) in `directory` and asks `opener` to open
/// it; the file is deleted again if it cannot be opened. Shared by Health fixes (`fixInTerminal`) and Forge login (`ForgeTerminal`).
func openScript(_ script: (String) -> String, opener: TerminalOpener, directory: String) throws -> URL {
    let path = (directory as NSString).appendingPathComponent("carrier-\(UUID().uuidString).command")
    let descriptorNumber = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o700)
    guard descriptorNumber >= 0 else { throw ContinueError.notWritten }
    let handle = FileHandle(fileDescriptor: descriptorNumber, closeOnDealloc: true)
    do {
        try handle.write(contentsOf: Data(script(path).utf8))
        try handle.close()
        // The mode asked at creation is subject to the umask; this one is not.
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
        try opener.open(URL(fileURLWithPath: path))
    } catch {
        try? FileManager.default.removeItem(atPath: path)
        throw error
    }
    return URL(fileURLWithPath: path)
}
