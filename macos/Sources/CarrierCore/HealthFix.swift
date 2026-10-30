import Foundation

// What the app offers for a check that failed (docs/specs/health-check-in-the-app.md): a command that opens Terminal, or the installation
// page of a CLI that is missing. The list is data here, keyed by what failed; nothing a probe, the host or the doctor returned (a name, a
// harness, a detail) is ever part of a command, and a key that is not in the list has no fix. The script and the opener are Continue in
// Terminal's (docs/adr/0007).

/// What was checked: a chat agent by its harness, `gh` or `git`.
public enum HealthTool: Equatable {
    case agent(harness: String)
    case gh
    case git
}

public enum HealthFix: Equatable {
    /// The words of a command to run in Terminal.
    case command([String])
    /// The page that says how to install the CLI.
    case install(URL)

    /// The command as the button names it.
    public var label: String? {
        if case .command(let words) = self { words.joined(separator: " ") } else { nil }
    }
}

/// The fixed list: `signedOut` has the command that signs in (`claude`, `codex`, `gh`), `missing` a CLI's installation page and `git`'s
/// installer (`xcode-select --install`). `ready` and `unknown` have none, and neither has any harness the list does not name.
public func healthFix(_ tool: HealthTool, _ state: ToolState) -> HealthFix? {
    switch (tool, state) {
    case (.agent("claude"), .signedOut): .command(["claude", "auth", "login"])
    case (.agent("codex"), .signedOut): .command(["codex", "login"])
    case (.gh, .signedOut): .command(["gh", "auth", "login"])
    case (.git, .missing): .command(["xcode-select", "--install"])
    case (.agent("claude"), .missing): .install(URL(string: "https://docs.claude.com/en/docs/claude-code/setup")!)
    case (.agent("codex"), .missing): .install(URL(string: "https://developers.openai.com/codex/cli")!)
    case (.gh, .missing): .install(URL(string: "https://cli.github.com")!)
    default: nil
    }
}

/// The one-use script of a fix: it removes itself, then runs the command in an interactive login shell (the user's PATH), each word quoted.
public func fixScript(_ command: [String], path: String) -> String {
    "#!/bin/zsh -il\nrm -f -- \(shellQuote(path))\n\(command.map(shellQuote).joined(separator: " "))\n"
}

/// Opens Terminal on the fix the list has for `tool` in `state`; nil, and nothing written or opened, when the fix is not a command.
@discardableResult
public func fixInTerminal(_ tool: HealthTool, _ state: ToolState, opener: TerminalOpener, directory: String = NSTemporaryDirectory()) throws -> URL? {
    guard case .command(let command)? = healthFix(tool, state) else { return nil }
    return try openScript({ fixScript(command, path: $0) }, opener: opener, directory: directory)
}
