import Foundation

// Changing and resetting a repo's role from its page: writes `repos[].agents.<role>` of `config.json` and nothing else. The file is read
// again inside the save, so a change made by another writer since the page read it is not lost, and every key the app does not know stays.

public let roleEfforts = ["low", "medium", "high", "xhigh", "max"]

/// The accounts of `providers.json` (ADR 0020), or the three default accounts when the file is not there.
public func declaredAccounts(providersJSON: Data?) -> [String] {
    guard let providersJSON, let file = (try? JSONSerialization.jsonObject(with: providersJSON)) as? [String: Any],
          let declared = file["providers"] as? [String: Any]
    else { return ["claude", "codex", "agy"] }
    return declared.keys.sorted()
}

/// The icon of each account of `providers.json`, by the harness it runs (the three default accounts when the file is not there). An account with
/// no `harness` key is taken for the harness it is named after.
public func accountIcons(providersJSON: Data?) -> [String: String] {
    guard let providersJSON, let file = (try? JSONSerialization.jsonObject(with: providersJSON)) as? [String: Any],
          let declared = file["providers"] as? [String: Any]
    else { return ["claude": "claude", "codex": "codex", "agy": "antigravity"] }
    return declared.reduce(into: [:]) { icons, entry in
        icons[entry.key] = providerIconName(harness: (entry.value as? [String: Any])?["harness"] as? String ?? entry.key)
    }
}

extension RoleFields {
    /// What the engine reads: every text trimmed, an empty one left out (a model of only spaces is none), a persona with neither name nor prompt none.
    public func normalized() -> RoleFields {
        func text(_ value: String?) -> String? { value.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 } }
        let persona = persona.map { RolePersona(name: text($0.name), prompt: text($0.prompt)) }.flatMap { $0.name == nil && $0.prompt == nil ? nil : $0 }
        return RoleFields(profile: text(profile), provider: text(provider), model: text(model), effort: text(effort), persona: persona)
    }

    /// What the engine would refuse in these (normalized) fields, in words: a name that is not declared, an effort or persona out of its limits.
    public func problems(profiles: [String], accounts: [String]) -> [String] {
        var found: [String] = []
        if let profile, profiles.contains(profile) == false { found.append("Identity “\(profile)” is not declared in profiles. Pick another one.") }
        if let provider, accounts.contains(provider) == false { found.append("Provider “\(provider)” is not an account of providers.json. Pick another one.") }
        if let effort, roleEfforts.contains(effort) == false { found.append("Effort must be one of \(roleEfforts.joined(separator: ", ")).") }
        if let name = persona?.name, name.count > 40 || name.contains(where: \.isNewline) { found.append("The persona’s name is one line of up to 40 characters.") }
        if let prompt = persona?.prompt, prompt.count > 4000 { found.append("The persona’s prompt is up to 4000 characters.") }
        return found
    }
}

/// Said under a repo's roles when Author and Reviewer resolve to one identity: the engine accepts it and shares the epic's account.
public func signatureNote(_ rows: [RepoRoleRow]) -> String? {
    guard let author = rows.first(where: { $0.role == .author })?.value.profile,
          rows.first(where: { $0.role == .reviewer })?.value.profile == author
    else { return nil }
    return "Author and Reviewer both work as \(author): the signature will show it."
}

public enum RoleSave: Equatable {
    case saved
    /// the person's input the engine would refuse, in words; nothing was written
    case refused(String)
    /// the file could not be read or written
    case failed(String)
}

extension RoleSave {
    /// What the page shows where it shows a save that did not work; nil when all went through.
    public var problem: String? {
        switch self {
        case .saved: nil
        case .refused(let words), .failed(let words): words
        }
    }
}

/// `.saved` after the write, and the engine asked (what it answers is `ReloadStatus`'s, not the save's). Call it only after the write worked.
func written(_ reload: AfterWrite) -> RoleSave {
    _ = reload()
    return .saved
}

/// `json` with `repo`'s `role` set to the `fields` that are set, other keys of the entry kept; the entry goes when nothing is left. With `fields`
/// nil (Reset) the whole entry goes, and `agents` with it when it was the last. nil when `json` has no such repo.
func applyingRepoRole(_ fields: RoleFields?, role: AgentRole, repo: String, to json: Data) -> Data? {
    guard var file = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any], var repos = file["repos"] as? [[String: Any]],
          let index = repos.firstIndex(where: { $0["name"] as? String == repo })
    else { return nil }
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
    return try? JSONSerialization.data(withJSONObject: file, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
}

/// Saves `fields` as the repo's own `role` (nil resets it) in the file at `path`, read just now. A profile or account that is not declared
/// is refused before anything is written.
public func saveRepoRole(_ fields: RoleFields?, role: AgentRole, repo: String, path: String, accounts: [String], reload: AfterWrite = reloadInBackground) -> RoleSave {
    let url = URL(fileURLWithPath: path)
    guard let current = try? Data(contentsOf: url), let roles = repoRoles(json: current, repo: repo) else {
        return .failed("The config file could not be read.")
    }
    let fields = fields?.normalized()
    if let found = fields?.problems(profiles: roles.profiles, accounts: accounts), found.isEmpty == false { return .refused(found.joined(separator: " ")) }
    guard let updated = applyingRepoRole(fields, role: role, repo: repo, to: current) else { return .failed("\(repo) is no longer in the config file.") }
    do {
        try updated.write(to: url, options: .atomic)
        return written(reload)
    } catch {
        FileHandle.standardError.write(Data("carrier: saving \(path) failed: \(error)\n".utf8))
        return .failed("Could not save the config file: \(error.localizedDescription)")
    }
}
