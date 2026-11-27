import Foundation

// The `config` capability of the engine (docs/specs/macos-app-as-the-base-for-a-web-front-end.md, section 6; ADR 0053): a change to `engine.json` is a request, and
// Node's code writes the file and makes the engine run on it. The engine answers it when its hello lists `config`; otherwise (Carrier is stopped, or an older engine)
// `carrier config` takes the same request, without its `id`, and prints the reply the socket would give.

/// What the person has chosen for an extra reviewer they are adding: the engine refuses it, naming the field, when one is empty.
public struct ExtraReviewerDraft: Equatable, Sendable {
    public var name: String
    /// A slug that says what the reviewer looks at.
    public var type: String
    /// `.bot` or `.gh`
    public var identity: RoleChange
    public var provider: String
    public var model: String
    public var effort: String?

    public init(name: String, type: String, identity: RoleChange, provider: String, model: String, effort: String? = nil) {
        (self.name, self.type, self.identity, self.provider, self.model, self.effort) = (name, type, identity, provider, model, effort)
    }

    /// The identity, provider, model and effort as `editRole` takes them (an effort left out is not sent: a new reviewer has none to take out).
    var changes: [RoleChange] { [identity, .provider(provider), .model(model)] + (effort.map { [.effort($0)] } ?? []) }
}

/// One entry of a repo's own list of extra reviewers: what the engine reads of it (its persona, failover steps and skills are the Reviewer's).
public struct RepoExtraReviewer: Equatable, Sendable {
    /// The key the entry has in the repo's map (the engine derives none: a repo's list is sent whole).
    public var key: String
    public var type: String
    public var name: String
    /// The name of one of the file's profiles.
    public var profile: String
    public var provider: String
    public var model: String
    public var effort: String?

    public init(key: String, type: String, name: String, profile: String, provider: String, model: String, effort: String? = nil) {
        (self.key, self.type, self.name, self.profile, self.provider, self.model, self.effort) = (key, type, name, profile, provider, model, effort)
    }
}

/// A change to `engine.json` the app asks for: the watched repos, the eight values of Behavior, the roles, or the orchestrator's profile.
public enum EngineConfigChange: Equatable, Sendable {
    /// The whole list of `owner/name`, in order; a repo that stays keeps its own fields in the file.
    case watchedRepos([String])
    /// The eight values Behavior edits; Node takes out of the file the ones equal to the engine's default.
    case behavior(EngineConfig)
    /// The changes of one pick of the Roles page to a global role, applied together or not at all.
    case role(AgentRole, [RoleChange])
    /// A repo's own fields of a role (the ones left nil are not its own); nil takes the repo's override out.
    case repoRole(repo: String, role: AgentRole, fields: RoleFields?)
    /// The persona of a global role: either text alone, or both; nil for both takes it out.
    case persona(role: AgentRole, name: String?, prompt: String?)
    /// The first two failover steps of a global role; both nil is Switch automatically off.
    case failover(role: AgentRole, first: FailoverStep?, second: FailoverStep?)
    /// A complete draft turns the Lead reviewer on; nil turns it off.
    case leadReviewer(LeadReviewerDraft?)
    /// nil takes the key out: the author's profile.
    case orchestratorProfile(String?)
    /// A complete draft of an extra reviewer, added at the end of the global map; the engine derives the key from the name.
    case addExtraReviewer(ExtraReviewerDraft)
    /// The changes of one pick to an extra reviewer, pointed at by its key and applied together or not at all; `name` and `type` are the only fields a role has not, and a nil one is left as it is.
    case extraReviewerRole(key: String, name: String?, type: String?, [RoleChange])
    /// The persona of an extra reviewer: either text alone, or both; nil for both takes it out.
    case extraReviewerPersona(key: String, name: String?, prompt: String?)
    /// The first two failover steps of an extra reviewer's own list; both nil takes the list out and the reviewer goes back to the Reviewer's steps.
    case extraReviewerFailover(key: String, first: FailoverStep?, second: FailoverStep?)
    /// Takes an extra reviewer out of the global map by its key; the profile it used stays in the file.
    case removeExtraReviewer(key: String)
    /// A repo's own list of extra reviewers, sent whole in the order given: `[]` is none, nil takes the repo's key out and the global list applies again.
    case repoExtraReviewers(repo: String, [RepoExtraReviewer]?)

