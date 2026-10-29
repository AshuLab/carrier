import Foundation

// What the app does about a chat host older than the installed `carrier`. Stopping a host closes its agents' processes and the work
// in them, so only a host with no session working or waiting is replaced.

public enum HostReplacement: Equatable { case keep, replace, askRestart }

/// Numbers separated by dots, nil for anything else (empty, `unknown`, `1.2-beta`). Surrounding whitespace is dropped, so the line
/// `carrier --version` prints reads as it is.
public func versionNumbers(_ text: String) -> [Int]? {
    let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".", omittingEmptySubsequences: false)
    let numbers = parts.compactMap { $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) ? Int($0) : nil }
    return numbers.count == parts.count ? numbers : nil
}

/// A version that cannot be read, on either side, is never older: the host stays. `1.2` and `1.2.0` are the same.
public func hostReplacement(running: String, installed: String, working: Bool) -> HostReplacement {
    guard var older = versionNumbers(running), var newer = versionNumbers(installed) else { return .keep }
    let length = max(older.count, newer.count)
    older += Array(repeating: 0, count: length - older.count)
    newer += Array(repeating: 0, count: length - newer.count)
    guard older.lexicographicallyPrecedes(newer) else { return .keep }
    return working ? .askRestart : .replace
}

/// What the Sessions section and the Sessions home say while an older host is left running because a session is working.
public let chatHostRestartNotice = ChatHostNotice(
    title: "The chat host is older than Carrier",
    line: "A session is working, so the app left it running. Restart the chat host when it finishes to use the installed Carrier."
)
