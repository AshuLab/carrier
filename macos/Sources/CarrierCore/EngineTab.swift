import Foundation

// The readiness banner of Settings (docs/specs/macos-app-redesign.md, story 30) as plain values. `node` and the `PATH` come from the shell, and
// `carrier` from Homebrew or the one the person chose under Programs on the Engine page.

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
        detail: "Install carrier with Homebrew, or use “Use another…” and then Detect under Programs."
    )
}
