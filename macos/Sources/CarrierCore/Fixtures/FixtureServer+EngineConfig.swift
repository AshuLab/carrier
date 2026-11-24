import Foundation

// `setWatchedRepos` and `editBehavior` (and, below, the role requests) as the real engine answers them (src/config/engine-edit.ts), against the fixture home's `engine.json`: the file is read again, the change applied to its raw
// JSON (every other key and every other repo's fields stay), checked with the words and kinds Node gives, and written only when all hold. The reply is `engine: "applied"`: there is no engine to
// run on the file. A change that would make the whole file invalid in a way only the engine's full schema sees is not refused here.

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
            config.maxExecutionRetries = (limits["maxExecutionRetries"] as? Int) ?? config.maxExecutionRetries
            config.githubCallTimeoutSeconds = (limits["githubCallTimeoutSeconds"] as? Int) ?? config.githubCallTimeoutSeconds
            if limits["maxExecutionHours"] as? String == "unlimited" { config.maxExecutionHours = nil } else if let hours = limits["maxExecutionHours"] as? Int { config.maxExecutionHours = hours }
            if let (key, words) = config.problems.sorted(by: { $0.key < $1.key }).first {
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

// `editRole`, `editRepoRole`, `editPersona`, `editFailover`, `setLeadReviewer` and `setOrchestratorProfile`: the fixture engine runs the same checks the app made before it asked for these (`saveGlobalRole` and the other
// writers, which only it uses now and which Node's `config/role-edit.ts` repeats word for word) against the fixture home's `engine.json`, `providers.json` and `agent-forge.json`. What Node refuses is refused with
// the same words; the code is `config.problem` with a key path of `(engine.json)`, the exact path and kind being the real engine's.

extension FixtureServer {
    func engineRolesReply(_ id: Int, _ request: [String: Any]) -> Data? {
        let path = CarrierPlaces(folder: home).engineConfig
        let accounts = declaredAccounts(providersJSON: try? Data(contentsOf: URL(fileURLWithPath: CarrierPlaces(folder: home).providers)))
        let bots = forgeBots(registry: try? Data(contentsOf: URL(fileURLWithPath: home + "/agent-forge.json"))).names
        let role = (request["role"] as? String).flatMap(AgentRole.init(rawValue:))
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
        let result: RoleSave
        switch request["cmd"] as? String {
        case "editRole":
            guard let role, let wire = request["changes"] as? [String: Any] else { return nil }
            result = saveGlobalRole(changes(wire), role: role, path: path, accounts: accounts, bots: bots, reload: { .applied })
        case "editRepoRole":
            guard let role, let repo = request["repo"] as? String, request.keys.contains("fields") else { return nil }
            let fields = (request["fields"] as? [String: Any]).map { wire in
                let persona = (wire["persona"] as? [String: Any]).map { RolePersona(name: $0["name"] as? String, prompt: $0["prompt"] as? String) }
                return RoleFields(profile: wire["profile"] as? String, provider: wire["provider"] as? String, model: wire["model"] as? String, effort: wire["effort"] as? String, persona: persona)
            }
            result = saveRepoRole(fields, role: role, repo: repo, path: path, accounts: accounts, reload: { .applied })
        case "editPersona":
            guard let role else { return nil }
            result = saveGlobalPersona(name: request["name"] as? String, prompt: request["prompt"] as? String, role: role, path: path, reload: { .applied })
        case "editFailover":
            guard let role else { return nil }
            result = saveGlobalFailover(first: step(request["first"]), second: step(request["second"]), role: role, path: path, accounts: accounts, reload: { .applied })
        case "setLeadReviewer":
            guard request.keys.contains("draft") else { return nil }
            if let wire = request["draft"] as? [String: Any] {
                var draft = LeadReviewerDraft()
                changes(wire).forEach { draft.apply($0) }
                result = turnLeadReviewerOn(draft, path: path, accounts: accounts, bots: bots, reload: { .applied })
            } else {
                result = turnLeadReviewerOff(path: path, reload: { .applied })
            }
        case "setOrchestratorProfile":
            guard request.keys.contains("name") else { return nil }
            let url = URL(fileURLWithPath: path)
            guard var file = (try? Data(contentsOf: url)).flatMap({ try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any] else { result = .failed("\(path) could not be read, so it was not changed"); break }
            file["orchestratorProfile"] = request["name"] as? String
            let data = try? JSONSerialization.data(withJSONObject: file, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            result = data.map { (try? $0.write(to: url, options: .atomic)) != nil } == true ? .saved : .failed("internal error")
        default:
            return nil
        }
        // `saved` stays empty: the real engine answers the part it changed, but the app reads the file itself and never decodes it.
        guard let words = result.problem else { return Self.answer(id, ["saved": [String: Any](), "engine": "applied"]) }
        return Self.refused(id, "config.problem", words, ["path": .string("(engine.json)"), "problem": .string("invalid")])
    }
}
