import Foundation

// The Watching page as plain values: the `repos` of `engine.json` the app lets the person change (which repos are watched), their
// rows and the text of the confirmation to stop watching one. Nothing here reads or shows a repo's own settings: the list is written by
// the engine (`EngineConfigChange.watchedRepos`), which keeps a repo's other fields in the file exactly as they are.

/// `owner/name`, as the engine's `repoNamePattern` (src/config/schema.ts) accepts it: two parts of letters, digits, `_`, `.`
/// and `-`, neither of them `.` or `..`.
public func isRepoName(_ name: String) -> Bool {
    let parts = name.split(separator: "/", omittingEmptySubsequences: false)
    return parts.count == 2 && parts.allSatisfy { part in
        part.isEmpty == false && part != "." && part != ".."
            && part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "_.-".contains($0)) }
    }
}

/// The folder name Solve's worktrees use: no owner, so same-name repos would share paths.
public func repoFolder(_ name: String) -> String { String(name.split(separator: "/").last ?? "").lowercased() }

/// Why `name` cannot join `others`; nil when it can.
public func repoProblem(_ name: String, joining others: [String], bundle: Bundle? = nil, locale: Locale = .current) -> String? {
    guard isRepoName(name) else { return Copy.watchingMustBeOwnerName(name: name, bundle: bundle, locale: locale) }
    if others.contains(where: { $0.lowercased() == name.lowercased() }) { return Copy.watchingAlreadyWatched(name: name, bundle: bundle, locale: locale) }
    if let clash = others.first(where: { repoFolder($0) == repoFolder(name) }) {
        return Copy.watchingSameFolder(name: name, other: clash, bundle: bundle, locale: locale)
    }
    return nil
}

/// What the engine would refuse in the whole list; nil when it is fine (an empty list is fine: nothing is watched yet). The first problem, in list order.
public func reposProblem(_ names: [String], bundle: Bundle? = nil, locale: Locale = .current) -> String? {
    for (index, name) in names.enumerated() {
        if let problem = repoProblem(name, joining: Array(names[..<index]), bundle: bundle, locale: locale) { return problem }
    }
    return nil
}

