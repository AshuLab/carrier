import Foundation

// The Identities page of Settings (docs/macos/settings-carrier.md#identities): every GitHub profile a role can sign as (the bots of the Agent Forge
// registry and the person's own gh login), the roles that sign as each one (the extra reviewers too), globally and as a repo's own role, and the repos where it can mint a token,
// from the doctor's checks as Watching reads them. This only reads; the page writes nothing, a role picks its identity on its own screen.

extension RoleIdentity {
    /// What the window's history knows the identity by (the path of its screen): `bot:<name>` for a bot of the registry, `gh` for the person's own login.
    public var key: String? {
        switch self {
        case .forge(let bot): "bot:" + bot
        case .gh: "gh"
        case .missing, .unset: nil
        }
    }
}

/// A role that signs as an identity: the global role (`repo` is nil) or the role a repo has of its own. An extra reviewer is a role too, by its key, in the global map or in a repo's own.
public struct IdentityRoleLink: Equatable, Identifiable, Sendable {
    public var slot: RoleSlot
    /// what an extra reviewer is called; nil for the fixed roles
    public var name: String?
    public var repo: String?
    public var id: String { repo.map { "\($0)/\(slot.name)" } ?? slot.name }

    public init(slot: RoleSlot, name: String? = nil, repo: String? = nil) { (self.slot, self.name, self.repo) = (slot, name, repo) }

    /// `Reviewer`, or `Reviewer in acme/api` for a repo's own; an extra reviewer by its name (its key while the entry has none).
    public func title(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        let name = slot.agentRole?.title(bundle: bundle, locale: locale) ?? (self.name.flatMap { $0.isEmpty ? nil : $0 } ?? slot.name)
        return repo.map { Copy.identitiesRoleIn(role: name, repo: $0, bundle: bundle, locale: locale) } ?? name
    }

    public func detail(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        repo == nil ? Copy.identitiesGlobalSetting(bundle: bundle, locale: locale) : Copy.identitiesRepoSetting(bundle: bundle, locale: locale)
    }

    /// Where the link opens: Roles' screen of the role, the repo's screen of a fixed role the repo has of its own, or the repo's screen for an entry of its own list of extra reviewers.
    public var place: SettingsPlace {
        switch (repo, slot.agentRole) {
        case (nil, _): SettingsPlace(.roles, path: [slot.name])
        case (let repo?, let role?): SettingsPlace(.watching, path: [repo, role.rawValue])
        case (let repo?, nil): SettingsPlace(.watching, path: [repo])
        }
    }
}

/// One watched repo on an identity's screen: the doctor's check of whether it can mint a token there.
public struct IdentityRepo: Equatable, Identifiable {
    /// `title` is the repo's name
    public var check: RepoCheckRow
    /// no role signs as the identity in this repo, so the doctor made no check
    public var unused: Bool
    public var id: String { check.title }
}

/// What a row says of where the identity can sign.
public enum IdentityStanding: Equatable {
    /// nothing to say: the doctor has not run, or no role signs as it in a watched repo
    case unchecked
    case checking
    /// the doctor could not answer, or refused the config
    case unanswered
    case canSign
    /// the watched repos where it cannot mint a token
    case cannotSign([String])
}

public struct IdentityRow: Equatable, Identifiable {
    public var identity: RoleIdentity
    /// the bot's name; the person's own login has none the app knows
    public var bot: String?
    /// the bot's GitHub App id, when the registry has a valid one
    public var appId: String?
    public var signsAs: [IdentityRoleLink]
    public var repos: [IdentityRepo]
    public var standing: IdentityStanding
    public var id: String { identity.key ?? "" }

    public func title(bundle: Bundle? = nil, locale: Locale = .current) -> String { bot ?? Copy.rolesIdentityGh(bundle: bundle, locale: locale) }

    /// What the identity is: a bot of Agent Forge or the person's own account.
    public func kind(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        bot == nil ? Copy.rolesOwnAccount(bundle: bundle, locale: locale) : Copy.rolesIdentityForge(bundle: bundle, locale: locale)
    }

    /// The line under the kind, when the doctor has something to say about where it signs.
    public func standingLine(bundle: Bundle? = nil, locale: Locale = .current) -> String? {
        switch standing {
        case .unchecked, .canSign: nil
        case .checking: Copy.watchingChecking(bundle: bundle, locale: locale)
        case .unanswered: Copy.identitiesCouldNotCheck(bundle: bundle, locale: locale)
        case .cannotSign(let repos): Copy.identitiesCannotSign(repos: repos.joined(separator: ", "), bundle: bundle, locale: locale)
        }
    }

    /// `GitHub App 1000001` for a bot that has an id.
    public func appLine(bundle: Bundle? = nil, locale: Locale = .current) -> String? {
        appId.map { Copy.identitiesAppId(id: $0, bundle: bundle, locale: locale) }
    }

    /// The bot's page on GitHub; nil for the person's own login and for a name that is not one GitHub accepts.
    public var gitHubURL: URL? {
        guard let bot, isGithubLogin(bot) else { return nil }
        return URL(string: "https://github.com/apps/\(bot.lowercased())")
    }
}

public struct IdentitiesPage: Equatable {
    public var rows: [IdentityRow]
    /// said when the list of bots is empty because the registry is not there or does not read
    public var registryNote: String?
    /// said while the doctor runs or when it could not answer
    public var doctorNote: String?
}