    var command: String {
        switch self {
        case .watchedRepos: "setWatchedRepos"
        case .behavior: "editBehavior"
        case .role, .extraReviewerRole: "editRole"
        case .repoRole: "editRepoRole"
        case .persona, .extraReviewerPersona: "editPersona"
        case .failover, .extraReviewerFailover: "editFailover"
        case .leadReviewer: "setLeadReviewer"
        case .orchestratorProfile: "setOrchestratorProfile"
        case .addExtraReviewer: "addExtraReviewer"
        case .removeExtraReviewer: "removeExtraReviewer"
        case .repoExtraReviewers: "setRepoExtraReviewers"
        }
    }

    /// The request's fields after `cmd` (and `id` on the socket), as JSON.
    var fields: String {
        switch self {
        case .watchedRepos(let names):
            return ",\"repos\":[" + names.map(jsonString).joined(separator: ",") + "]"
        case .behavior(let config):
            let limits: [String: Any] = [
                "maxConcurrentEpics": config.maxConcurrentEpics, "maxReviews": config.maxReviews, "maxLeadRounds": config.maxLeadRounds, "maxExecutionRetries": config.maxExecutionRetries,
                "maxExecutionHours": config.maxExecutionHours ?? "unlimited", "githubCallTimeoutSeconds": config.githubCallTimeoutSeconds,
            ]
            let changes: [String: Any] = ["pollIntervalMinutes": config.pollIntervalMinutes, "logLevel": config.logLevel, "finishedWindowDays": config.finishedWindowDays, "limits": limits]
            // a value that is not a number (the page refuses it before) would be a crash in the encoder: the engine refuses an empty change instead
            guard JSONSerialization.isValidJSONObject(changes), let data = try? JSONSerialization.data(withJSONObject: changes, options: [.sortedKeys, .withoutEscapingSlashes]) else { return "" }
            return ",\"changes\":" + String(decoding: data, as: UTF8.self)
        case .role(let role, let changes):
            return members(["role": role.rawValue, "changes": wire(changes)])
        case .repoRole(let repo, let role, let fields):
            return members(["repo": repo, "role": role.rawValue, "fields": fields.map(wire) ?? NSNull()])
        case .persona(let role, let name, let prompt):
            return members(["role": role.rawValue, "name": name ?? NSNull(), "prompt": prompt ?? NSNull()])
        case .failover(let role, let first, let second):
            return members(["role": role.rawValue, "first": first.map(wire) ?? NSNull(), "second": second.map(wire) ?? NSNull()])
        case .leadReviewer(let draft):
            return members(["draft": draft.map { wire($0.changes) } ?? NSNull()])
        case .orchestratorProfile(let name):
            return members(["name": name ?? NSNull()])
        case .addExtraReviewer(let draft):
            var body = wire(draft.changes)
            body["name"] = draft.name
            body["type"] = draft.type
            return members(["draft": body])
        case .extraReviewerRole(let key, let name, let type, let changes):
            var body = wire(changes)
            body["name"] = name
            body["type"] = type
            return members(["role": ["extraReviewer": key], "changes": body])
        case .extraReviewerPersona(let key, let name, let prompt):
            return members(["role": ["extraReviewer": key], "name": name ?? NSNull(), "prompt": prompt ?? NSNull()])
        case .extraReviewerFailover(let key, let first, let second):
            return members(["role": ["extraReviewer": key], "first": first.map(wire) ?? NSNull(), "second": second.map(wire) ?? NSNull()])
        case .removeExtraReviewer(let key):
            return members(["key": key])
        case .repoExtraReviewers(let repo, let reviewers):
            // the map is written by hand: the order of the entries is the order the epic runs them in, which a dictionary does not keep
            let map = reviewers.map { "{" + $0.map { jsonString($0.key) + ":" + entry($0) }.joined(separator: ",") + "}" } ?? "null"
            return ",\"repo\":" + jsonString(repo) + ",\"reviewers\":" + map
        }
    }

