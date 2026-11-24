import Foundation

// Sign in and Update on the Providers page (docs/specs/providers-in-settings.md, docs/adr/0007): the command is built here from a closed
// list, harness by action, with every value single-quoted; the script and the opener are Continue in Terminal's (`openScript`). Nothing
// from the host or from `providers.json` (a binary, a folder) becomes part of a shell string unquoted, and a value that is not an absolute
// path is refused before anything is written.

public enum ProviderAction: String, Equatable {
    case signIn, update
}

public enum ProviderCommandError: Error, Equatable {
    /// A harness outside `claude`, `codex` and `agy`.
    case unknownHarness
    /// The account's folder is not an absolute path.
    case badFolder
    /// The account's `command` is not an absolute path.
    case badCommand
}

/// An absolute path with no control character (a NUL cannot go through a shell at all).
private func isAbsolutePath(_ path: String) -> Bool {
    path.hasPrefix("/") && path.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value != 0x7F }
}

/// The line the script runs. Sign in: `CLAUDE_CONFIG_DIR='<folder>' 'claude' '/login'`, `CODEX_HOME='<folder>' 'codex' 'login'` or `'agy'` (the variable
/// only when the account has a folder; Antigravity has none). Update: `'claude' 'update'`, `'codex' 'update'` or `'agy' 'update'`. `command`, when the
/// account sets one, is the binary that runs in place of the harness's name.
public func providerCommand(_ action: ProviderAction, harness: String, command: String? = nil, configDir: String? = nil) throws -> String {
    guard ["claude", "codex", "agy"].contains(harness) else { throw ProviderCommandError.unknownHarness }
    if let command, isAbsolutePath(command) == false { throw ProviderCommandError.badCommand }
    if let configDir, isAbsolutePath(configDir) == false { throw ProviderCommandError.badFolder }
    let binary = shellQuote(command ?? harness)
    switch action {
    case .update:
        return "\(binary) 'update'"
    case .signIn:
        let variable = ["claude": "CLAUDE_CONFIG_DIR", "codex": "CODEX_HOME"][harness]
        let environment = variable.flatMap { name in configDir.map { "\(name)=\(shellQuote($0)) " } } ?? ""
        switch harness {
        case "claude": return "\(environment)\(binary) '/login'"
        case "codex": return "\(environment)\(binary) 'login'"
        default: return binary
        }
    }
}

/// The one-use script of a provider action: it removes itself, then runs the line in an interactive login shell (the user's PATH).
public func providerScript(_ line: String, path: String) -> String {
    "#!/bin/zsh -il\nrm -f -- \(shellQuote(path))\n\(line)\n"
}

/// Opens Terminal on `providerCommand`; a refusal is thrown before anything is written or opened.
@discardableResult
public func providerInTerminal(
    _ action: ProviderAction, harness: String, command: String? = nil, configDir: String? = nil, opener: TerminalOpener,
    directory: String = NSTemporaryDirectory()
) throws -> URL {
    let line = try providerCommand(action, harness: harness, command: command, configDir: configDir)
    return try openScript({ providerScript(line, path: $0) }, opener: opener, directory: directory)
}

/// The opener of `--fixture`: says what Terminal would have run and removes the script, so a click in the fixture opens nothing.
public struct FixtureTerminalOpener: TerminalOpener {
    private let say: (String) -> Void

    public init(say: @escaping (String) -> Void = { FileHandle.standardError.write(Data("carrier: fixture terminal: \($0)\n".utf8)) }) { self.say = say }

    public func open(_ script: URL) throws {
        let text = try String(contentsOf: script, encoding: .utf8)
        try FileManager.default.removeItem(at: script)
        say(text.split(separator: "\n").last.map(String.init) ?? "")
    }
}
