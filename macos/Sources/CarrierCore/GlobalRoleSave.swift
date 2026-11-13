import Foundation

// Changing a global role from the Agents page (docs/specs/agents-in-settings.md): writes one key of `agents.<role>` of `config.json`, plus the
// profile a chosen identity needs, and nothing else. The file is read again inside the save, so a change another writer made since the page read it
// is not lost, and every key the app does not know stays. The checks and `RoleSave` are the ones of a repo's role (RepoRoleSave.swift).

/// The one thing the person changed in a role.
public enum RoleChange: Equatable {
    /// a bot of the Agent Forge registry: writes (or reuses) the profile `{ kind: "forge", agent: <name> }`
    case bot(String)
    /// the person's own login: the profile `{ kind: "gh" }`
    case gh
    case provider(String)
    case model(String)
    /// nil: none, the CLI's own default
    case effort(String?)
}

/// `name` for a bot's profile, or `name-2`, `name-3`… when `name` already means something else.
private func freeProfileName(_ name: String, in profiles: [String: Any]) -> String {
    var candidate = name
    var number = 2
    while profiles[candidate] != nil {
        candidate = "\(name)-\(number)"
        number += 1
    }
    return candidate
}

/// Applies `changes` to the global `role` in the file at `path`, read just now, together: one write, or none. A bot the registry (`bots`) does not list, a provider that is not
/// an account, an empty model, or a role left without profile, provider or model is refused before anything is written. With `creating` the role may not be in the file yet (turning the Lead reviewer on), and then
/// the changes have to make the whole role, identity, provider and model, or nothing is written.
public func saveGlobalRole(_ changes: [RoleChange], role: AgentRole, path: String, accounts: [String], bots: [String], creating: Bool = false, reload: AfterWrite = reloadInBackground) -> RoleSave {
    let url = URL(fileURLWithPath: path)
    guard let current = try? Data(contentsOf: url), var file = (try? JSONSerialization.jsonObject(with: current)) as? [String: Any] else {
        return .failed("The config file could not be read.")
    }
    var agents = file["agents"] as? [String: Any] ?? [:]
    var entry: [String: Any]
    if let existing = agents[role.rawValue] as? [String: Any] {
        entry = existing
    } else if creating {
        entry = [:]
    } else {
        return .refused("\(role.title) has no entry in config.json. Add it there first.")
    }
    var profiles = file["profiles"] as? [String: Any] ?? [:]

    for change in changes {
        switch change {
        case .bot(let name):
            guard bots.contains(name) else { return .refused("“\(name)” is not in Agent Forge’s list. Pick another one.") }
            let existing = profiles.keys.sorted().first { (profiles[$0] as? [String: Any]).map { $0["kind"] as? String == "forge" && $0["agent"] as? String == name } ?? false }
            let profile = existing ?? freeProfileName(name, in: profiles)
            profiles[profile] = profiles[profile] ?? ["kind": "forge", "agent": name]
            entry["profile"] = profile
        case .gh:
            let existing = profiles.keys.sorted().first { (profiles[$0] as? [String: Any])?["kind"] as? String == "gh" }
            let profile = existing ?? freeProfileName("gh", in: profiles)
            profiles[profile] = profiles[profile] ?? ["kind": "gh"]
            entry["profile"] = profile
        case .provider(let provider): entry["provider"] = provider
        case .model(let model): entry["model"] = model.trimmingCharacters(in: .whitespacesAndNewlines)
        case .effort(let effort):
            if let effort { entry["effort"] = effort } else { entry.removeValue(forKey: "effort") }
        }
    }

    let fields = roleFields(entry).normalized()
    if fields.profile == nil || fields.provider == nil || fields.model == nil {
        return .refused(fields.model == nil ? "The model cannot be empty." : "\(role.title) needs an identity, a provider and a model.")
    }
    let problems = fields.problems(profiles: Array(profiles.keys), accounts: accounts)
    if problems.isEmpty == false { return .refused(problems.joined(separator: " ")) }

    agents[role.rawValue] = entry
    file["agents"] = agents
    file["profiles"] = profiles
    do {
        let updated = try JSONSerialization.data(withJSONObject: file, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try updated.write(to: url, options: .atomic)
        return written(reload)
    } catch {
        FileHandle.standardError.write(Data("carrier: saving \(path) failed: \(error)\n".utf8))
        return .failed("Could not save the config file: \(error.localizedDescription)")
    }
}
