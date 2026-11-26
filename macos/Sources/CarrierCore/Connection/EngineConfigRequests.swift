import Foundation

// The `config` capability of the engine (docs/specs/macos-app-as-the-base-for-a-web-front-end.md, section 6; ADR 0053): a change to `engine.json` is a request, and
// Node's code writes the file and makes the engine run on it. The engine answers it when its hello lists `config`; otherwise (Carrier is stopped, or an older engine)
// `carrier config` takes the same request, without its `id`, and prints the reply the socket would give.

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

    var command: String {
        switch self {
        case .watchedRepos: "setWatchedRepos"
        case .behavior: "editBehavior"
        case .role: "editRole"
        case .repoRole: "editRepoRole"
        case .persona: "editPersona"
        case .failover: "editFailover"
        case .leadReviewer: "setLeadReviewer"
        case .orchestratorProfile: "setOrchestratorProfile"
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
}

/// The calls that wait on the engine run here and not on a thread of the cooperative pool, which they would hold.
private let configQueue = DispatchQueue(label: "carrier.config", qos: .userInitiated, attributes: .concurrent)

private func onQueue<Value>(_ work: @escaping () throws -> Value) async throws -> Value {
    try await withCheckedThrowingContinuation { answer in
        configQueue.async { answer.resume(with: Result { try work() }) }
    }
}
