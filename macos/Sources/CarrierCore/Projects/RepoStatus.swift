import Foundation

/// The Status card of a repo's page, from the list's row: what the running engine knows of it, where Carrier's clone is and the repo
/// on GitHub. A repo the engine has not loaded, and every repo while Carrier is stopped, has no epics and no last check, only a note (`notLoaded`, from `settingsNote`).
public struct RepoStatus: Equatable {
    /// "None ready · 1 running"; nil when the engine does not know the repo
    public var epics: String?
    /// "Checked 2m ago", or the engine's error; nil when the engine does not know the repo
    public var lastCheck: String?
    /// said in place of the epics and the last check
    public var note: String?
    /// the clone with `~` for the home folder
    public var clone: String
    public var clonePath: String
    /// Reveal is offered only for a clone that exists
    public var canRevealClone: Bool
    /// Open
    public var gitHubURL: URL?
}

public func repoStatus(
    _ row: RepoRow, engine: String, home: String = NSHomeDirectory(), cloneExists: Bool, notLoaded: String, bundle: Bundle? = nil, locale: Locale = .current
) -> RepoStatus {
    let path = row.clonePath(engine: engine)
    var status = RepoStatus(clone: tildePath(path, home: home), clonePath: path, canRevealClone: cloneExists, gitHubURL: row.gitHubURL)
    guard row.isLoaded, let epics = row.epics else {
        status.note = notLoaded
        return status
    }
    let counts = Copy.projectsRepoEpics(ready: epics.queued, running: epics.running, bundle: bundle, locale: locale)
    status.epics = epics.needsYou > 0 ? Copy.projectsRepoEpicsNeedsYou(epics: counts, count: epics.needsYou, bundle: bundle, locale: locale) : counts
    status.lastCheck = row.line
    return status
}
