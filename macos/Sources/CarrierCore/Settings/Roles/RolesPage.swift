import Foundation

// The Roles page of Settings (docs/specs/agents-in-settings.md): the roles of `engine.json` (the three fixed ones and the extra reviewers) with their identity, provider, model,
// effort, persona and failover steps, as plain values. This only reads; the file is never written from here.

/// The bots of the Agent Forge registry: names only, never a key.
public struct ForgeBots: Equatable {
    public var names: [String]
    /// The GitHub App id of each bot that has a valid one (digits only), by the bot's name: where its picture is (`forgeAvatarURL`).
    public var appIds: [String: String] = [:]
    /// said on the page when the list is empty because the registry is not there or does not read
    public var note: String?
}

/// Where Agent Forge keeps its registry: `$AGENT_FORGE_CONFIG`, else `agent-forge/agents.json` under `$XDG_CONFIG_HOME` or `~/.config`.
/// (The engine's wizard also tries `./agents.json`; a Mac app has no working folder worth looking in.)
public func forgeRegistryPath(environment: [String: String] = ProcessInfo.processInfo.environment, home: String = NSHomeDirectory()) -> String {
    if let path = environment["AGENT_FORGE_CONFIG"], path.isEmpty == false { return path }
    let config = environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? home + "/.config"
    return config + "/agent-forge/agents.json"
}

/// The registry's bytes, read each time; nil when the file is not there or cannot be read.
public func currentForgeRegistry(environment: [String: String] = ProcessInfo.processInfo.environment, home: String = NSHomeDirectory()) -> Data? {
    try? Data(contentsOf: URL(fileURLWithPath: forgeRegistryPath(environment: environment, home: home)))
}

/// The names in `registry` (`{ "agents": [{ "name": … }] }`), as the engine's `readForgeAgents` reads them. No file, or one that is not a JSON
/// object, gives no names and a note, not an error.
public func forgeBots(registry: Data?, bundle: Bundle? = nil, locale: Locale = .current) -> ForgeBots {
    guard let registry else {
        return ForgeBots(names: [], note: Copy.rolesNoRegistry(bundle: bundle, locale: locale))
    }
    guard let file = (try? JSONSerialization.jsonObject(with: registry)) as? [String: Any] else {
        return ForgeBots(names: [], note: Copy.rolesRegistryUnreadable(bundle: bundle, locale: locale))
    }
    let entries = file["agents"] as? [[String: Any]] ?? []
    let names = entries.compactMap { $0["name"] as? String }
    var appIds: [String: String] = [:]
    for entry in entries {
        if let name = entry["name"] as? String, let id = entry["appId"] as? String, isGitHubAppId(id) { appIds[name] = id }
    }
    return ForgeBots(names: names, appIds: appIds, note: nil)
}

/// A GitHub App id as the registry stores it: digits only, since it goes into a URL.
func isGitHubAppId(_ id: String) -> Bool {
    // bytes and not characters: a digit with a combining mark is one character and must not pass
    (1...12).contains(id.utf8.count) && id.utf8.allSatisfy { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }
}

/// Where the picture of a bot is: Agent Forge's registry has no avatar of its own, but every bot is a GitHub App, whose logo is public at
/// `avatars.githubusercontent.com/in/<appId>`. nil for an id that is not digits. `pixels` is the side asked for.
public func forgeAvatarURL(appId: String, pixels: Int) -> URL? {
    guard isGitHubAppId(appId), (16...512).contains(pixels) else { return nil }
    return URL(string: "https://avatars.githubusercontent.com/in/\(appId)?s=\(pixels)")
}

/// A GitHub login: up to 39 letters, digits and hyphens, not starting with a hyphen. Nothing else goes into the address of a picture.
public func isGithubLogin(_ text: String) -> Bool {
    text.isEmpty == false && text.count <= 39 && text.first != "-" && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
}

/// What a role's profile is, by `profiles` and the registry.
public enum RoleIdentity: Equatable {
    /// a bot of Agent Forge that the registry has
    case forge(String)
    /// the person's own gh login
    case gh
    /// the role names a profile that is not in `profiles`, or a bot the registry does not have: it stays in the file
    case missing
    case unset
}

