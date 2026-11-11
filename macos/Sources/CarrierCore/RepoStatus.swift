import Foundation

/// The Status card of a repo's page, from the list's row: what the running engine knows of it, where Carrier's clone is and the repo
/// on GitHub. A repo the engine has not loaded, and every repo while Carrier is stopped, has no epics and no last check, only a note.
public struct RepoStatus: Equatable {
    public static let notLoaded = "Carrier reads it when it starts"

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

public func repoStatus(_ row: RepoRow, engine: String, home: String = NSHomeDirectory(), cloneExists: Bool) -> RepoStatus {
    let path = row.clonePath(engine: engine)
    var status = RepoStatus(clone: tildePath(path, home: home), clonePath: path, canRevealClone: cloneExists, gitHubURL: row.gitHubURL)
    guard row.isLoaded, let epics = row.epics else {
        status.note = RepoStatus.notLoaded
        return status
    }
    status.epics = [epics.queued > 0 ? "\(epics.queued) ready" : "None ready", epics.running > 0 ? "\(epics.running) running" : "none running"]
        .joined(separator: " · ") + (epics.needsYou > 0 ? " · \(epics.needsYou) needs you" : "")
    status.lastCheck = row.line
    return status
}