/// The page for `config`; nil when it is not a JSON object (the engine is not configured). Each role is looked up in the global `agents` and in the
/// `agents` of every watched repo; a profile that is not in the registry belongs to no identity (its role says so on its own screen).
public func identitiesPage(config: Data, bots: ForgeBots, doctor: DoctorState, bundle: Bundle? = nil, locale: Locale = .current) -> IdentitiesPage? {
    guard let file = (try? JSONSerialization.jsonObject(with: config)) as? [String: Any] else { return nil }
    let profiles = file["profiles"] as? [String: Any] ?? [:]
    let global = file["agents"] as? [String: Any] ?? [:]
    let repos = file["repos"] as? [[String: Any]] ?? []
    // the roles the engine runs: the Lead reviewer only while the global config has one, as a repo's roles are
    let roles = AgentRole.allCases.filter { $0 != .leadReviewer || global[$0.rawValue] is [String: Any] }

    func key(of profile: String?) -> String? {
        guard let profile, let found = profiles[profile] as? [String: Any] else { return nil }
        switch found["kind"] as? String {
        case "gh": return "gh"
        case "forge": return (found["agent"] as? String).flatMap { bots.names.contains($0) ? "bot:" + $0 : nil }
        default: return nil
        }
    }

    /// The entries of a map of extra reviewers in the order of the file (`jsonKeys` reads it, since a dictionary has none).
    func extras(_ map: [String: Any], at path: [String]) -> [(key: String, name: String, profile: String?)] {
        (jsonKeys(in: config, at: path) ?? []).compactMap { key in
            (map[key] as? [String: Any]).map { (key, $0["name"] as? String ?? "", $0["profile"] as? String) }
        }
    }
    let globalExtras = (global["extraReviewers"] as? [String: Any]).map { extras($0, at: ["agents", "extraReviewers"]) } ?? []

    let identities: [(identity: RoleIdentity, bot: String?)] = bots.names.map { (.forge($0), $0) } + [(.gh, nil)]
    let rows = identities.map { entry -> IdentityRow in
        let identityKey = entry.identity.key
        let names = Set(profiles.keys.filter { key(of: $0) == identityKey })
        var links: [IdentityRoleLink] = []
        var used: Set<String> = []
        for role in roles where key(of: roleFields(global[role.rawValue]).profile) == identityKey { links.append(IdentityRoleLink(slot: RoleSlot(role))) }
        for extra in globalExtras where key(of: extra.profile) == identityKey { links.append(IdentityRoleLink(slot: .extra(key: extra.key), name: extra.name)) }
        for (position, repo) in repos.enumerated() {
            guard let name = repo["name"] as? String else { continue }
            let own = repo["agents"] as? [String: Any] ?? [:]
            for role in roles {
                let profile = roleFields(own[role.rawValue]).profile ?? roleFields(global[role.rawValue]).profile
                guard key(of: profile) == identityKey else { continue }
                used.insert(name)
                if roleFields(own[role.rawValue]).profile != nil { links.append(IdentityRoleLink(slot: RoleSlot(role), repo: name)) }
            }
            // a repo's own map replaces the global one whole, an empty one included
            let ownMap = own["extraReviewers"] as? [String: Any]
            for extra in ownMap.map({ extras($0, at: ["repos", String(position), "agents", "extraReviewers"]) }) ?? globalExtras where key(of: extra.profile) == identityKey {
                used.insert(name)
                if ownMap != nil { links.append(IdentityRoleLink(slot: .extra(key: extra.key), name: extra.name, repo: name)) }
            }
        }
        var checks: [DoctorCheck] = []
        if case .checks(let all) = doctor { checks = all }
        let rows = repos.compactMap { $0["name"] as? String }.map { repo -> IdentityRepo in
            guard used.contains(repo) else {
                return IdentityRepo(check: RepoCheckRow(title: repo, status: .waiting, detail: Copy.identitiesNoRoleHere(bundle: bundle, locale: locale)), unused: true)
            }
            let found = checks.first { isMintCheck($0, repo: repo) && $0.profiles?.contains { names.contains($0) } == true }
            var row = checkRow(repo, found, missing: Copy.watchingNotCheckedYet(bundle: bundle, locale: locale), bundle: bundle, locale: locale)
            if row.status == .ok { row.detail = row.detail ?? Copy.identitiesCanMint(bundle: bundle, locale: locale) }
            return IdentityRepo(check: row, unused: false)
        }
        let failing = rows.filter { $0.check.status == .fail }.map(\.id)
        let standing: IdentityStanding
        switch doctor {
        case .idle: standing = .unchecked
        case .running: standing = .checking
        case .unknown, .refused: standing = .unanswered
        case .checks: standing = failing.isEmpty == false ? .cannotSign(failing) : rows.contains { $0.check.status == .ok } ? .canSign : .unchecked
        }
        return IdentityRow(identity: entry.identity, bot: entry.bot, appId: entry.bot.flatMap { bots.appIds[$0] }, signsAs: links, repos: rows, standing: standing)
    }
    return IdentitiesPage(rows: rows, registryNote: bots.note, doctorNote: doctorNote(doctor, bundle: bundle, locale: locale))
}
