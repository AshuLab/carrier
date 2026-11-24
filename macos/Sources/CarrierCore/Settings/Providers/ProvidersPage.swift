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

        /// The message with the key it is about, unless the message already names it.
        public var text: String { message.contains(path) ? message : "\(path): \(message)" }
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

    public var title: String {
        switch self {
        case .author: "Author"
        case .reviewer: "Reviewer"
        case .leadReviewer: "Lead reviewer"
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

    public var text: String {
        switch self {
        case .role(let role): role.title
        case .repoOverride(let repo, let role): "\(role.title) in \(repo)"
        case .failover(nil): "Failover, default order"
        case .failover(let role?): "Failover of \(role.title)"
        case .chatAgent(let name): "Chat agent \(name)"
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
    public var usedBy: String { uses.isEmpty ? "Not used yet" : "Used by " + uses.map(\.text).joined(separator: ", ") }
}

public struct ProviderTool: Equatable, Identifiable {
    public enum Status: Equatable {
        case ready, signedOut, unknown, missing
        /// The CLI is on this Mac and no account has it.
        case foundNotAdded

        public var text: String {
            switch self {
            case .ready: "Signed in"
            case .signedOut: "Signed out"
            case .unknown: "Could not check"
            case .missing: "Not installed"
            case .foundNotAdded: "Found, not added"
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

    public var status: String { running ? "Running · " + (models.count == 1 ? "1 model" : "\(models.count) models") : "Not running" }

    /// Why this server cannot be chosen as a text generator, in the words of its row; nil when it lists models.
    public var generatorNote: String? { running == false ? "Not running" : (models.isEmpty ? "No model loaded" : nil) }

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
    public var generatorInUse: String? {
        textGenerator.map { generator in "\(generator.model) on \(localServers.first { $0.id == generator.kind }?.title ?? generator.kind)" }
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
    public var note: String? {
        switch self {
        case .unasked: "Looking at this Mac…"
        case .noHost: "The chat host is not running, so this Mac was not looked at. Open Health to see why."
        case .tooOld: "The chat host is too old to list the AI tools. Restart it to use the installed Carrier."
        case .failed(let reason): "The chat host could not list the AI tools: \(reason)"
        case .reply(let reply): reply.problem.map { "providers.json does not match, so no accounts are shown. \($0.text)" }
        }
    }
}

/// What the host answered when asked to title earlier sessions (`regenerateTitles`).
public enum RetitleOutcome: Equatable {
    case started(Int)
    case refused(String)

    public var words: String {
        switch self {
        case .started(0): "Nothing to title: every session already has a title"
        case .started(let n): "Started \(n) \(n == 1 ? "session" : "sessions") in the background"
        case .refused(let reason): reason
        }
    }
}

/// The last answer of `providers`; asked when the page opens and again on request, and only of a host that lists it.
@MainActor @Observable public final class ProvidersStore {
    public private(set) var outcome = ProvidersOutcome.unasked
    /// Why the last Add did not write the account, in words; nil when it did or none was made.
    public private(set) var addProblem: String?
    /// Why the last Add account, edit or Remove did not write the file, in words naming the field; nil when it did or none was made.
    public private(set) var editProblem: String?
    /// What the engine answered to the last write when that is a plain fact and not a problem (an older engine reads the file when it starts); nil when it applied it or none was made.
    public private(set) var editNote: String?
    /// An Add is being written and the engine asked: its button waits for the answer, so a second click does not add twice. Save and Remove close at once.
    public private(set) var busy = false
    /// Whether the host knows the `label`, `icon` and `color` of an account (its hello lists `accountIdentity`). An older `carrier` refuses a
    /// `providers.json` that has them, accounts and all, so the editor does not offer them and writes none until it does.
    public private(set) var identityEditable = false
    /// Whether the host also knows the later icons and colors (`accountPalette`); an `accountIdentity` host refuses a file with one.
    public private(set) var paletteEditable = false
    /// Whether the host knows `textGenerators` (its hello lists it). An older `carrier` refuses a `providers.json` with the keys, so none is written until it does.
    public private(set) var generatorEditable = false
    /// Whether the host can title earlier sessions in the background (`regenerateTitles` in its hello).
    public private(set) var canRegenerateTitles = false
    /// True while `regenerateTitles` is waiting for the host's answer.
    public private(set) var retitling = false
    /// What the last `regenerateTitles` answered, or nil before it ran or after leaving or changing the generator.
    public private(set) var retitleOutcome: RetitleOutcome?

    @ObservationIgnored private let host: ChatHost
    @ObservationIgnored private let file: () -> ProvidersFile
    @ObservationIgnored private let log: (String) -> Void
    @ObservationIgnored private let status: ReloadStatus
    /// The look at the host after a write.
    @ObservationIgnored private var follow: Task<Void, Never>?

    /// `file` is looked up at each use, so the Carrier folder is the one the app has then; the app only reads it (a change is a request to `host`, ADR 0053).
    public init(
        host: ChatHost, file: @escaping () -> ProvidersFile = ProvidersFile.current,
        log: @escaping (String) -> Void = { FileHandle.standardError.write(Data("carrier: \($0)\n".utf8)) },
        status: ReloadStatus? = nil
    ) {
        self.host = host
        self.file = file
        self.log = log
        self.status = status ?? .shared
    }

    /// When the app opens: with no `providers.json`, asks for one account per harness the host found, named after it. With a file there it asks for nothing, so an account that was removed stays removed; with nothing found
    /// it asks for nothing either (an empty file would leave the roles' default accounts undeclared), and a host that cannot answer is not guessed at.
    public func createFileIfMissing() async {
        guard file().exists == false else { return }
        await load()
        guard case .reply(let reply) = outcome, reply.problem == nil else { return }
        let found = reply.accounts.filter(\.found).map { DetectedAccount(name: $0.name, harness: $0.harness) }
        guard found.isEmpty == false, file().exists == false else { return }
        do {
            let saved = try await host.changeProviders(.setAccounts(found))
            status.record(saved.outcome)
            // no page is asking for this file, so the engine's refusal goes to the log
            if let problem = reloadWords(saved.outcome) { log("providers: the engine did not apply the new providers.json: \(problem)") }
        } catch {
            log("providers: could not create providers.json: \(error)")
            return
        }
        await load()
    }

    /// The Add of a "Found, not added" row: the account named after the harness, then the host is asked again so the row goes away.
    public func add(harness: String) async {
        busy = true
        defer { busy = false }
        addProblem = nil
        dismissProblem()
        do {
            let saved = try await host.changeProviders(.setAccounts([DetectedAccount(name: harness, harness: harness)]))
            // the row leaves "Found, not added" once the host is asked again, so the engine's words go where the accounts show them
            engineSaid(saved.outcome)
        } catch {
            addProblem = problem(error, "add \(harness)")
        }
        busy = false
        await load()
    }

    /// The person closed the form or editor that showed `editProblem`, or left the page.
    public func dismissProblem() {
        editProblem = nil
        editNote = nil
        retitleOutcome = nil
    }

    /// What the engine answered to a write: a problem is `editProblem`, a plain fact `editNote`. The answer is also the shared one, which other pages show.
    private func engineSaid(_ outcome: ReloadOutcome) {
        status.record(outcome)
        let words = reloadWords(outcome)
        editProblem = outcome.isProblem ? words : nil
        editNote = outcome.isProblem ? nil : words
    }

    /// What a failed request says: Carrier's own words for a refusal, a fixed sentence (the error goes to the log) for anything else.
    private func problem(_ error: Error, _ what: String) -> String {
        if case ControlError.remote(let refusal) = error { return refusal.text }
        log("providers: could not \(what): \(error)")
        return "providers.json could not be written; the file stays as it was."
    }

    /// A quiet line when another account of `harness` already has this config folder, which makes it the same login and not a new one; nil otherwise.
    public func sharedFolderNote(configDir: String, harness: String, except name: String? = nil) -> String? {
        let json = (try? file().read()).flatMap { $0 }
        return accountSharingFolder(configDir: configDir, harness: harness, except: name, in: json).map { "\($0) already uses this folder, so this is the same login, not another one." }
    }

    /// The Add account of a tool: a new account with a name and, when given, a config folder.
    @discardableResult public func addAccount(name: String, harness: String, configDir: String) async -> Bool {
        await change("add \(name)", .addAccount(name: name, harness: harness, configDir: configDir))
    }

    /// The editor's Save: the fields written to the account, an emptied one removing its key.
    @discardableResult public func save(name: String, draft: AccountDraft) async -> Bool {
        await change("save \(name)", .editAccount(name: name, draft: draft))
    }

    /// Remove: refused, naming who, while a role, a repo override, a failover list or a chat agent names the account.
    @discardableResult public func remove(name: String) async -> Bool {
        await change("remove \(name)", .removeAccount(name: name))
    }

    /// Choose the text generator (a model of a local server), or clear the choice with nil; written only while the host lists `textGenerators`.
    @discardableResult public func chooseTextGenerator(_ choice: (server: String, model: String)?) async -> Bool {
        guard generatorEditable else {
            editProblem = "The chat host does not know text generators yet. Update carrier (brew upgrade carrier) and restart the chat host."
            return false
        }
        retitleOutcome = nil
        return await change("choose a text generator", .setTextGenerator(choice.map { TextGeneratorChoice(server: $0.server, model: $0.model) }), showAtOnce: true)
    }

    /// Asks the host to title earlier sessions whose title is still their first line, in the background. Only sent while the host lists `regenerateTitles`.
    public func regenerateTitles() async {
        guard canRegenerateTitles else { return }
        retitling = true
        retitleOutcome = nil
        defer { retitling = false }
        do {
            retitleOutcome = .started(try await host.regenerateTitles())
        } catch {
            retitleOutcome = .refused(ConversationModel.words(error))
        }
    }

    /// Asks for the change and says what the engine did with the file; a refusal wrote nothing and says why. The editor closes when it gives back, and the host is looked at again after it
    /// (`settled`), in the background unless the page shows the result at once; a `problem` the host answers is what the page shows.
    private func change(_ what: String, _ request: ProvidersRequest, showAtOnce: Bool = false) async -> Bool {
        dismissProblem()
        let saved: ProvidersSaved
        do { saved = try await host.changeProviders(request) } catch {
            editProblem = problem(error, what)
            return false
        }
        engineSaid(saved.outcome)
        // the host reads the file at each use, so the page can show the choice the moment it is written
        if showAtOnce { await load() } else { follow = Task { await load() } }
        return true
    }

    /// Waits for the look at the host that follows the last write.
    public func settled() async { await follow?.value }

    public func load() async {
        let capabilities: Set<ControlClient.Capability>
        do { capabilities = try await host.capabilities() } catch {
            identityEditable = false
            paletteEditable = false
            generatorEditable = false
            canRegenerateTitles = false
            retitleOutcome = nil
            outcome = .noHost
            return
        }
        identityEditable = capabilities.contains(.accountIdentity)
        paletteEditable = capabilities.contains(.accountPalette)
        generatorEditable = capabilities.contains(.textGenerators)
        canRegenerateTitles = capabilities.contains(.regenerateTitles)
        if canRegenerateTitles == false { retitleOutcome = nil }
        guard capabilities.contains(.providers) else {
            outcome = .tooOld
            return
        }
        do { outcome = .reply(try await host.providers()) } catch {
            let reason = ConversationModel.words(error)
            log("providers: \(reason)")
            outcome = .failed(reason)
        }
    }
}
