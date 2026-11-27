import Foundation

// "Who works here" on a repo's page, as plain values: what each role of the repo resolves to, from the global `agents` and the repo's
// own `agents` in `engine.json`. This only reads; a change is a request to the engine (`EngineConfigChange.repoRole`).

public enum AgentRole: String, CaseIterable, Equatable, Sendable {
    case author, reviewer, leadReviewer

    public func title(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        switch self {
        case .author: Copy.rolesRole(which: .author, bundle: bundle, locale: locale)
        case .reviewer: Copy.rolesRole(which: .reviewer, bundle: bundle, locale: locale)
        case .leadReviewer: Copy.rolesRole(which: .leadReviewer, bundle: bundle, locale: locale)
        }
    }
}

/// The persona of a role: a name, a prompt, or both. A repo's persona replaces the global one whole.
public struct RolePersona: Equatable, Sendable {
    public var name: String?
    public var prompt: String?

    public init(name: String? = nil, prompt: String? = nil) {
        self.name = name
        self.prompt = prompt
    }
}

/// The fields of a role, each one optional because a repo sets only some of them.
public struct RoleFields: Equatable, Sendable {
    public var profile: String?
    public var provider: String?
    public var model: String?
    public var effort: String?
    public var persona: RolePersona?

    public init(profile: String? = nil, provider: String? = nil, model: String? = nil, effort: String? = nil, persona: RolePersona? = nil) {
        self.profile = profile
        self.provider = provider
        self.model = model
        self.effort = effort
        self.persona = persona
    }

    public var isEmpty: Bool { self == RoleFields() }

    /// `<profile> · <provider> · <model> · <effort>`, leaving out what is not set; "Not set" when nothing is.
    public func text(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        let parts = [profile, provider, model, effort].compactMap { $0 }.filter { $0.isEmpty == false }
        return parts.isEmpty ? Copy.rolesNotSet(bundle: bundle, locale: locale) : parts.joined(separator: " · ")
    }

    /// These fields, each one the `own` one when the repo has it, else this.
    func overridden(by own: RoleFields) -> RoleFields {
        RoleFields(
            profile: own.profile ?? profile, provider: own.provider ?? provider, model: own.model ?? model,
            effort: own.effort ?? effort, persona: own.persona ?? persona
        )
    }
}

public struct RepoRoleRow: Equatable, Identifiable {
    public var role: AgentRole
    /// what the role is for this repo: the repo's own fields over the global ones
    public var value: RoleFields
    /// what the global config gives it
    public var inherited: RoleFields
    /// the repo's own fields; empty when it has no entry
    public var own: RoleFields
    public var id: String { role.rawValue }

    public var isOwn: Bool { own.isEmpty == false }
    public func title(bundle: Bundle? = nil, locale: Locale = .current) -> String { role.title(bundle: bundle, locale: locale) }
}

/// A repo's extra reviewers: its `agents.extraReviewers` replaces the global map whole, so there are three states and nothing in between.
public enum RepoExtraReviewers: Equatable, CaseIterable, Sendable {
    /// no key: the list of Roles runs there
    case sameAsEverywhere
    /// a map of its own
    case ownList
    /// `{}`: only the Reviewer reviews there
    case noExtras
}

extension RepoExtraReviewers {
    /// The state in a word, as the group's chip says it.
    public func title(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        switch self {
        case .sameAsEverywhere: Copy.rolesSameAsEverywhere(bundle: bundle, locale: locale)
        case .ownList: Copy.watchingOwnList(bundle: bundle, locale: locale)
        case .noExtras: Copy.watchingNone(bundle: bundle, locale: locale)
        }
    }

    /// What the state means, and when the app cannot change it (the engine does not announce `extraReviewers`) that it only shows it.
    public func footer(editable: Bool, bundle: Bundle? = nil, locale: Locale = .current) -> String {
        let meaning =
            switch self {
            case .sameAsEverywhere: Copy.watchingMoreFooter(which: .sameAsEverywhere, bundle: bundle, locale: locale)
            case .ownList: Copy.watchingMoreFooter(which: .ownList, bundle: bundle, locale: locale)
            case .noExtras: Copy.watchingMoreFooter(which: .noExtras, bundle: bundle, locale: locale)
            }
        return editable ? meaning : meaning + " " + Copy.watchingMoreReadOnly(bundle: bundle, locale: locale)
    }
}

/// What the app reads of the config for a repo's roles.
public struct RepoRoles: Equatable {
    /// the names under `profiles`, for the Identity field
    public var profiles: [String]
    /// Author and Reviewer, and the Lead reviewer only when the global config has one
    public var rows: [RepoRoleRow]
    public var extras: RepoExtraReviewers
}