/// One step of a role's failover: a provider and, optionally, a model and how hard it thinks (left out, the effort the role was running with).
public struct FailoverStep: Equatable, Sendable {
    public var provider: String
    public var model: String?
    public var effort: String?

    public init(provider: String, model: String? = nil, effort: String? = nil) {
        self.provider = provider
        self.model = model
        self.effort = effort
    }

    /// `codex · gpt-5 · low`, or `codex` when the step takes the account's model and the role's effort.
    public var text: String { [provider, model, effort].compactMap { $0 }.joined(separator: " · ") }
}

/// A role of an epic as the page names it: the engine's slot (ADR 0048). An extra reviewer is its key in `agents.extraReviewers` (ADR 0057), never
/// the word of another role.
public enum RoleSlot: Hashable, Sendable {
    case author, reviewer, lead
    case extra(key: String)

    public init(_ role: AgentRole) {
        switch role {
        case .author: self = .author
        case .reviewer: self = .reviewer
        case .leadReviewer: self = .lead
        }
    }

    /// The three fixed roles' own type, for what the engine edits by role; nil for an extra reviewer.
    public var agentRole: AgentRole? {
        switch self {
        case .author: .author
        case .reviewer: .reviewer
        case .lead: .leadReviewer
        case .extra: nil
        }
    }

    public var isExtra: Bool { if case .extra = self { true } else { false } }

    /// The last element of the role's settings place (`SettingsPlace(.roles, path: [name])`): the fixed roles keep the names they had, an extra reviewer is its key.
    public var name: String {
        if case .extra(let key) = self { return key }
        return agentRole?.rawValue ?? ""
    }

    /// A place's name is a slot when it is a fixed role's or looks like a key; whether the file has that key is for the page to say (`RolesPage.rows`).
    public init?(name: String) {
        if let role = AgentRole(rawValue: name) {
            self.init(role)
        } else if RoleSlot.isExtraKey(name) {
            self = .extra(key: name)
        } else {
            return nil
        }
    }

    /// The engine's rule for a key (`slugPattern` and `reservedKeys` of `src/config/extra-reviewer-key.ts`): 1 to 40 lowercase letters, digits and hyphens, starting with a letter, and not a role's word.
    static func isExtraKey(_ name: String) -> Bool {
        let letters = UInt8(ascii: "a")...UInt8(ascii: "z"), digits = UInt8(ascii: "0")...UInt8(ascii: "9")
        let bytes = Array(name.utf8)
        return (1...40).contains(bytes.count) && letters.contains(bytes[0]) && bytes.allSatisfy { letters.contains($0) || digits.contains($0) || $0 == UInt8(ascii: "-") }
            && ["author", "reviewer", "lead", "lead-reviewer"].contains(name) == false
    }

    /// At most three extra reviewers.
    public static let maxExtra = 3
}

public struct RoleRow: Equatable, Identifiable {
    public var slot: RoleSlot
    /// what an extra reviewer is called and what it looks at (`name` and `type` of its entry); nil for the fixed roles
    public var name: String?
    public var type: String?
    /// the fixed role, nil for an extra reviewer
    public var role: AgentRole? { slot.agentRole }
    public var what: String
    /// profile, provider, model, effort and persona as the file has them
    public var fields: RoleFields
    public var identity: RoleIdentity
    /// the provider is not an account of `providers.json`
    public var providerMissing: Bool
    /// every step of the role's list, though the page offers two; an extra reviewer with none of its own shows the Reviewer's (`ownSteps` false)
    public var steps: [FailoverStep]
    /// false for an extra reviewer that declares no `failover`, and for the lead while `failover.roles.leadReviewer` is not there: the engine gives them the Reviewer's steps
    public var ownSteps = true
    /// the Lead reviewer while the file has no `agents.leadReviewer`: its page is shown dimmed and not usable
    public var off: Bool
    /// The page shows this row with what the person is choosing for a Lead reviewer they are turning on (`LeadReviewerDraft.shown`): `off` stays, since
    /// the switch still has to say the file has no role, but it is drawn and worded as a role that is on. Also the reviewer being added (`NewExtraReviewer.row`): not saved yet.
    public var drafting = false
    public var id: String { slot.name }
    /// The role's name, or the name the person gave an extra reviewer (its key while the entry has none, "New reviewer" for the one being added).
    public func title(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        name ?? slot.agentRole?.title(bundle: bundle, locale: locale) ?? (slot == .draft ? Copy.rolesNewReviewer(bundle: bundle, locale: locale) : slot.name)
    }
    /// the Lead reviewer has the switch row on top
    public var hasSwitch: Bool { slot == .lead }