/// The watched repos in the file, in order; nil when `json` is not a JSON object.
public func configRepoNames(json: Data) -> [String]? {
    guard let file = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else { return nil }
    return (file["repos"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
}

/// The epics of one repo that stop when it leaves the config: the ones running, queued or waiting for a person.
public struct RepoEpics: Equatable {
    public var running = 0
    public var queued = 0
    public var needsYou = 0

    public var isNone: Bool { running + queued + needsYou == 0 }

    /// "1 running · 2 queued · 1 needs you"; empty when none.
    public func line(separator: String = " · ", bundle: Bundle? = nil, locale: Locale = .current) -> String {
        [
            running > 0 ? Copy.watchingRunning(count: running, bundle: bundle, locale: locale) : nil,
            queued > 0 ? Copy.watchingQueued(count: queued, bundle: bundle, locale: locale) : nil,
            needsYou > 0 ? Copy.watchingNeedsYou(count: needsYou, bundle: bundle, locale: locale) : nil,
        ].compactMap { $0 }.joined(separator: separator)
    }
}

/// nil without a snapshot: with Carrier stopped nobody knows.
public func repoEpics(_ repo: String, snapshot: PanelSnapshot?) -> RepoEpics? {
    guard let snapshot else { return nil }
    return RepoEpics(
        running: snapshot.epics.filter { $0.repo == repo && $0.status == .running }.count,
        queued: snapshot.queue.filter { $0.repo == repo }.count,
        needsYou: snapshot.epics.filter { $0.repo == repo && $0.status == .needsHuman }.count
    )
}

/// The confirmation under the list when the person presses ✕ on a repo. `appliesNow`: Carrier applies the change while it runs
/// (`appliesWhileRunning`); else it reads the list when it starts.
public func removalText(_ epics: RepoEpics?, appliesNow: Bool, bundle: Bundle? = nil, locale: Locale = .current) -> String {
    guard let epics else {
        return appliesNow ? Copy.watchingRemovalUnknown(when: .now, bundle: bundle, locale: locale) : Copy.watchingRemovalUnknown(when: .other, bundle: bundle, locale: locale)
    }
    if epics.isNone {
        return appliesNow ? Copy.watchingRemovalNone(when: .now, bundle: bundle, locale: locale) : Copy.watchingRemovalNone(when: .other, bundle: bundle, locale: locale)
    }
    let line = epics.line(separator: ", ", bundle: bundle, locale: locale)
    return appliesNow
        ? Copy.watchingRemovalSome(when: .now, epics: line, bundle: bundle, locale: locale) : Copy.watchingRemovalSome(when: .other, epics: line, bundle: bundle, locale: locale)
}

public struct RepoRow: Equatable, Identifiable {
    public enum Health: Equatable { case ok, error, unknown }

    public var name: String
    public var health: Health
    /// "Checked 2m ago", or the engine's error for a repo GitHub refused
    public var line: String
    /// nil when nobody knows (Carrier is stopped, or it has not loaded the repo)
    public var epics: RepoEpics?
    /// in the draft but not in the file yet
    public var isNew: Bool
    /// the running engine has loaded it, so its epics and last check are known
    public var isLoaded = false
    /// whether the repo follows the list of extra reviewers of Roles, has its own or has none
    public var extras = RepoExtraReviewers.sameAsEverywhere
    public var id: String { name }

    public var owner: String { String(name.split(separator: "/").first ?? "") }
    public var repo: String { String(name.split(separator: "/").last ?? "") }
    public var gitHubURL: URL? { URL(string: "https://github.com/\(name)") }
    /// Where Carrier keeps its clone: `<folder>/engine/repos/owner/name`; `engine` is the engine's folder.
    public func clonePath(engine: String) -> String { "\(engine)/repos/\(name)" }
}

/// `path` with the home folder as `~`.
public func tildePath(_ path: String, home: String = NSHomeDirectory()) -> String {
    path == home ? "~" : path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
}

/// One row per repo of the `draft`; `saved` is the file's list, `snapshot` what Carrier says (nil when stopped).
public func repoRows(draft: [String], saved: [String], snapshot: PanelSnapshot?, bundle: Bundle? = nil, locale: Locale = .current) -> [RepoRow] {
    draft.map { name in
        let epics = repoEpics(name, snapshot: snapshot)
        if saved.contains(name) == false {
            return RepoRow(name: name, health: .unknown, line: Copy.watchingNotCheckedYet(bundle: bundle, locale: locale), epics: nil, isNew: true)
        }
        guard let snapshot else {
            return RepoRow(name: name, health: .unknown, line: Copy.watchingCarrierStopped(bundle: bundle, locale: locale), epics: nil, isNew: false)
        }
        guard let watched = snapshot.watched?.first(where: { $0.repo == name }) else {
            return RepoRow(name: name, health: .unknown, line: Copy.watchingNotInUse(bundle: bundle, locale: locale), epics: epics, isNew: false)
        }
        if watched.ok == false {
            return RepoRow(
                name: name, health: .error, line: watched.error ?? Copy.watchingGitHubRefused(bundle: bundle, locale: locale), epics: epics, isNew: false, isLoaded: true)
        }
        guard let at = watched.lastCheckedAt else {
            return RepoRow(name: name, health: .unknown, line: Copy.watchingNotCheckedYet(bundle: bundle, locale: locale), epics: epics, isNew: false, isLoaded: true)
        }
        return RepoRow(
            name: name, health: .ok, line: Copy.watchingCheckedAgo(ago: agoLine(at, now: snapshot.now, bundle: bundle, locale: locale), bundle: bundle, locale: locale),
            epics: epics, isNew: false, isLoaded: true)
    }
}