    /// The members of a request after `cmd`, as `fields` has them; nothing when a value could not be JSON (the engine refuses the request without them).
    private func members(_ object: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(object), let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) else { return "" }
        return "," + String(decoding: data, as: UTF8.self).dropFirst().dropLast()
    }

    /// What a pick of the page changes, as `editRole` takes it: a bot or the gh login is the identity, `effort` nil is `null` (none).
    private func wire(_ changes: [RoleChange]) -> [String: Any] {
        var wire: [String: Any] = [:]
        for change in changes {
            switch change {
            case .bot(let name): wire["identity"] = ["kind": "forge", "agent": name]
            case .gh: wire["identity"] = ["kind": "gh"]
            case .provider(let provider): wire["provider"] = provider
            case .model(let model): wire["model"] = model
            case .effort(let effort): wire["effort"] = effort ?? NSNull()
            }
        }
        return wire
    }

    private func entry(_ reviewer: RepoExtraReviewer) -> String {
        var body = ["type": reviewer.type, "name": reviewer.name, "profile": reviewer.profile, "provider": reviewer.provider, "model": reviewer.model]
        body["effort"] = reviewer.effort
        let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes])
        return data.map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }

    /// The fields a repo sets: only the ones that are set.
    private func wire(_ fields: RoleFields) -> [String: Any] {
        var wire: [String: Any] = [:]
        wire["profile"] = fields.profile
        wire["provider"] = fields.provider
        wire["model"] = fields.model
        wire["effort"] = fields.effort
        wire["persona"] = fields.persona.map { ["name": $0.name, "prompt": $0.prompt].compactMapValues { $0 } }
        return wire
    }

    private func wire(_ step: FailoverStep) -> [String: Any] {
        ["provider": step.provider, "model": step.model, "effort": step.effort].compactMapValues { $0 }
    }

    /// The request as `carrier config` reads it: the socket's request without its `id`.
    public var request: Data { Data("{\"cmd\":\"\(command)\"\(fields)}\n".utf8) }
}

/// What the engine answers to a change of its file: whether it runs on the saved file now. What was saved is not decoded: the app reads the file itself.
public struct EngineConfigReply: Decodable, Equatable, Sendable {
    public enum Engine: String, Decodable, Sendable { case applied, refused, notRunning }

    /// Why the engine kept its settings: a text code and its words, the same a refused `reload` gives.
    public struct Reason: Decodable, Equatable, Sendable {
        public let code: String
        public let params: [String: TextParam]
        public let error: String
    }

    public let engine: Engine
    public let reason: Reason?

    public init(engine: Engine, reason: Reason? = nil) { (self.engine, self.reason) = (engine, reason) }

    /// What the pages show of it, as they show a `reload`: the file is saved in every case.
    public var outcome: ReloadOutcome {
        switch engine {
        case .applied: .applied
        case .notRunning: .nobody
        case .refused: .refused(Refusal(code: reason?.code, params: reason?.params ?? [:], text: reason?.error ?? "the engine refused the saved settings"))
        }
    }
}

/// How the app sends a change of `engine.json`: to the engine's socket when its hello lists `config`, to `carrier config` otherwise (through the process runner).
public struct EngineConfigSender {
    public let socketPath: () -> String
    /// nil in a context that makes no request through `carrier`.
    public let launcher: CarrierConfigLauncher?

    public init(socketPath: @escaping () -> String = { controlSocketPath() }, launcher: CarrierConfigLauncher? = nil) {
        (self.socketPath, self.launcher) = (socketPath, launcher)
    }

