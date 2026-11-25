import Foundation

// The Carrier switch of a project (docs/specs/projects.md, "The watch"): watching a project is its `owner/name` in the `repos` of `engine.json`. The
// request, the rules and the words are the Watching page's (`setWatchedRepos`, `reposProblem`, `settingsNote`, `removalText`), so the two pages cannot disagree about the file.

/// Whether `repo` is in `names`, compared as GitHub does, ignoring case.
public func isWatched(_ repo: String, in names: [String]) -> Bool {
    names.contains { $0.lowercased() == repo.lowercased() }
}

/// What a project's Carrier switch shows and does.
public struct ProjectWatchRow: Equatable, Sendable {
    public var isOn: Bool
    /// False for a project with no GitHub origin and while the engine config cannot be read.
    public var canChange: Bool
    public var detail: String
    /// Orange, in the place of the detail.
    public var problem: String?
}

/// The switch's row. `repos` is the engine config's list as it was when the page opened (nil when the file cannot be read); `failure` is why the last change was
/// refused; `outcome` is what the engine answered to the last save. A stopped Carrier says it reads the change when it starts.
public func projectWatchRow(
    repo: String?, repos: [String]?, state: ConnectionState?, canReload: Bool, outcome: ReloadOutcome?, failure: String?, bundle: Bundle? = nil, locale: Locale = .current
) -> ProjectWatchRow {
    guard let repo else {
        return ProjectWatchRow(isOn: false, canChange: false, detail: Copy.projectsWatchNoOrigin(bundle: bundle, locale: locale), problem: nil)
    }
    guard let repos else {
        return ProjectWatchRow(
            isOn: false, canChange: false, detail: "",
            problem: Copy.projectsWatchNoEngine(bundle: bundle, locale: locale)
        )
    }
    let isOn = isWatched(repo, in: repos)
    let detail = isOn
        ? settingsNote(state: state, canReload: canReload, outcome: outcome, repo: repo)
        : appliesWhileRunning(state: state, canReload: canReload)
            ? Copy.projectsWatchOff(repo: repo, bundle: bundle, locale: locale)
            : Copy.projectsWatchOffStopped(repo: repo, bundle: bundle, locale: locale)
    let answer = isOn && outcome?.isProblem == true ? outcome.flatMap(reloadWords) : nil
    return ProjectWatchRow(isOn: isOn, canChange: true, detail: detail, problem: failure ?? reposProblem(repos) ?? answer)
}

/// What turning the switch of `repo` asks: the list for `setWatchedRepos` (the one `names`, the config's list now, with `repo` added or taken out; it keeps every other key and every other repo's fields
/// in the engine), or the reason the Watching page's rules would not take it (the same folder name as a repo already watched), and nothing is sent.
public enum WatchChange: Equatable {
    case send([String])
    case refused(String)
}

public func watchChange(_ on: Bool, repo: String, in names: [String]) -> WatchChange {
    var next = names.filter { $0.lowercased() != repo.lowercased() }
    if on, isWatched(repo, in: names) == false {
        if let problem = repoProblem(repo, joining: names) { return .refused(problem) }
        next = names + [repo]
    } else if on {
        next = names
    }
    if let problem = reposProblem(next) { return .refused(problem) }
    return .send(next)
}
