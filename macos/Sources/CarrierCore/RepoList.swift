import Foundation

// The Repos tab as plain values: the `repos` of `config.json` the app lets the person change (which repos are watched), their
// rows and the text of the confirmation to stop watching one. Nothing here reads or shows a repo's own settings: a repo's other
// fields in the file are kept exactly as they are.

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
public func repoProblem(_ name: String, joining others: [String]) -> String? {
    guard isRepoName(name) else { return "\(name) must be owner/name" }
    if others.contains(where: { $0.lowercased() == name.lowercased() }) { return "\(name) is already watched" }
    if let clash = others.first(where: { repoFolder($0) == repoFolder(name) }) {
        return "\(name) has the same folder name as \(clash); Solve's worktree paths have no owner"
    }
    return nil
}

/// What the engine would refuse in the whole list; nil when it is fine. The first problem, in list order.
public func reposProblem(_ names: [String]) -> String? {
    if names.isEmpty { return "The config needs at least one repo." }
    for (index, name) in names.enumerated() {
        if let problem = repoProblem(name, joining: Array(names[..<index])) { return problem }
    }
    return nil
}

/// The watched repos in the file, in order; nil when `json` is not a JSON object.
public func configRepoNames(json: Data) -> [String]? {
    guard let file = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else { return nil }
    return (file["repos"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
}

/// `json` with `names` as its repos. A repo that was there keeps its entry as it is; a new one is `{"name": …}`; everything else
/// in the file is left alone. nil when `json` is not a JSON object or the list has a problem: like `EngineConfig.applied`, the
/// app never makes a config file.
public func applyingRepos(_ names: [String], to json: Data) -> Data? {
    guard reposProblem(names) == nil, var file = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else { return nil }
    let kept = file["repos"] as? [[String: Any]] ?? []
    file["repos"] = names.map { name in kept.first { $0["name"] as? String == name } ?? ["name": name] }
    return try? JSONSerialization.data(withJSONObject: file, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
}

/// The epics of one repo that stop when it leaves the config: the ones running, queued or waiting for a person.
public struct RepoEpics: Equatable {
    public var running = 0
    public var queued = 0
    public var needsYou = 0

    public var isNone: Bool { running + queued + needsYou == 0 }

    /// "1 running · 2 queued · 1 needs you"; empty when none.
    public func line(separator: String = " · ") -> String {
        [running > 0 ? "\(running) running" : nil, queued > 0 ? "\(queued) queued" : nil, needsYou > 0 ? "\(needsYou) needs you" : nil]
            .compactMap { $0 }.joined(separator: separator)
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

/// The confirmation under the list when the person presses ✕ on a repo.
public func removalText(_ epics: RepoEpics?) -> String {
    let when = " It takes effect when you save; Revert puts it back."
    guard let epics else {
        return "Its epics, if it has any, stop where they are, untouched, and continue if you add the repo again. Nothing is deleted." + when
    }
    if epics.isNone { return "It has no epics. You can add it again whenever you want." + when }
    return "It has epics (\(epics.line(separator: ", "))). They stop where they are, untouched, and continue if you add the repo again. Nothing is deleted." + when
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
    public var id: String { name }

    public var owner: String { String(name.split(separator: "/").first ?? "") }
    public var repo: String { String(name.split(separator: "/").last ?? "") }
    public var gitHubURL: URL? { URL(string: "https://github.com/\(name)") }
    /// Where Carrier keeps its clone: `<root>/repos/owner/name`.
    public func clonePath(root: String) -> String { "\(root)/repos/\(name)" }
}

/// `path` with the home folder as `~`.
public func tildePath(_ path: String, home: String = NSHomeDirectory()) -> String {
    path == home ? "~" : path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
}

/// One row per repo of the `draft`; `saved` is the file's list, `snapshot` what Carrier says (nil when stopped).
public func repoRows(draft: [String], saved: [String], snapshot: PanelSnapshot?) -> [RepoRow] {
    draft.map { name in
        let epics = repoEpics(name, snapshot: snapshot)
        if saved.contains(name) == false {
            return RepoRow(name: name, health: .unknown, line: "Not checked yet · Carrier looks at it after it starts with the new list", epics: nil, isNew: true)
        }
        guard let snapshot else { return RepoRow(name: name, health: .unknown, line: "Carrier is stopped", epics: nil, isNew: false) }
        guard let watched = snapshot.watched?.first(where: { $0.repo == name }) else {
            return RepoRow(name: name, health: .unknown, line: "Carrier has not loaded it yet · it does after a restart", epics: epics, isNew: false)
        }
        if watched.ok == false {
            return RepoRow(name: name, health: .error, line: watched.error ?? "GitHub refused it", epics: epics, isNew: false)
        }
        guard let at = watched.lastCheckedAt else { return RepoRow(name: name, health: .unknown, line: "Not checked yet", epics: epics, isNew: false) }
        return RepoRow(name: name, health: .ok, line: "Checked \(agoLine(at, now: snapshot.now))", epics: epics, isNew: false)
    }
}