    /// Answers when the file is saved and the engine has run on it, or kept its settings (the reply says which); throws `ControlError.remote` with the code and the key
    /// path and kind of problem when the file's schema refuses the change, the file left as it was.
    public func send(_ change: EngineConfigChange) async throws -> EngineConfigReply {
        if let reply = try await onQueue({ try sendToSocket(change) }) { return reply }
        guard let launcher else { throw ControlError.remote(.configNotRun) }
        return try await launcher.run(change.request, as: EngineConfigReply.self)
    }

    /// The socket's answer; nil, with nothing sent, when no engine answers or its hello does not list `config`. Blocks until the engine has run on the file (10 s at most), so
    /// the app runs it off the main thread, or, when it quits, in place.
    public func sendToSocket(_ change: EngineConfigChange) throws -> EngineConfigReply? {
        guard let client = ControlClient.connect(path: socketPath(), timeout: 10) else { return nil }
        defer { client.close() }
        _ = try client.supportedHello()
        return try client.request(change.command, requires: .config, fields: change.fields, as: EngineConfigReply.self)
    }
}

/// What a page or a model sends a change with: the app's sender, or a test's fake.
public typealias SendEngineConfig = (EngineConfigChange) async throws -> EngineConfigReply

/// Sends `change` and keeps what the engine answered in `status`, which every page that saves listens to; as the pages save: `.saved` when the file is saved (the engine may still have kept
/// its settings, which `status` says), `.refused` with the words, code and key path the schema gave when the change was refused, and `.failed` when nothing could be asked.
@MainActor public func saveEngineConfig(
    _ change: EngineConfigChange, send: SendEngineConfig, status: ReloadStatus? = nil, bundle: Bundle? = nil, locale: Locale = .current
) async -> RoleSave {
    do {
        (status ?? .shared).record(try await send(change).outcome)
        return .saved
    } catch ControlError.remote(let refusal) {
        return .refused(refusal.shown(bundle: bundle, locale: locale))
    } catch {
        FileHandle.standardError.write(Data("carrier: saving engine.json failed: \(error)\n".utf8))
        return .failed(Copy.engineSaveFailed(reason: error.localizedDescription, bundle: bundle, locale: locale))
    }
}

/// Saves one change at a time, in the order they were asked: two edits made one after the other reach the file in that order, whichever answers first.
@MainActor public final class EngineConfigQueue {
    private var last: Task<Void, Never>?

    public init() {}

    public func save(_ change: EngineConfigChange, send: @escaping SendEngineConfig, status: ReloadStatus? = nil) async -> RoleSave {
        let before = last
        let mine = Task { () -> RoleSave in
            await before?.value
            return await saveEngineConfig(change, send: send, status: status)
        }
        last = Task { _ = await mine.value }
        return await mine.value
    }

    /// Like `save`, but the change is built when its turn comes, after the saves asked before it have reached the file: an edit that sends a whole value again (a repo's list of reviewers) starts from
    /// what those left and does not overwrite them, however fast the edits were made. `build` answers nil when there is nothing to send, and then so does this.
    public func save(
        building build: @escaping @MainActor () -> EngineConfigChange?, send: @escaping SendEngineConfig, status: ReloadStatus? = nil
    ) async -> RoleSave? {
        let before = last
        let mine = Task { () -> RoleSave? in
            await before?.value
            guard let change = build() else { return nil }
            return await saveEngineConfig(change, send: send, status: status)
        }
        last = Task { _ = await mine.value }
        return await mine.value
    }
}

/// The calls that wait on the engine run here and not on a thread of the cooperative pool, which they would hold.
private let configQueue = DispatchQueue(label: "carrier.config", qos: .userInitiated, attributes: .concurrent)

private func onQueue<Value>(_ work: @escaping () throws -> Value) async throws -> Value {
    try await withCheckedThrowingContinuation { answer in
        configQueue.async { answer.resume(with: Result { try work() }) }
    }
}