/// The roles of `repo`; nil when `json` is not a JSON object (the engine is not configured).
public func repoRoles(json: Data, repo: String) -> RepoRoles? {
    guard let file = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else { return nil }
    let global = file["agents"] as? [String: Any] ?? [:]
    let entry = (file["repos"] as? [[String: Any]])?.first { $0["name"] as? String == repo }
    let own = entry?["agents"] as? [String: Any] ?? [:]
    let roles = AgentRole.allCases.filter { $0 != .leadReviewer || global[$0.rawValue] is [String: Any] }
    let extras: RepoExtraReviewers =
        switch own["extraReviewers"] as? [String: Any] {
        case nil: .sameAsEverywhere
        case let map? where map.isEmpty: .noExtras
        default: .ownList
        }
    return RepoRoles(
        profiles: (file["profiles"] as? [String: Any] ?? [:]).keys.sorted(),
        rows: roles.map { role in
            let inherited = roleFields(global[role.rawValue])
            let mine = roleFields(own[role.rawValue])
            return RepoRoleRow(role: role, value: inherited.overridden(by: mine), inherited: inherited, own: mine)
        },
        extras: extras
    )
}

func roleFields(_ value: Any?) -> RoleFields {
    guard let role = value as? [String: Any] else { return RoleFields() }
    func text(_ key: String) -> String? { (role[key] as? String).flatMap { $0.isEmpty ? nil : $0 } }
    let persona = (role["persona"] as? [String: Any]).map { RolePersona(name: $0["name"] as? String, prompt: $0["prompt"] as? String) }
    return RoleFields(profile: text("profile"), provider: text("provider"), model: text("model"), effort: text("effort"), persona: persona)
}

/// The Roles page as it is for `repo`: each role's fields are the global ones with the repo's own over them (a persona replaces the global one whole), so the
/// rail, the pictures and the readiness of Roles read a repo's roles as they read the global ones. The Lead reviewer is in it only as the global config has it, off
/// included; one the repo names alone is not a role of the repo. The extra reviewers are not on the rail but in `repoExtraReviewers`. nil when `config` is not a JSON object.
public func repoRolesPage(config: Data, providers: Data?, bots: ForgeBots, repo: String, bundle: Bundle? = nil, locale: Locale = .current) -> RolesPage? {
    guard var page = repoPage(config: config, providers: providers, bots: bots, repo: repo, bundle: bundle, locale: locale) else { return nil }
    page.rows.removeAll { $0.slot.isExtra }
    return page
}

/// The extra reviewers that run in `repo`, in the order of the map: the repo's own map when it has the key (empty for `{}`), else the global one, each with its name,
/// type, identity and model as the Roles page reads it. nil when `config` is not a JSON object.
public func repoExtraReviewers(config: Data, providers: Data?, bots: ForgeBots, repo: String, bundle: Bundle? = nil, locale: Locale = .current) -> [RoleRow]? {
    repoPage(config: config, providers: providers, bots: bots, repo: repo, bundle: bundle, locale: locale)?.rows.filter { $0.slot.isExtra }
}

private func repoPage(config: Data, providers: Data?, bots: ForgeBots, repo: String, bundle: Bundle?, locale: Locale) -> RolesPage? {
    guard var file = (try? JSONSerialization.jsonObject(with: config)) as? [String: Any] else { return nil }
    var agents = file["agents"] as? [String: Any] ?? [:]
    let position = (file["repos"] as? [[String: Any]])?.firstIndex { $0["name"] as? String == repo }
    let own = position.flatMap { (file["repos"] as? [[String: Any]])?[$0]["agents"] as? [String: Any] } ?? [:]
    for (role, fields) in own where role != "extraReviewers" {
        guard var merged = agents[role] as? [String: Any], let mine = fields as? [String: Any] else { continue }
        for (key, value) in mine { merged[key] = value }
        agents[role] = merged
    }
    // the map replaces the global one whole, and keeps the order of the repo's own
    var extraKeys: [String]?
    if let map = own["extraReviewers"] as? [String: Any], let position {
        agents["extraReviewers"] = map
        extraKeys = jsonKeys(in: config, at: ["repos", String(position), "agents", "extraReviewers"])
    }
    file["agents"] = agents
    guard let merged = try? JSONSerialization.data(withJSONObject: file) else { return nil }
    return rolesPage(config: merged, providers: providers, bots: bots, extraKeys: extraKeys, bundle: bundle, locale: locale)
}
