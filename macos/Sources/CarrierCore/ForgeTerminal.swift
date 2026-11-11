import Foundation

// Create a bot… on the Agents page (docs/specs/agents-in-settings.md, docs/adr/0007): Terminal opens on `agent-forge add`. The command is
// from a closed list, one entry; nothing read from the registry, the config or the host becomes part of it, and the script and the opener
// are Continue in Terminal's (`openScript`). Agent Forge makes the GitHub App and keeps the key; the app never sees it.

public enum ForgeCommandError: Error, Equatable {
    /// A verb outside the list.
    case notInTheList
}

/// The words of the command for `verb`; only `add` is in the list.
public func forgeCommand(_ verb: String) throws -> [String] {
    switch verb {
    case "add": ["agent-forge", "add"]
    default: throw ForgeCommandError.notInTheList
    }
}

/// Opens Terminal on `agent-forge add`, through the same one-use script as a health fix.
@discardableResult
public func createBotInTerminal(opener: TerminalOpener, directory: String = NSTemporaryDirectory()) throws -> URL {
    let command = try forgeCommand("add")
    return try openScript({ fixScript(command, path: $0) }, opener: opener, directory: directory)
}
