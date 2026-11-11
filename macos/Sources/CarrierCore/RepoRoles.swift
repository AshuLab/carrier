import Foundation

// "Who works here" on a repo's page, as plain values: what each role of the repo resolves to, from the global `agents` and the repo's
// own `agents` in `config.json`. This only reads; writing is RepoRoleSave.swift.

public enum AgentRole: String, CaseIterable, Equatable {
    case author, reviewer, leadReviewer

    public var title: String {
        switch self {
        case .author: "Author"
        case .reviewer: "Reviewer"
        case .leadReviewer: "Lead reviewer"
        }
    }
}

/// The persona of a role: a name, a prompt, or both. A repo's persona replaces the global one whole.
public struct RolePersona: Equatable {
    public var name: String?
    public var prompt: String?

    public init(name: String? = nil, prompt: String? = nil) {
        self.name = name
        self.prompt = prompt
    }
}

/// The fields of a role, each one optional because a repo sets only some of them.
public struct RoleFields: Equatable {
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
    public var text: String {
        let parts = [profile, provider, model, effort].compactMap { $0 }.filter { $0.isEmpty == false }
        return parts.isEmpty ? "Not set" : parts.joined(separator: " · ")
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
    public var title: String { role.title }
}

/// What the app reads of the config for a repo's roles.
public struct RepoRoles: Equatable {
    /// the names under `profiles`, for the Identity field
    public var profiles: [String]
    /// Author and Reviewer, and the Lead reviewer only when the global config has one
    public var rows: [RepoRoleRow]
}

/// The roles of `repo`; nil when `json` is not a JSON object (the engine is not configured).
public func repoRoles(json: Data, repo: String) -> RepoRoles? {
    guard let file = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else { return nil }
    let global = file["agents"] as? [String: Any] ?? [:]
    let entry = (file["repos"] as? [[String: Any]])?.first { $0["name"] as? String == repo }
    let own = entry?["agents"] as? [String: Any] ?? [:]
    let roles = AgentRole.allCases.filter { $0 != .leadReviewer || global[$0.rawValue] is [String: Any] }
    return RepoRoles(
        profiles: (file["profiles"] as? [String: Any] ?? [:]).keys.sorted(),
        rows: roles.map { role in
            let inherited = roleFields(global[role.rawValue])
            let mine = roleFields(own[role.rawValue])
            return RepoRoleRow(role: role, value: inherited.overridden(by: mine), inherited: inherited, own: mine)
        }
    )
}

func roleFields(_ value: Any?) -> RoleFields {
    guard let role = value as? [String: Any] else { return RoleFields() }
    func text(_ key: String) -> String? { (role[key] as? String).flatMap { $0.isEmpty ? nil : $0 } }
    let persona = (role["persona"] as? [String: Any]).map { RolePersona(name: $0["name"] as? String, prompt: $0["prompt"] as? String) }
    return RoleFields(profile: text("profile"), provider: text("provider"), model: text("model"), effort: text("effort"), persona: persona)
}
