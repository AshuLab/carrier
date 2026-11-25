import Foundation
import Observation

// The Providers page of Settings (docs/specs/providers-in-settings.md): what the chat host says of the AI tools on this Mac (`providers`),
// joined with who uses each account, read from `engine.json` (roles, repo overrides, failover) and `chat.json` (chat agents). The page reads; it asks Carrier's own code to change `providers.json` for the Add of a harness found with no account and for an account's Add, edit and Remove (`ProvidersStore`, `ProvidersRequest`).

/// The reply of `providers`: the accounts of `providers.json` with their state, the harnesses found that no account has, and the local servers.
public struct HostProviders: Decodable, Equatable {
    public struct Account: Decodable, Equatable {
        public let name: String
        public let harness: String
        public let displayName: String?
        public let command: String?
        public let configDir: String?
        public let found: Bool
        public let path: String?
        public let version: String?
        public let state: ToolState
    }

    public struct Unadded: Decodable, Equatable {
        public let harness: String
        public let path: String
        public let version: String?
    }

    public struct Server: Decodable, Equatable {
        public let kind: String
        public let running: Bool
        public let models: [String]
    }

    /// The text generator in use, as the host reads it from `providers.json`.
    public struct TextGenerator: Decodable, Equatable {
        public let name: String
        public let kind: String
        public let model: String
    }

    /// `providers.json` does not match: why, with no accounts.
    public struct Problem: Decodable, Equatable {
        public let path: String
        public let message: String
        /// The text code and parameters of `message`; nil from a host that predates the codes.
        public let code: String?
        public let params: [String: TextParam]?

        /// The message in the person's language, with the key it is about unless the message already names it.
        public func shown(bundle: Bundle? = nil, locale: Locale = .current) -> String {
            let words = shownText(message, code: code, params: params, bundle: bundle, locale: locale)
            return words.contains(path) ? words : "\(path): \(words)"
        }
    }

    public let accounts: [Account]
    public let unadded: [Unadded]
    public let servers: [Server]
    /// Absent when the file names none, and from a host that does not list `textGenerators`.
    public let textGenerator: TextGenerator?
    public let problem: Problem?
}

public enum ProviderRole: CaseIterable {
    case author, reviewer, leadReviewer

    /// The key of the role in `engine.json`.
    var key: String {
        switch self {
        case .author: "author"
        case .reviewer: "reviewer"
        case .leadReviewer: "leadReviewer"
        }
    }

    public func title(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        switch self {
        case .author: AgentRole.author.title(bundle: bundle, locale: locale)
        case .reviewer: AgentRole.reviewer.title(bundle: bundle, locale: locale)
        case .leadReviewer: AgentRole.leadReviewer.title(bundle: bundle, locale: locale)
        }
    }
}

/// One way an account is named by the files: a role, a repo's override of a role, a failover list or a chat agent.
public enum AccountUse: Equatable {
    case role(ProviderRole)
    case repoOverride(repo: String, role: ProviderRole)
    /// nil is the default order, which any role without its own list follows.
    case failover(ProviderRole?)
    case chatAgent(String)

    public func text(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        switch self {
        case .role(let role): role.title(bundle: bundle, locale: locale)
        case .repoOverride(let repo, let role): Copy.providersUseRepo(role: role.title(bundle: bundle, locale: locale), repo: repo, bundle: bundle, locale: locale)
        case .failover(nil): Copy.providersUseFailoverDefault(bundle: bundle, locale: locale)
        case .failover(let role?): Copy.providersUseFailover(role: role.title(bundle: bundle, locale: locale), bundle: bundle, locale: locale)
        case .chatAgent(let name): Copy.providersUseChat(name: name, bundle: bundle, locale: locale)
        }
    }
}

