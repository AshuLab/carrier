import Foundation

// The Watching page as plain values (docs/macos/settings-carrier.md#watching): the order of the list of watched repos, the projects
// the person can pick to watch and why one cannot be picked, and the words of the banner that says the engine kept its settings. The rows themselves,
// and what is written to `engine.json`, are `RepoList.swift`'s.

/// The repos GitHub refused first, then by name, so the page opens on what is wrong.
public func watchingOrder(_ rows: [RepoRow]) -> [RepoRow] {
    rows.sorted { a, b in
        let (aWrong, bWrong) = (a.health == .error, b.health == .error)
        return aWrong != bWrong ? aWrong : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }
}

/// A project of the picker "Watch a project": `reason` is why it cannot be picked, nil when it can.
public struct WatchChoice: Equatable, Identifiable {
    public let project: ProjectRow
    public let reason: String?

    public var id: String { project.path }
    public var canWatch: Bool { reason == nil }
}

/// The projects to offer, those Carrier can watch first and then by name. A project already watched is not offered; one with no GitHub origin, or whose
/// repository the engine would refuse next to the ones watched (the same folder name), is offered off with the reason. A clone that is running is not a project yet.
public func watchChoices(projects: [ProjectRow], watched: [String], bundle: Bundle? = nil, locale: Locale = .current) -> [WatchChoice] {
    let choices: [WatchChoice] = projects.compactMap { project in
        guard project.clone == nil else { return nil }
        guard let repo = project.repo else { return WatchChoice(project: project, reason: Copy.watchingNoOrigin(bundle: bundle, locale: locale)) }
        if isWatched(repo, in: watched) { return nil }
        return WatchChoice(project: project, reason: repoProblem(repo, joining: watched, bundle: bundle, locale: locale))
    }
    return choices.sorted { a, b in
        a.canWatch != b.canWatch ? a.canWatch : a.project.name.localizedCaseInsensitiveCompare(b.project.name) == .orderedAscending
    }
}

/// What the page says when the engine read the saved `engine.json` and refused it: it kept the settings it had, so what was saved is not in use yet.
/// `detail` says what is wrong in words when the reason is one the page knows; `raw` is the engine's own, always kept so nothing is lost; `fix` is the page that mends it.
public struct RefusalBanner: Equatable {
    public let title: String
    public let detail: String?
    public let raw: String
    public let fix: SettingsPage?
    /// After the detail: what the refusal means for what was just saved.
    public let consequence: String
    public let fixTitle: String?
}

/// The banner for the engine's refusal of the saved file. A `config.problem` about a failover step of a role is told in words, from its `path` and `problem`,
/// and sent to Agents, where it is mended; any other refusal is shown as the engine says it.
public func refusalBanner(_ reason: Refusal, bundle: Bundle? = nil, locale: Locale = .current) -> RefusalBanner {
    let path = reason.params["path"]?.text.split(separator: ".").map(String.init) ?? []
    guard reason.has("config.problem"), path.count == 4, path[0] == "failover", path[1] == "roles", let index = Int(path[3]) else {
        return refusalBanner(detail: nil, raw: reason.shown(bundle: bundle, locale: locale), fix: nil, bundle: bundle, locale: locale)
    }
    let role = AgentRole(rawValue: path[2])?.title(bundle: bundle, locale: locale) ?? path[2]
    let detail: String? =
        switch reason.params["problem"]?.text {
        case "stepOwnRole": Copy.watchingRefusalStep(problem: .stepOwnRole, role: role, step: index + 1, bundle: bundle, locale: locale)
        case "stepRepeated": Copy.watchingRefusalStep(problem: .stepRepeated, role: role, step: index + 1, bundle: bundle, locale: locale)
        case "providerNotDeclared": Copy.watchingRefusalStep(problem: .providerNotDeclared, role: role, step: index + 1, bundle: bundle, locale: locale)
        default: nil
        }
    return refusalBanner(detail: detail, raw: reason.shown(bundle: bundle, locale: locale), fix: .agents, bundle: bundle, locale: locale)
}

private func refusalBanner(detail: String?, raw: String, fix: SettingsPage?, bundle: Bundle?, locale: Locale) -> RefusalBanner {
    RefusalBanner(
        title: Copy.watchingRefusalTitle(bundle: bundle, locale: locale), detail: detail, raw: raw, fix: fix,
        consequence: Copy.watchingRefusalConsequence(bundle: bundle, locale: locale), fixTitle: fix.map { Copy.watchingOpenPage(page: $0.title(bundle: bundle, locale: locale), bundle: bundle, locale: locale) })
}
