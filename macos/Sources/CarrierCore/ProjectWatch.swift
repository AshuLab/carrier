import Foundation

// The Carrier switch of a project (docs/specs/projects.md, "The watch"): watching a project is its `owner/name` in the `repos` of `engine.json`. The
// writer, the rules and the words are the Repos page's (`applyingRepos`, `reposProblem`, `settingsNote`, `removalText`), so the two pages cannot disagree about the file.

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
public func projectWatchRow(repo: String?, repos: [String]?, state: ConnectionState?, canReload: Bool, outcome: ReloadOutcome?, failure: String?) -> ProjectWatchRow {
    guard let repo else {
        return ProjectWatchRow(isOn: false, canChange: false, detail: "No GitHub origin: Carrier watches GitHub repositories, and this folder has none.", problem: nil)
    }
    guard let repos else {
        return ProjectWatchRow(
            isOn: false, canChange: false, detail: "",
            problem: "The engine is not configured: engine.json in the Carrier folder is missing or is not a JSON object."
        )
    }
    let isOn = isWatched(repo, in: repos)
    let detail = isOn
        ? settingsNote(state: state, canReload: canReload, outcome: outcome, repo: repo)
        : "Carrier does not look for epics in \(repo)." + (appliesWhileRunning(state: state, canReload: canReload) ? "" : " Carrier reads the list when it starts.")
    let answer = isOn && outcome?.isProblem == true ? outcome.flatMap(reloadWords) : nil
    return ProjectWatchRow(isOn: isOn, canChange: true, detail: detail, problem: failure ?? reposProblem(repos) ?? answer)
}

/// Watches or stops watching `repo` in the engine config at `path`, read just now and written like the Repos page does (every other key and every other repo's
/// fields kept), then the engine is asked to reload. `.refused` carries the reason when the rules of the Repos page would not take the list (the same folder name
/// as a repo already watched), and nothing is written.
public func saveWatch(_ on: Bool, repo: String, path: String, reload: AfterWrite = reloadInBackground) -> RoleSave {
    var refusal: String?
    let result = saveConfig(path: path, unusable: "The config file could not be read or the list is not valid.", edit: { json in
        guard let names = configRepoNames(json: json) else { return nil }
        var next = names.filter { $0.lowercased() != repo.lowercased() }
        if on, isWatched(repo, in: names) == false {
            refusal = repoProblem(repo, joining: names)
            next = names + [repo]
        } else if on {
            next = names
        }
        guard refusal == nil else { return nil }
        let data = applyingRepos(next, to: json)
        if data == nil { refusal = reposProblem(next) }
        return data
    }, reload: reload)
    return refusal.map(RoleSave.refused) ?? result
}
