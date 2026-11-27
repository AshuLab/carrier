import Foundation

// `setWatchedRepos` and `editBehavior` (and, below, the role requests) as the real engine answers them (src/config/engine-edit.ts), against the fixture home's `engine.json`: the file is read again, the change applied to its raw
// JSON (every other key and every other repo's fields stay), checked with the words and kinds Node gives, and written only when all hold. The reply is `engine: "applied"`: there is no engine to
// run on the file. A change that would make the whole file invalid in a way only the engine's full schema sees is not refused here. This is the only Swift code that writes an `engine.json`.

extension FixtureServer {
    func engineConfigReply(_ id: Int, _ request: [String: Any]) -> Data? {
        let url = URL(fileURLWithPath: CarrierPlaces(folder: home).engineConfig)
        func refusal(_ path: String, _ problem: String, _ words: String) -> Data {
            Self.refused(id, "config.problem", words, ["path": .string(path), "problem": .string(problem)])
        }
        guard let current = try? Data(contentsOf: url) else { return refusal("(file)", "notFound", "\(url.path) is not there, so it was not changed") }
        guard var file = (try? JSONSerialization.jsonObject(with: current)) as? [String: Any] else {
            return refusal("(file)", "notAnObject", "\(url.path) is not a JSON object, so it was not changed")
        }
        var saved: [String: Any] = [:]
        switch request["cmd"] as? String {
        case "setWatchedRepos":
            guard let names = request["repos"] as? [String] else { return nil }
            for (index, name) in names.enumerated() {
                guard let problem = repoProblem(name, joining: Array(names[..<index])) else { continue }
                let kind = isRepoName(name) == false ? "notARepo" : problem.hasSuffix("is already watched") ? "alreadyWatched" : "sameFolderName"
                return refusal("repos[\(index)]", kind, problem)
            }
            let kept = file["repos"] as? [[String: Any]] ?? []
            let repos = names.map { name in kept.first { $0["name"] as? String == name } ?? ["name": name] }
            file["repos"] = repos
            saved["repos"] = repos
        case "editBehavior":
            guard let changes = request["changes"] as? [String: Any] else { return nil }
            var config = EngineConfig(json: current)
            let limits = changes["limits"] as? [String: Any] ?? [:]
            config.pollIntervalMinutes = (changes["pollIntervalMinutes"] as? Double) ?? config.pollIntervalMinutes
            config.logLevel = (changes["logLevel"] as? String) ?? config.logLevel
            config.finishedWindowDays = (changes["finishedWindowDays"] as? Int) ?? config.finishedWindowDays
            config.maxConcurrentEpics = (limits["maxConcurrentEpics"] as? Int) ?? config.maxConcurrentEpics
            config.maxReviews = (limits["maxReviews"] as? Int) ?? config.maxReviews
            config.maxLeadRounds = (limits["maxLeadRounds"] as? Int) ?? config.maxLeadRounds
            config.maxExecutionRetries = (limits["maxExecutionRetries"] as? Int) ?? config.maxExecutionRetries
            config.githubCallTimeoutSeconds = (limits["githubCallTimeoutSeconds"] as? Int) ?? config.githubCallTimeoutSeconds
            if limits["maxExecutionHours"] as? String == "unlimited" { config.maxExecutionHours = nil } else if let hours = limits["maxExecutionHours"] as? Int { config.maxExecutionHours = hours }
            // the fixture engine answers in English, as the engine does
            if let (key, words) = config.problems(bundle: Copy.bundle("en"), locale: Locale(identifier: "en_US")).sorted(by: { $0.key < $1.key }).first {
                let path = ["pollIntervalMinutes", "logLevel", "finishedWindowDays"].contains(key) ? key : "limits.\(key)"
                return refusal(path, "invalid", words)
            }
            let base = EngineConfig()
            func put(_ key: String, _ value: Any, differs: Bool, in object: inout [String: Any]) {
                if differs { object[key] = value } else { object.removeValue(forKey: key) }
            }
            put("pollIntervalMinutes", config.pollIntervalMinutes, differs: config.pollIntervalMinutes != base.pollIntervalMinutes, in: &file)
            put("logLevel", config.logLevel, differs: config.logLevel != base.logLevel, in: &file)
            put("finishedWindowDays", config.finishedWindowDays, differs: config.finishedWindowDays != base.finishedWindowDays, in: &file)
            var own = file["limits"] as? [String: Any] ?? [:]
            put("maxConcurrentEpics", config.maxConcurrentEpics, differs: config.maxConcurrentEpics != base.maxConcurrentEpics, in: &own)
            put("maxReviews", config.maxReviews, differs: config.maxReviews != base.maxReviews, in: &own)
            put("maxLeadRounds", config.maxLeadRounds, differs: config.maxLeadRounds != base.maxLeadRounds, in: &own)
            put("maxExecutionRetries", config.maxExecutionRetries, differs: config.maxExecutionRetries != base.maxExecutionRetries, in: &own)
            put("maxExecutionHours", config.maxExecutionHours ?? "unlimited", differs: config.maxExecutionHours != base.maxExecutionHours, in: &own)
            put("githubCallTimeoutSeconds", config.githubCallTimeoutSeconds, differs: config.githubCallTimeoutSeconds != base.githubCallTimeoutSeconds, in: &own)
            file["limits"] = own.isEmpty ? nil : own
            for key in changes.keys where key != "limits" { saved[key] = file[key] }
            saved = saved.compactMapValues { $0 }
            if limits.isEmpty == false, let own = file["limits"] as? [String: Any] {
                let kept = limits.keys.reduce(into: [String: Any]()) { $0[$1] = own[$1] }.compactMapValues { $0 }
                if kept.isEmpty == false { saved["limits"] = kept }
            }
        default:
            return nil
        }
        guard let data = try? JSONSerialization.data(withJSONObject: file, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]), (try? data.write(to: url, options: .atomic)) != nil else {
            return Self.refused(id, "request.internal", "internal error")
        }
        return Self.answer(id, ["saved": saved, "engine": "applied"])
    }
}

