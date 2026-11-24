import Foundation

// The five requests that write `providers.json`, as the fixture host answers them under `--fixture` (docs/specs/macos-app-as-the-base-for-a-web-front-end.md, section 6):
// they change the file of the scratch Carrier folder and answer `{ saved, engine }` with the refusals of the real host, so the Providers page works as it does against it.
// The fixture's engine always applies the file.

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
    case .invalid(let words):
        return Refusal(code: "config.problem", params: ["path": "providers", "problem": "custom"], text: words)
    }
}

/// The `data` of the reply, or the refusal; the file is written only when the change holds.
enum FixtureProvidersAnswer {
    case data([String: Any])
    case refused(Refusal)
}

func fixtureProvidersChange(_ request: [String: Any], home: String) -> FixtureProvidersAnswer {
    let file = ProvidersFile(folder: home)
    let places = CarrierPlaces(folder: home)
    do {
        let current = try file.read()
        let updated: Data
        switch request["cmd"] as? String {
        case "setAccounts":
            let accounts = (request["accounts"] as? [[String: String]] ?? []).compactMap { entry in entry["name"].flatMap { name in entry["harness"].map { (name: name, harness: $0) } } }
            updated = try applyingAccounts(accounts, to: current)
        case "addAccount":
            let account = request["account"] as? [String: String] ?? [:]
            updated = try applyingNewAccount(name: account["name"] ?? "", harness: account["harness"] ?? "", configDir: account["configDir"] ?? "", to: current)
        case "editAccount":
            updated = try fixtureEditedAccount(name: request["name"] as? String ?? "", changes: request["changes"] as? [String: Any] ?? [:], in: current)
        case "removeAccount":
            let name = request["name"] as? String ?? ""
            let uses = accountUses(config: try? Data(contentsOf: URL(fileURLWithPath: places.engineConfig)), chat: try? Data(contentsOf: URL(fileURLWithPath: places.chatConfig)))
            updated = try applyingRemoval(name: name, uses: uses[name] ?? [], to: current)
        case "setTextGenerator":
            let choice = (request["choice"] as? [String: String]).flatMap { entry in entry["server"].flatMap { server in entry["model"].map { (server: server, model: $0) } } }
            updated = try applyingTextGenerator(choice, to: current)
        default:
            return .refused(Refusal(code: "request.invalid", text: "invalid request"))
        }
        try file.write(updated)
        let whole = (try? JSONSerialization.jsonObject(with: updated)) as? [String: Any] ?? [:]
        let touched = (request["accounts"] as? [[String: String]])?.compactMap { $0["name"] } ?? [(request["account"] as? [String: String])?["name"] ?? request["name"] as? String].compactMap { $0 }
        let providers = (whole["providers"] as? [String: Any] ?? [:]).filter { touched.contains($0.key) }
        var saved: [String: Any] = request["cmd"] as? String == "setTextGenerator" ? [:] : ["providers": providers]
        for key in ["textGenerators", "textGenerator"] where request["cmd"] as? String == "setTextGenerator" { saved[key] = whole[key] }
        return .data(["saved": saved, "engine": "applied"])
    } catch let error as ProvidersFileError {
        return .refused(fixtureProvidersRefusal(error))
    } catch {
        return .refused(Refusal(code: "request.internal", text: "internal error"))
    }
}

/// `json` with each key of `changes` set on the account `name`; a null removes it, every other key stays.
private func fixtureEditedAccount(name: String, changes: [String: Any], in json: Data?) throws -> Data {
    var file: [String: Any] = [:]
    if let json {
        guard let object = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else { throw ProvidersFileError.notAnObject }
        file = object
    }
    var providers = file["providers"] as? [String: Any] ?? [:]
    guard var account = providers[name] as? [String: Any] else { throw ProvidersFileError.missing(name) }
    for (key, value) in changes { account[key] = value is NSNull ? nil : value }
    providers[name] = account
    file["providers"] = providers
    return try JSONSerialization.data(withJSONObject: file, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
}
