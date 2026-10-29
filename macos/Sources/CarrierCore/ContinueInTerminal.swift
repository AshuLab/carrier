import Foundation

// Continue in Terminal (docs/adr/0007, docs/research/interactive-resume.md and macos-app-command-script.md): the engine's
// descriptor is validated against allowlists, the command is built here with every value single-quoted, written to a one-use
// 0700 script and handed to the user's terminal. The descriptor never reaches a shell unvalidated, and no token is involved:
// the terminal runs as the user, in their environment.

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

/// The two steps of the command, every value single-quoted: `cd '<folder>'` and `CLAUDE_CONFIG_DIR='<dir>' claude --resume '<id>'`.
private func resumeSteps(_ resume: ValidResume) -> (cd: String, run: String) {
    let variable = [("claude", "CLAUDE_CONFIG_DIR"), ("codex", "CODEX_HOME")].first { $0.0 == resume.harness }?.1
    let environment = variable.flatMap { name in resume.configDir.map { "\(name)=\(shellQuote($0)) " } } ?? ""
    let id = shellQuote(resume.sessionId)
    let run = switch resume.harness {
    case "codex": "codex resume \(id)"
    case "agy": "agy --conversation \(id)"
    default: "claude --resume \(id)"
    }
    return ("cd \(shellQuote(resume.cwd))", environment + run)
}

/// The command of the mockup's block: `cd '<folder>' && CLAUDE_CONFIG_DIR='<dir>' claude --resume '<id>'`.
public func resumeCommand(_ resume: ValidResume) -> String {
    let steps = resumeSteps(resume)
    return "\(steps.cd) && \(steps.run)"
}

/// The one-use script: it removes itself first, then runs the command in an interactive login shell, so the user's PATH holds
/// the harnesses. ponytail: not run in a real terminal here; `-il` is the user's own tab shell, by hand it is Diego's check.
public func resumeScript(_ resume: ValidResume, path: String) -> String {
    let steps = resumeSteps(resume)
    return "#!/bin/zsh -il\nrm -f -- \(shellQuote(path))\n\(steps.cd) || exit 1\n\(steps.run)\n"
}

/// Hands the script to the user's terminal; the app's is `NSWorkspace`, tests record the call.
public protocol TerminalOpener {
    func open(_ script: URL) throws
}

public enum ContinueError: Error, Equatable {
    case rejected(ResumeRejection)
    case notWritten
}

/// Validates, writes the script (mode 0700, unpredictable name, created exclusively) in `directory` and asks `opener` to open
/// it. The script is deleted again if it cannot be opened; otherwise it deletes itself when it runs.
@discardableResult
public func continueInTerminal(
    _ descriptor: ResumeDescriptor, engine: String, opener: TerminalOpener, directory: String = NSTemporaryDirectory()
) throws -> URL {
    let resume: ValidResume
    switch validateResume(descriptor, engine: engine) {
    case .success(let valid): resume = valid
    case .failure(let rejection): throw ContinueError.rejected(rejection)
    }
    let path = (directory as NSString).appendingPathComponent("carrier-\(UUID().uuidString).command")
    let descriptorNumber = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o700)
    guard descriptorNumber >= 0 else { throw ContinueError.notWritten }
    let handle = FileHandle(fileDescriptor: descriptorNumber, closeOnDealloc: true)
    do {
        try handle.write(contentsOf: Data(resumeScript(resume, path: path).utf8))
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
