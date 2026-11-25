import Foundation

// The five requests that write `providers.json`, as the fixture host answers them under `--fixture` (docs/specs/macos-app-as-the-base-for-a-web-front-end.md, section 6):
// they change the file of the scratch Carrier folder and answer `{ saved, engine }` with the refusals of the real host (src/chat/providers-edit.ts), so the Providers page works as it does
// against it. The fixture's engine always applies the file. This is the only Swift code that writes a `providers.json`.

enum ProvidersFileError: Error, Equatable {
    /// The file is there and is not a JSON object with a `providers` map.
    case notAnObject
    case taken(String)
    case missing(String)
    /// The account is named by a role, a repo override, a failover list or a chat agent, so it stays.
    case inUse(String, [AccountUse])
    /// The words of what the host would refuse, and the key they are about (the host's `config.problem` path).
    case invalid(path: String, String)
}

/// The servers a text generator can be: the entry the host writes is named after its server.
private let textGeneratorServers = ["lmstudio", "ollama"]

func fixtureProvidersRefusal(_ error: ProvidersFileError) -> Refusal {
    switch error {
    case .notAnObject:
        return Refusal(code: "config.problem", params: ["path": "(file)", "problem": "notAnObject"], text: "providers.json is not a JSON object with a providers map, so it was not changed")
    case .taken(let name):
        return Refusal(code: "account.taken", params: ["name": .string(name)], text: "There is already an account named \(name).")
    case .missing(let name):
        return Refusal(code: "account.missing", params: ["name": .string(name)], text: "There is no account named \(name) in providers.json.")
    case .inUse(let name, let uses):
        let who = uses.map(\.text).joined(separator: ", ")
        return Refusal(code: "account.inUse", params: ["name": .string(name), "uses": .string(who)], text: "\(name) is used by \(who), so it stays. Point those at another account first.")
    case .invalid(let path, let words):
        return Refusal(code: "config.problem", params: ["path": .string(path), "problem": "custom"], text: words)
    }
}

/// The `data` of the reply, or the refusal; the file is written only when the change holds.
enum FixtureProvidersAnswer {
    case data([String: Any])
    case refused(Refusal)
}

func fixtureProvidersChange(_ request: [String: Any], home: String) -> FixtureProvidersAnswer {
    let places = CarrierPlaces(folder: home)
    func accountMap(_ value: Any?) -> [String: String] { value as? [String: String] ?? [:] }
    do {
        var file: [String: Any] = [:]
        if let current = try ProvidersFile(folder: home).read() {
            guard let object = (try? JSONSerialization.jsonObject(with: current)) as? [String: Any] else { throw ProvidersFileError.notAnObject }
            file = object
        }
        var providers: [String: Any] = [:]
        if let existing = file["providers"] {
            guard let map = existing as? [String: Any] else { throw ProvidersFileError.notAnObject }
            providers = map
        }
        let cmd = request["cmd"] as? String
        switch cmd {
        case "setAccounts":
            for account in request["accounts"] as? [[String: String]] ?? [] {
                guard let name = account["name"], let harness = account["harness"] else { continue }
                guard providers[name] == nil else { throw ProvidersFileError.taken(name) }
                providers[name] = ["harness": harness]
            }
        case "addAccount":
            let account = accountMap(request["account"])
            let (name, harness, configDir) = (account["name"] ?? "", account["harness"] ?? "", account["configDir"] ?? "")
            if let problem = nameProblem(name) { throw ProvidersFileError.invalid(path: "providers.\(name)", problem) }
            guard harness == "claude" || harness == "codex" else { throw ProvidersFileError.invalid(path: "providers.\(name).harness", "Only Claude Code and Codex take more accounts.") }
            var draft = AccountDraft()
            draft.configDir = configDir
            let problems = draftProblems(draft, harness: harness)
            if let field = AccountDraft.fields.first(where: { problems[$0] != nil }) { throw ProvidersFileError.invalid(path: "providers.\(name).\(field)", problems[field] ?? "") }
            guard providers[name] == nil else { throw ProvidersFileError.taken(name) }
            providers[name] = configDir.isEmpty ? ["harness": harness] : ["harness": harness, "configDir": normalizedConfigDir(configDir)]
        case "editAccount":
            let name = request["name"] as? String ?? ""
            guard var account = providers[name] as? [String: Any] else { throw ProvidersFileError.missing(name) }
            for (key, value) in request["changes"] as? [String: Any] ?? [:] { account[key] = value is NSNull ? nil : value }
            let problems = draftProblems(AccountDraft(account: account), harness: account["harness"] as? String ?? "")
            if let field = AccountDraft.fields.first(where: { problems[$0] != nil }) { throw ProvidersFileError.invalid(path: "providers.\(name).\(field)", problems[field] ?? "") }
            providers[name] = account
        case "removeAccount":
            let name = request["name"] as? String ?? ""
            guard providers[name] != nil else { throw ProvidersFileError.missing(name) }
            let uses = accountUses(config: try? Data(contentsOf: URL(fileURLWithPath: places.engineConfig)), chat: try? Data(contentsOf: URL(fileURLWithPath: places.chatConfig)))[name] ?? []
            guard uses.isEmpty else { throw ProvidersFileError.inUse(name, uses) }
            providers[name] = nil
        case "setTextGenerator":
            var generators = file["textGenerators"] as? [String: Any] ?? [:]
            for server in textGeneratorServers { generators[server] = nil }
            file["textGenerator"] = nil
            if let choice = request["choice"] as? [String: String], let server = choice["server"] {
                let model = (choice["model"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard textGeneratorServers.contains(server), model.isEmpty == false else {
                    throw ProvidersFileError.invalid(path: "textGenerators.\(server)", "textGenerators.\(server): a text generator is a model of LM Studio or Ollama")
                }
                generators[server] = ["kind": server, "model": model]
                file["textGenerator"] = server
            }
            file["textGenerators"] = generators.isEmpty ? nil : generators
        default:
            return .refused(Refusal(code: "request.invalid", text: "invalid request"))
        }
        if cmd != "setTextGenerator" { file["providers"] = providers }
        let updated = try JSONSerialization.data(withJSONObject: file, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: home), withIntermediateDirectories: true)
        try updated.write(to: URL(fileURLWithPath: places.providers), options: .atomic)
        let whole = (try? JSONSerialization.jsonObject(with: updated)) as? [String: Any] ?? [:]
        let touched = (request["accounts"] as? [[String: String]])?.compactMap { $0["name"] } ?? [(request["account"] as? [String: String])?["name"] ?? request["name"] as? String].compactMap { $0 }
        let named = (whole["providers"] as? [String: Any] ?? [:]).filter { touched.contains($0.key) }
        var saved: [String: Any] = cmd == "setTextGenerator" ? [:] : ["providers": named]
        for key in ["textGenerators", "textGenerator"] where cmd == "setTextGenerator" { saved[key] = whole[key] }
        return .data(["saved": saved, "engine": "applied"])
    } catch let error as ProvidersFileError {
        return .refused(fixtureProvidersRefusal(error))
    } catch {
        return .refused(Refusal(code: "request.internal", text: "internal error"))
    }
}