    /// The line under the role in the list.
    public func summary(bundle: Bundle? = nil, locale: Locale = .current) -> String { off ? Copy.rolesOff(bundle: bundle, locale: locale) : fields.text(bundle: bundle, locale: locale) }

    /// What the toolbar says under the role's name on its screen: the model, how hard it thinks and who it works as.
    public func headline(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        if off, drafting == false { return Copy.rolesOff(bundle: bundle, locale: locale) }
        let parts = [fields.model, fields.effort, fields.profile].compactMap { $0 }.filter { $0.isEmpty == false }
        return parts.isEmpty ? Copy.rolesNotSet(bundle: bundle, locale: locale) : parts.joined(separator: " · ")
    }

    public func identityDetail(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        switch identity {
        case .forge: Copy.rolesIdentityForge(bundle: bundle, locale: locale)
        case .gh: Copy.rolesIdentityGh(bundle: bundle, locale: locale)
        case .missing: fields.profile.map { Copy.rolesIdentityMissing(profile: $0, bundle: bundle, locale: locale) } ?? ""
        case .unset: Copy.rolesNotSet(bundle: bundle, locale: locale)
        }
    }
}

public struct RolesPage: Equatable {
    /// Author, Reviewer, the extra reviewers in the order of the map `agents.extraReviewers`, then the Lead reviewer
    public var rows: [RoleRow]
    /// the bots of the registry, then the person's own login is offered next to them
    public var bots: ForgeBots
    /// the accounts the Provider field lists
    public var accounts: [String]
    /// said when Author and Reviewer resolve to one account
    public var sharedNote: String?
    /// `limits.maxLeadRounds`: how many rounds the lead has with the author (3 when the file has none)
    public var leadRounds = 3
}

