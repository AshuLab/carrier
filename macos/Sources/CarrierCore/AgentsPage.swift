import Foundation

// The Agents page of Settings (docs/specs/agents-in-settings.md): the three fixed roles of `engine.json` with their identity, provider, model,
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
public func forgeBots(registry: Data?) -> ForgeBots {
    guard let registry else {
        return ForgeBots(names: [], note: "No Agent Forge registry was found, so only your gh login is offered. Create a bot to add one.")
    }
    guard let file = (try? JSONSerialization.jsonObject(with: registry)) as? [String: Any] else {
        return ForgeBots(names: [], note: "The Agent Forge registry could not be read, so only your gh login is offered.")
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
public struct FailoverStep: Equatable {
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

public struct RoleRow: Equatable, Identifiable {
    public var role: AgentRole
    public var what: String
    /// profile, provider, model, effort and persona as the file has them
    public var fields: RoleFields
    public var identity: RoleIdentity
    /// the provider is not an account of `providers.json`
    public var providerMissing: Bool
    /// every step of the role's list, though the page offers two
    public var steps: [FailoverStep]
    /// the Lead reviewer while the file has no `agents.leadReviewer`: its page is shown dimmed and not usable
    public var off: Bool
    /// The page shows this row with what the person is choosing for a Lead reviewer they are turning on (`LeadReviewerDraft.shown`): `off` stays, since
    /// the switch still has to say the file has no role, but it is drawn and worded as a role that is on.
    public var drafting = false
    public var id: String { role.rawValue }
    public var title: String { role.title }
    /// the Lead reviewer has the switch row on top
    public var hasSwitch: Bool { role == .leadReviewer }

    /// The line under the role in the list.
    public var summary: String { off ? "Off" : fields.text }

    /// What the toolbar says under the role's name on its screen: the model, how hard it thinks and who it works as.
    public var headline: String {
        if off, drafting == false { return "Off" }
        let parts = [fields.model, fields.effort, fields.profile].compactMap { $0 }.filter { $0.isEmpty == false }
        return parts.isEmpty ? "Not set" : parts.joined(separator: " · ")
    }

    public var identityDetail: String {
        switch identity {
        case .forge: "A bot from Agent Forge"
        case .gh: "Your gh login"
        case .missing: fields.profile.map { "“\($0)” is not in Agent Forge’s list or in profiles; it is kept" } ?? ""
        case .unset: "Not set"
        }
    }
}

public struct AgentsPage: Equatable {
    public var rows: [RoleRow]
    /// the bots of the registry, then the person's own login is offered next to them
    public var bots: ForgeBots
    /// the accounts the Provider field lists
    public var accounts: [String]
    /// said when Author and Reviewer resolve to one account
    public var sharedNote: String?
}

/// The page for `config`; nil when it is not a JSON object (the engine is not configured). `providers` is `providers.json`, nil when it is not there.
public func agentsPage(config: Data, providers: Data?, bots: ForgeBots) -> AgentsPage? {
    guard let file = (try? JSONSerialization.jsonObject(with: config)) as? [String: Any] else { return nil }
    let roles = file["agents"] as? [String: Any] ?? [:]
    let profiles = file["profiles"] as? [String: Any] ?? [:]
    let lists = (file["failover"] as? [String: Any])?["roles"] as? [String: Any] ?? [:]
    let accounts = declaredAccounts(providersJSON: providers)
    func profile(_ name: String?) -> [String: Any]? { name.flatMap { profiles[$0] as? [String: Any] } }

    let rows = AgentRole.allCases.map { role in
        let fields = roleFields(roles[role.rawValue])
        let identity: RoleIdentity
        if let name = fields.profile {
            switch (profile(name)?["kind"] as? String, profile(name)?["agent"] as? String) {
            case ("gh", _): identity = .gh
            case ("forge", let agent?) where bots.names.contains(agent): identity = .forge(agent)
            default: identity = .missing
            }
        } else {
            identity = .unset
        }
        let steps = (lists[role.rawValue] as? [[String: Any]] ?? []).compactMap { step in
            (step["provider"] as? String).map { FailoverStep(provider: $0, model: step["model"] as? String, effort: step["effort"] as? String) }
        }
        return RoleRow(
            role: role, what: role.purpose, fields: fields, identity: identity,
            providerMissing: fields.provider.map { accounts.contains($0) == false } ?? false,
            steps: steps, off: role == .leadReviewer && roles[role.rawValue] is [String: Any] == false
        )
    }

    // the engine's rule (`sameAccount`): two gh logins, or two profiles of the same bot, not two equal names
    func account(_ role: AgentRole) -> (profile: String, key: String)? {
        guard let name = rows.first(where: { $0.role == role })?.fields.profile, let found = profile(name), let kind = found["kind"] as? String else { return nil }
        return (name, kind == "gh" ? "gh" : "forge:" + (found["agent"] as? String ?? ""))
    }
    var shared: String?
    if let author = account(.author), let reviewer = account(.reviewer), author.key == reviewer.key {
        let who = author.profile == reviewer.profile ? "both work as \(author.profile)" : "are one account (\(author.profile) and \(reviewer.profile))"
        shared = "Author and Reviewer \(who): the signature will show it."
    }
    return AgentsPage(rows: rows, bots: bots, accounts: accounts, sharedNote: shared)
}

extension AgentRole {
    /// What the role does, under its name.
    public var purpose: String {
        switch self {
        case .author: "Writes the code of the epic and answers the reviewer"
        case .reviewer: "Reviews the final pull request"
        case .leadReviewer: "Optional. Looks at architecture and production readiness after the reviewer"
        }
    }
}
