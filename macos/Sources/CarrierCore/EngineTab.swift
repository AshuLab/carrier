import Foundation

// The Engine tab of Settings as plain values: the readiness banner (docs/specs/macos-app-redesign.md, story 30). The tab asks for
// nothing but the advanced "use this carrier"; `node` and the `PATH` come from the shell, and `carrier` from Homebrew.

public struct ReadinessBanner: Equatable {
    public enum State: Equatable { case ready, missing, detecting }

    public var state: State
    public var title: String
    public var detail: String
}

/// `missing` is what `startMissing` says.
public func readinessBanner(missing: [String], detecting: Bool) -> ReadinessBanner {
    if detecting {
        return ReadinessBanner(state: .detecting, title: "Looking for what Carrier needs", detail: "Asking your shell, this takes a few seconds.")
    }
    if missing.isEmpty {
        return ReadinessBanner(state: .ready, title: "Start Carrier is ready", detail: "Everything it needs was found.")
    }
    let names = missing.joined(separator: " and ")
    return ReadinessBanner(
        state: .missing, title: "Start Carrier needs \(names)",
        detail: "Install carrier with Homebrew, or set “Use this carrier” under Advanced, then run Detect again."
    )
}