/// Who uses each account, by account name. A missing `chat.json` (or one with no `agents`) is the chat's defaults: `claude` and `codex`, each
/// on the account of the same name. A role's failover steps count too. A file that does not read names nobody.
public func accountUses(config: Data?, chat: Data?) -> [String: [AccountUse]] {
    func object(_ data: Data?) -> [String: Any] {
        data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
    }
    func provider(_ role: Any?, _ key: String) -> String? { (role as? [String: Any])?[key] as? String }
    var uses: [String: [AccountUse]] = [:]
    let file = object(config)

    let roles = file["agents"] as? [String: Any] ?? [:]
    for role in ProviderRole.allCases {
        if let name = provider(roles[role.key], "provider") { uses[name, default: []].append(.role(role)) }
    }
    for repo in file["repos"] as? [[String: Any]] ?? [] {
        guard let repoName = repo["name"] as? String, let overrides = repo["agents"] as? [String: Any] else { continue }
        for role in ProviderRole.allCases {
            if let name = provider(overrides[role.key], "provider") { uses[name, default: []].append(.repoOverride(repo: repoName, role: role)) }
        }
    }
    let lists = (file["failover"] as? [String: Any])?["roles"] as? [String: Any] ?? [:]
    for role in ProviderRole.allCases {
        for step in lists[role.key] as? [[String: Any]] ?? [] {
            if let name = step["provider"] as? String { uses[name, default: []].append(.failover(role)) }
        }
    }

    let agents = object(chat)["agents"] as? [String: Any] ?? ["claude": ["account": "claude"], "codex": ["account": "codex"]]
    for agent in agents.keys.sorted() {
        if let name = provider(agents[agent], "account") { uses[name, default: []].append(.chatAgent(agent)) }
    }
    return uses
}

public struct ProviderAccount: Equatable, Identifiable {
    public let name: String
    /// The name the person gave it, else the account's name.
    public let title: String
    public let state: ToolState
    public let configDir: String?
    /// The binary the account runs, when it sets one.
    public let command: String?
    public let uses: [AccountUse]

    public var id: String { name }
    /// "Used by Author, Chat agent claude", or "Not used yet".
    public func usedBy(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        uses.isEmpty
            ? Copy.providersNotUsed(bundle: bundle, locale: locale)
            : Copy.providersUsedBy(uses: uses.map { $0.text(bundle: bundle, locale: locale) }.joined(separator: ", "), bundle: bundle, locale: locale)
    }
}

public struct ProviderTool: Equatable, Identifiable {
    public enum Status: Equatable {
        case ready, signedOut, unknown, missing
        /// The CLI is on this Mac and no account has it.
        case foundNotAdded

        public func text(bundle: Bundle? = nil, locale: Locale = .current) -> String {
            switch self {
            case .ready: Copy.providersStatus(which: .ready, bundle: bundle, locale: locale)
            case .signedOut: Copy.providersStatus(which: .signedOut, bundle: bundle, locale: locale)
            case .unknown: Copy.providersStatus(which: .unknown, bundle: bundle, locale: locale)
            case .missing: Copy.providersStatus(which: .missing, bundle: bundle, locale: locale)
            case .foundNotAdded: Copy.providersStatus(which: .foundNotAdded, bundle: bundle, locale: locale)
            }
        }
    }

    /// The harness: `claude`, `codex` or `agy`.
    public let id: String
    public let title: String
    /// The name of the bundled mark (`providerIconURL`).
    public let icon: String
    public let status: Status
    public let version: String?
    public let path: String?
    /// The binary of the account the version and path come from, when it sets one.
    public let command: String?
    public let accounts: [ProviderAccount]
}

public struct ProviderServer: Equatable, Identifiable {
    public let id: String
    public let title: String
    public let running: Bool
    public let models: [String]
    /// The model of the text generator in use, when it is on this server.
    public let generatorModel: String?

    public func status(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        running ? Copy.providersServerRunning(count: models.count, bundle: bundle, locale: locale) : Copy.providersNotRunning(bundle: bundle, locale: locale)
    }

    /// Why this server cannot be chosen as a text generator, in the words of its row; nil when it lists models.
    public func generatorNote(bundle: Bundle? = nil, locale: Locale = .current) -> String? {
        running == false ? Copy.providersNotRunning(bundle: bundle, locale: locale) : (models.isEmpty ? Copy.providersNoModelLoaded(bundle: bundle, locale: locale) : nil)
    }

    /// What the server offers as a text generator: its models, and the one in use when the server no longer lists it, so the row still shows it.
    public var generatorModels: [String] {
        guard running else { return [] }
        return models + (generatorModel.map { models.contains($0) ? [] : [$0] } ?? [])
    }
}