/// The page for `config`; nil when it is not a JSON object (the engine is not configured). `providers` is `providers.json`, nil when it is not there.
/// `extraKeys` is the order of the extra reviewers when it is not the file's `agents.extraReviewers` (a repo's own map, merged in).
public func rolesPage(config: Data, providers: Data?, bots: ForgeBots, extraKeys: [String]? = nil, bundle: Bundle? = nil, locale: Locale = .current) -> RolesPage? {
    guard let file = (try? JSONSerialization.jsonObject(with: config)) as? [String: Any] else { return nil }
    let roles = file["agents"] as? [String: Any] ?? [:]
    let profiles = file["profiles"] as? [String: Any] ?? [:]
    let lists = (file["failover"] as? [String: Any])?["roles"] as? [String: Any] ?? [:]
    let accounts = declaredAccounts(providersJSON: providers)
    func profile(_ name: String?) -> [String: Any]? { name.flatMap { profiles[$0] as? [String: Any] } }

    func steps(_ list: Any?) -> [FailoverStep] {
        (list as? [[String: Any]] ?? []).compactMap { step in
            (step["provider"] as? String).map { FailoverStep(provider: $0, model: step["model"] as? String, effort: step["effort"] as? String) }
        }
    }
    func identity(_ fields: RoleFields) -> RoleIdentity {
        guard let name = fields.profile else { return .unset }
        switch (profile(name)?["kind"] as? String, profile(name)?["agent"] as? String) {
        case ("gh", _): return .gh
        case ("forge", let agent?) where bots.names.contains(agent): return .forge(agent)
        default: return .missing
        }
    }
    func row(_ slot: RoleSlot, entry: Any?, steps: [FailoverStep], ownSteps: Bool = true, off: Bool = false) -> RoleRow {
        let fields = roleFields(entry)
        let extra = entry as? [String: Any]
        return RoleRow(
            slot: slot, name: slot.isExtra ? extra?["name"] as? String : nil, type: slot.isExtra ? extra?["type"] as? String : nil, what: slot.purpose(bundle: bundle, locale: locale), fields: fields, identity: identity(fields),
            providerMissing: fields.provider.map { accounts.contains($0) == false } ?? false, steps: steps, ownSteps: ownSteps, off: off
        )
    }
    let reviewerSteps = steps(lists[AgentRole.reviewer.rawValue])
    func fixed(_ role: AgentRole) -> RoleRow {
        // the engine's rule (`failoverStepsFor`): the lead takes the Reviewer's steps while it declares none
        let inherits = role == .leadReviewer && lists[role.rawValue] == nil
        return row(
            RoleSlot(role), entry: roles[role.rawValue], steps: inherits ? reviewerSteps : steps(lists[role.rawValue]), ownSteps: inherits == false,
            off: role == .leadReviewer && roles[role.rawValue] is [String: Any] == false
        )
    }
    // the engine's rule (`failoverStepsOfSlot`): an extra reviewer's own steps when it declares a list, else the Reviewer's
    // a list, which the engine refuses, has no keys: no row
    let map = roles["extraReviewers"] as? [String: Any] ?? [:]
    let extras = (extraKeys ?? jsonKeys(in: config, at: ["agents", "extraReviewers"]) ?? []).prefix(RoleSlot.maxExtra).compactMap { key -> RoleRow? in
        guard let entry = map[key] as? [String: Any] else { return nil }
        return row(.extra(key: key), entry: entry, steps: entry["failover"] == nil ? reviewerSteps : steps(entry["failover"]), ownSteps: entry["failover"] != nil)
    }
    let rows = [fixed(.author), fixed(.reviewer)] + extras + [fixed(.leadReviewer)]

    // the engine's rule (`sameAccount`): two gh logins, or two profiles of the same bot, not two equal names
    func account(_ role: RoleSlot) -> (profile: String, key: String)? {
        guard let name = rows.first(where: { $0.slot == role })?.fields.profile, let found = profile(name), let kind = found["kind"] as? String else { return nil }
        return (name, kind == "gh" ? "gh" : "forge:" + (found["agent"] as? String ?? ""))
    }
    var shared: String?
    if let author = account(.author), let reviewer = account(.reviewer), author.key == reviewer.key {
        shared = author.profile == reviewer.profile
            ? Copy.rolesSharedSame(profile: author.profile, bundle: bundle, locale: locale)
            : Copy.rolesSharedOne(author: author.profile, reviewer: reviewer.profile, bundle: bundle, locale: locale)
    }
    return RolesPage(rows: rows, bots: bots, accounts: accounts, sharedNote: shared, leadRounds: EngineConfig(json: config).maxLeadRounds)
}

/// Each extra reviewer of `config` as a place the Settings search can open, by the name the person gave it and its type (the static index cannot know them).
public func rolesSearchEntries(config: Data, bundle: Bundle? = nil, locale: Locale = .current) -> [SettingsEntry] {
    let rows = rolesPage(config: config, providers: nil, bots: ForgeBots(names: []), bundle: bundle, locale: locale)?.rows ?? []
    return rows.filter { $0.slot.isExtra }.map {
        SettingsEntry(
            page: .roles, groupID: "how-an-epic-runs", group: Copy.rolesRailGroup(bundle: bundle, locale: locale), rowID: $0.id, title: $0.title(bundle: bundle, locale: locale),
            detail: $0.what, keywords: $0.type ?? "")
    }
}

extension AgentRole {
    /// What the role does, under its name.
    public func purpose(bundle: Bundle? = nil, locale: Locale = .current) -> String { RoleSlot(self).purpose(bundle: bundle, locale: locale) }
}

extension RoleSlot {
    /// What the role does, under its name.
    public func purpose(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        switch self {
        case .author: Copy.rolesPurpose(which: .author, bundle: bundle, locale: locale)
        case .reviewer: Copy.rolesPurpose(which: .reviewer, bundle: bundle, locale: locale)
        case .lead: Copy.rolesPurpose(which: .leadReviewer, bundle: bundle, locale: locale)
        case .extra: Copy.rolesPurposeExtra(bundle: bundle, locale: locale)
        }
    }
}
