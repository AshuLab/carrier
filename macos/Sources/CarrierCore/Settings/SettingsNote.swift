import Foundation

// What the Watching page and the new session say about when Carrier uses a repo that is saved (docs/specs/settings-apply-without-restart.md): that
// it applies it to the next epic when the connected engine lists `reload`, else that it reads it when it starts, which is true of a stopped
// Carrier and of an engine too old to reload. A save the engine did not apply says so, whatever the engine can do.

/// `canReload`: the hello of the engine the app talks to lists `reload`. `outcome`: what the engine answered to the last save; `repo` is
/// what the note calls the repo (nil: "this repository", on its own page).
public func settingsNote(
    state: ConnectionState?, canReload: Bool, outcome: ReloadOutcome?, repo: String? = nil, bundle: Bundle? = nil, locale: Locale = .current
) -> String {
    let repo = repo ?? Copy.settingsNoteThisRepository(bundle: bundle, locale: locale)
    // what the engine answered belongs to a running engine: a stopped Carrier reads the file when it starts, whatever it once said
    guard case .running? = state else { return reads(repo, bundle: bundle, locale: locale) }
    switch outcome {
    case .refused?: return Copy.settingsNoteRefused(bundle: bundle, locale: locale)
    case .noAnswer?: return Copy.settingsNoteNoAnswer(repo: repo, bundle: bundle, locale: locale)
    default: return canReload ? applies(repo, bundle: bundle, locale: locale) : reads(repo, bundle: bundle, locale: locale)
    }
}

/// A change to the list is applied while Carrier runs: it is running and its engine lists `reload`.
public func appliesWhileRunning(state: ConnectionState?, canReload: Bool) -> Bool {
    if case .running? = state { return canReload }
    return false
}

/// What the new session says of the repo it added, from what the engine answered.
public func addedRepoNote(_ repo: String, outcome: ReloadOutcome, bundle: Bundle? = nil, locale: Locale = .current) -> (text: String, failed: Bool) {
    switch outcome {
    case .applied: (applies(repo, bundle: bundle, locale: locale), false)
    case .nobody, .unsupported: (reads(repo, bundle: bundle, locale: locale), false)
    case .refused(let problem): (Copy.settingsNoteAddedRefused(repo: repo, problem: problem.shown(bundle: bundle, locale: locale), bundle: bundle, locale: locale), true)
    case .noAnswer: (Copy.settingsNoteAddedNoAnswer(repo: repo, bundle: bundle, locale: locale), true)
    }
}

private func applies(_ repo: String, bundle: Bundle?, locale: Locale) -> String { Copy.settingsNoteApplies(repo: repo, bundle: bundle, locale: locale) }
private func reads(_ repo: String, bundle: Bundle?, locale: Locale) -> String { Copy.settingsNoteReads(repo: repo, bundle: bundle, locale: locale) }