public struct ProvidersPage: Equatable {
    public let tools: [ProviderTool]
    public let servers: [ProviderServer]
    public let textGenerator: HostProviders.TextGenerator?

    /// The generator in use in words, "qwen3:8b on Ollama"; nil when none is chosen.
    public func generatorInUse(bundle: Bundle? = nil, locale: Locale = .current) -> String? {
        textGenerator.map { generator in
            Copy.providersGeneratorInUse(model: generator.model, server: localServers.first { $0.id == generator.kind }?.title ?? generator.kind, bundle: bundle, locale: locale)
        }
    }
}

private let harnesses: [(id: String, title: String, icon: String)] = [("claude", "Claude Code", "claude"), ("codex", "Codex", "codex"), ("agy", "Antigravity", "antigravity")]
private let localServers: [(id: String, title: String)] = [("lmstudio", "LM Studio"), ("ollama", "Ollama")]

/// The rows of the page: every tool with its state, version and path and its accounts with who uses them, and the local servers with their models.
public func providersPage(_ reply: HostProviders, config: Data?, chat: Data?) -> ProvidersPage {
    let uses = accountUses(config: config, chat: chat)
    let tools = harnesses.map { harness -> ProviderTool in
        let own = reply.accounts.filter { $0.harness == harness.id }
        let seen = own.first { $0.found }
        let unadded = reply.unadded.first { $0.harness == harness.id }
        let status: ProviderTool.Status
        if seen == nil && own.isEmpty && unadded != nil {
            status = .foundNotAdded
        } else if seen == nil {
            status = .missing
        } else if own.contains(where: { $0.state == .ready }) {
            status = .ready
        } else if own.contains(where: { $0.state == .signedOut }) {
            status = .signedOut
        } else {
            status = .unknown
        }
        return ProviderTool(
            id: harness.id, title: harness.title, icon: harness.icon, status: status,
            version: seen?.version ?? unadded?.version, path: seen?.path ?? unadded?.path, command: seen?.command,
            accounts: own.map {
                ProviderAccount(name: $0.name, title: $0.displayName ?? $0.name, state: $0.state, configDir: $0.configDir, command: $0.command, uses: uses[$0.name] ?? [])
            }
        )
    }
    let servers = localServers.map { local -> ProviderServer in
        let seen = reply.servers.first { $0.kind == local.id }
        return ProviderServer(id: local.id, title: local.title, running: seen?.running ?? false, models: seen?.models ?? [], generatorModel: reply.textGenerator.flatMap { $0.kind == local.id ? $0.model : nil })
    }
    return ProvidersPage(tools: tools, servers: servers, textGenerator: reply.textGenerator)
}

/// What the app got when it asked the host: the reply, or why there is none.
public enum ProvidersOutcome: Equatable {
    case unasked
    /// No chat host is running.
    case noHost
    /// The host's hello does not list `providers`.
    case tooOld
    case failed(String)
    case reply(HostProviders)

    /// Said in place of the page when there is no reply, or when `providers.json` does not match (the reply then has no accounts); nil when
    /// there is a page to draw.
    public func note(bundle: Bundle? = nil, locale: Locale = .current) -> String? {
        switch self {
        case .unasked: Copy.providersLooking(bundle: bundle, locale: locale)
        case .noHost: Copy.providersNoHost(bundle: bundle, locale: locale)
        case .tooOld: Copy.providersTooOld(bundle: bundle, locale: locale)
        case .failed(let reason): Copy.providersFailed(reason: reason, bundle: bundle, locale: locale)
        case .reply(let reply): reply.problem.map { Copy.providersMismatch(problem: $0.shown(bundle: bundle, locale: locale), bundle: bundle, locale: locale) }
        }
    }
}

/// What the host answered when asked to title earlier sessions (`regenerateTitles`).
public enum RetitleOutcome: Equatable {
    case started(Int)
    case refused(String)

    public func words(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        switch self {
        case .started(0): Copy.providersRetitleNothing(bundle: bundle, locale: locale)
        case .started(let n): Copy.providersRetitleStarted(count: n, bundle: bundle, locale: locale)
        case .refused(let reason): reason
        }
    }
}
