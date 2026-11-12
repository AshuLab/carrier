import Foundation

// What the Repos page and the new session say about when Carrier uses a repo that is saved (docs/specs/settings-apply-without-restart.md): that
// it applies it to the next epic when the connected engine lists `reload`, else that it reads it when it starts, which is true of a stopped
// Carrier and of an engine too old to reload. A save the engine did not apply says so, whatever the engine can do.

/// `canReload`: the hello of the engine the app talks to lists `reload`. `outcome`: what the engine answered to the last save; `repo` is
/// what the note calls the repo ("this repo" on its own page).
public func settingsNote(state: ConnectionState?, canReload: Bool, outcome: ReloadOutcome?, repo: String = "this repo") -> String {
    // what the engine answered belongs to a running engine: a stopped Carrier reads the file when it starts, whatever it once said
    guard case .running? = state else { return reads(repo) }
    switch outcome {
    case .refused?: return "Not in use: Carrier kept its previous settings"
    case .noAnswer?: return "Carrier did not answer: it may not have applied \(repo)"
    default: return canReload ? applies(repo) : reads(repo)
    }
}

/// What the new session says of the repo it added, from what the engine answered.
public func addedRepoNote(_ repo: String, outcome: ReloadOutcome) -> (text: String, failed: Bool) {
    switch outcome {
    case .applied: (applies(repo), false)
    case .nobody, .unsupported, .asked: (reads(repo), false)
    case .refused(let problem): ("\(repo) was added to Carrier's list, but Carrier kept its settings: \(problem)", true)
    case .noAnswer: ("\(repo) was added to Carrier's list, but Carrier did not answer: it may not have applied it.", true)
    }
}

private func applies(_ repo: String) -> String { "Carrier applies \(repo) to the next epic" }
private func reads(_ repo: String) -> String { "Carrier reads \(repo) when it starts" }