// `editRole`, `editRepoRole`, `editPersona`, `editFailover`, `setLeadReviewer`, `setOrchestratorProfile` and the extra reviewers' requests (`FixtureServer+ExtraReviewers.swift`): the fixture engine makes the checks Node's `config/role-edit.ts` makes (with its words)
// against the fixture home's `engine.json`, `providers.json` and `agent-forge.json`. What Node refuses is refused with the same words; the code is `config.problem` with a key path
// of `(engine.json)`, the exact path and kind being the real engine's.

extension FixtureServer {
    func engineRolesReply(_ id: Int, _ request: [String: Any]) -> Data? {
        let url = URL(fileURLWithPath: CarrierPlaces(folder: home).engineConfig)
        let accounts = declaredAccounts(providersJSON: try? Data(contentsOf: URL(fileURLWithPath: CarrierPlaces(folder: home).providers)))
        let bots = forgeBots(registry: try? Data(contentsOf: URL(fileURLWithPath: home + "/agent-forge.json"))).names
        let role = (request["role"] as? String).flatMap(AgentRole.init(rawValue:))
        // `editRole`, `editPersona` and `editFailover` point at an extra reviewer as `{"extraReviewer": key}`
        let extra = (request["role"] as? [String: Any])?["extraReviewer"] as? String
        func step(_ value: Any?) -> FailoverStep? {
            guard let step = value as? [String: Any], let provider = step["provider"] as? String else { return nil }
            return FailoverStep(provider: provider, model: step["model"] as? String, effort: step["effort"] as? String)
        }
        func changes(_ wire: [String: Any]) -> [RoleChange] {
            var found: [RoleChange] = []
            if let identity = wire["identity"] as? [String: Any] { found.append(identity["kind"] as? String == "gh" ? .gh : .bot(identity["agent"] as? String ?? "")) }
            if let provider = wire["provider"] as? String { found.append(.provider(provider)) }
            if let model = wire["model"] as? String { found.append(.model(model)) }
            if wire.keys.contains("effort") { found.append(.effort(wire["effort"] as? String)) }
            return found
        }
        /// Reads the file again, lets `change` edit it (the words it returns are a refusal and nothing is written) and writes it back: nil when it went through.
        func edit(_ change: (inout [String: Any]) -> String?) -> String? {
            guard let current = try? Data(contentsOf: url), var file = (try? JSONSerialization.jsonObject(with: current)) as? [String: Any] else { return "The config file could not be read." }
            if let words = change(&file) { return words }
            guard let data = try? JSONSerialization.data(withJSONObject: file, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]), (try? data.write(to: url, options: .atomic)) != nil else { return "internal error" }
            return nil
        }
        let refusal: String?
        switch request["cmd"] as? String {
        case "editRole":
            guard let wire = request["changes"] as? [String: Any] else { return nil }
            if let extra {
                refusal = edit { Self.editExtra(key: extra, name: wire["name"] as? String, type: wire["type"] as? String, changes: changes(wire), accounts: accounts, bots: bots, to: &$0) }
            } else {
                guard let role else { return nil }
                refusal = edit { Self.applyRole(changes(wire), role: role, accounts: accounts, bots: bots, creating: false, to: &$0) }
            }
        case "editRepoRole":
            guard let role, let repo = request["repo"] as? String, request.keys.contains("fields") else { return nil }
            let fields = (request["fields"] as? [String: Any]).map { wire in
                let persona = (wire["persona"] as? [String: Any]).map { RolePersona(name: $0["name"] as? String, prompt: $0["prompt"] as? String) }
                return RoleFields(profile: wire["profile"] as? String, provider: wire["provider"] as? String, model: wire["model"] as? String, effort: wire["effort"] as? String, persona: persona)
            }
            refusal = edit { Self.applyRepoRole(fields, role: role, repo: repo, accounts: accounts, to: &$0) }
        case "editPersona":
            if let extra {
                refusal = edit { Self.editExtraPersona(key: extra, name: request["name"] as? String, prompt: request["prompt"] as? String, to: &$0) }
            } else {
                guard let role else { return nil }
                refusal = edit { Self.applyPersona(name: request["name"] as? String, prompt: request["prompt"] as? String, role: role, to: &$0) }
            }
        case "editFailover":
            if let extra {
                refusal = edit { Self.editExtraFailover(key: extra, first: step(request["first"]), second: step(request["second"]), accounts: accounts, to: &$0) }
            } else {
                guard let role else { return nil }
                refusal = edit { Self.applyFailover(first: step(request["first"]), second: step(request["second"]), role: role, accounts: accounts, to: &$0) }
            }
        case "addExtraReviewer":
            guard let draft = request["draft"] as? [String: Any] else { return nil }
            refusal = edit { Self.addExtra(draft: draft, accounts: accounts, bots: bots, to: &$0) }
        case "setRepoExtraReviewers":
            guard let repo = request["repo"] as? String, request["reviewers"] is NSNull || request["reviewers"] is [String: Any] else { return nil }
            refusal = edit { Self.setRepoExtras(repo: repo, reviewers: request["reviewers"] as? [String: Any], accounts: accounts, to: &$0) }
        case "removeExtraReviewer":
            guard let key = request["key"] as? String else { return nil }
            refusal = edit { Self.removeExtra(key: key, from: &$0) }
        case "setLeadReviewer":
            guard request.keys.contains("draft") else { return nil }
            if let wire = request["draft"] as? [String: Any] {
                var draft = LeadReviewerDraft()
                changes(wire).forEach { draft.apply($0) }
                let needs = draft.missing.map { field in
                    switch field {
                    case .identity: "an identity"
                    case .provider: "a provider"
                    case .model: "a model"
                    }
                }
                refusal = draft.isComplete
                    ? edit { Self.applyRole(draft.changes, role: .leadReviewer, accounts: accounts, bots: bots, creating: true, to: &$0) }
                    : "The lead reviewer needs \(needs.joined(separator: ", "))."
            } else {
                refusal = edit { file in
                    var agents = file["agents"] as? [String: Any] ?? [:]
                    agents[AgentRole.leadReviewer.rawValue] = nil
                    file["agents"] = agents
                    if var failover = file["failover"] as? [String: Any], var roles = failover["roles"] as? [String: Any] {
                        roles[AgentRole.leadReviewer.rawValue] = nil
                        failover["roles"] = roles
                        file["failover"] = failover
                    }
                    return nil
                }
            }
        case "setOrchestratorProfile":
            guard request.keys.contains("name") else { return nil }
            refusal = edit { $0["orchestratorProfile"] = request["name"] as? String; return nil }
        default:
            return nil
        }
        // `saved` stays empty: the real engine answers the part it changed, but the app reads the file itself and never decodes it.
        guard let words = refusal else { return Self.answer(id, ["saved": [String: Any](), "engine": "applied"]) }
        return Self.refused(id, "config.problem", words, ["path": .string("(engine.json)"), "problem": .string("invalid")])
    }

    /// `changes` applied together to the global `role` of `file`: a bot the registry (`bots`) does not list, a provider that is not an account, an empty model, or a role left without
    /// identity, provider or model is refused. With `creating` the role may not be in the file yet (the lead reviewer turned on).
    private static func applyRole(_ changes: [RoleChange], role: AgentRole, accounts: [String], bots: [String], creating: Bool, to file: inout [String: Any]) -> String? {
        var agents = file["agents"] as? [String: Any] ?? [:]
        var entry: [String: Any]
        if let existing = agents[role.rawValue] as? [String: Any] {
            entry = existing
        } else if creating {
            entry = [:]
        } else {
            return "\(role.title(bundle: Copy.bundle("en"), locale: Locale(identifier: "en_US"))) has no entry in engine.json. Add it there first."
        }
        var profiles = file["profiles"] as? [String: Any] ?? [:]
        let title = role.title(bundle: Copy.bundle("en"), locale: Locale(identifier: "en_US"))
        if let words = applyChanges(changes, to: &entry, profiles: &profiles, called: title, accounts: accounts, bots: bots) { return words }
        agents[role.rawValue] = entry
        file["agents"] = agents
        file["profiles"] = profiles
        // A role that now runs on the provider and model one of its failover steps names has no use for that step (the engine refuses the file otherwise): the step goes, a list left empty
        // goes too, and `failover` with it. A step with no model is another model's, so it stays.
        if var failover = file["failover"] as? [String: Any], var roles = failover["roles"] as? [String: Any], let steps = roles[role.rawValue] as? [[String: Any]] {
            let kept = steps.filter { ($0["provider"] as? String) != entry["provider"] as? String || ($0["model"] as? String) != entry["model"] as? String }
            if kept.count != steps.count {
                roles[role.rawValue] = kept.isEmpty ? nil : kept
                failover["roles"] = roles.isEmpty ? nil : roles
                file["failover"] = failover.isEmpty ? nil : failover
            }
        }
        return nil
    }

    /// `fields` as the repo's own `role` in `file` (nil resets it: the entry goes, and `agents` with the last), other keys kept.
    private static func applyRepoRole(_ fields: RoleFields?, role: AgentRole, repo: String, accounts: [String], to file: inout [String: Any]) -> String? {
        let fields = fields?.normalized()
        if let found = fields?.problems(profiles: Array((file["profiles"] as? [String: Any] ?? [:]).keys), accounts: accounts, bundle: Copy.bundle("en"), locale: Locale(identifier: "en_US")), found.isEmpty == false { return found.joined(separator: " ") }
        guard var repos = file["repos"] as? [[String: Any]], let index = repos.firstIndex(where: { $0["name"] as? String == repo }) else { return "\(repo) is no longer in the config file." }
        var agents = repos[index]["agents"] as? [String: Any] ?? [:]
        var entry: [String: Any] = [:]
        if let fields {
            entry = agents[role.rawValue] as? [String: Any] ?? [:]
            entry["profile"] = fields.profile
            entry["provider"] = fields.provider
            entry["model"] = fields.model
            entry["effort"] = fields.effort
            entry["persona"] = fields.persona.map { ["name": $0.name, "prompt": $0.prompt].compactMapValues { $0 } }
        }
        agents[role.rawValue] = entry.isEmpty ? nil : entry
        repos[index]["agents"] = agents.isEmpty ? nil : agents
        file["repos"] = repos
        return nil
    }

    /// The global `role`'s persona set to `name` and `prompt`, either one alone or both; nil for both removes it.
    private static func applyPersona(name: String?, prompt: String?, role: AgentRole, to file: inout [String: Any]) -> String? {
        let (persona, words) = checkedPersona(name: name, prompt: prompt)
        if let words { return words }
        var agents = file["agents"] as? [String: Any] ?? [:]
        guard var entry = agents[role.rawValue] as? [String: Any] else { return "\(role.title(bundle: Copy.bundle("en"), locale: Locale(identifier: "en_US"))) has no entry in engine.json. Add it there first." }
        entry["persona"] = persona.map { ["name": $0.name, "prompt": $0.prompt].compactMapValues { $0 } }
        agents[role.rawValue] = entry
        file["agents"] = agents
        return nil
    }

    /// The first two steps of the global `role`'s failover set to `first` and `second`, keeping the steps after them. Both nil removes the role's list.
    private static func applyFailover(first: FailoverStep?, second: FailoverStep?, role: AgentRole, accounts: [String], to file: inout [String: Any]) -> String? {
        let title = role.title(bundle: Copy.bundle("en"), locale: Locale(identifier: "en_US"))
        var failover = file["failover"] as? [String: Any] ?? [:]
        var roles = failover["roles"] as? [String: Any] ?? [:]
        return attempt {
            let steps = try failoverSteps(first: first, second: second, accounts: accounts, who: "role", before: roles[role.rawValue] as? [[String: Any]] ?? []) {
                guard let own = (file["agents"] as? [String: Any])?[role.rawValue] as? [String: Any] else { throw Refused(words: "\(title) has no entry in engine.json. Add it there first.") }
                return own
            }
            roles[role.rawValue] = steps.isEmpty ? nil : steps
            failover["roles"] = roles.isEmpty ? nil : roles
            file["failover"] = failover.isEmpty ? nil : failover
        }
    }
}
