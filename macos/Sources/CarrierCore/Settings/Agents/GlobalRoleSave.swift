import Foundation

// Changing a global role (docs/specs/agents-in-settings.md): writes keys of `agents.<role>` of `engine.json`, plus the profile a chosen identity needs, and nothing else.
// The app no longer writes the file: it sends `EngineConfigChange.role`, and the engine (src/config/role-edit.ts) does what this does. This is the fixture engine's copy of it
// (FixtureServer+EngineConfig.swift), so `--fixture` answers with the engine's words. The checks and `RoleSave` are the ones of a repo's role (RepoRoleSave.swift).

/// The one thing the person changed in a role.
public enum RoleChange: Equatable, Sendable {
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
func saveGlobalRole(_ changes: [RoleChange], role: AgentRole, path: String, accounts: [String], bots: [String], creating: Bool = false, reload: AfterWrite = reloadInBackground) -> RoleSave {
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
        return .refused("\(role.title) has no entry in engine.json. Add it there first.")
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
    dropFailoverSteps(equalTo: entry, role: role, in: &file)
    do {
        let updated = try JSONSerialization.data(withJSONObject: file, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try updated.write(to: url, options: .atomic)
        return written(reload)
    } catch {
        FileHandle.standardError.write(Data("carrier: saving \(path) failed: \(error)\n".utf8))
        return .failed("Could not save the config file: \(error.localizedDescription)")
    }
}

/// A role that now runs on the provider and model one of its failover steps names has no use for that step: moving to what it already runs on would move
/// nowhere (the engine refuses the file, `failover.roles.<role>.<n>`), and falling back to the account that ran out is no fallback. The step goes and the
/// others stay, in their order; a list left empty goes too, and `failover` with it, which is Switch automatically off. A step with no model is another
/// model's, so it stays.
func dropFailoverSteps(equalTo entry: [String: Any], role: AgentRole, in file: inout [String: Any]) {
    guard var failover = file["failover"] as? [String: Any], var roles = failover["roles"] as? [String: Any],
        let steps = roles[role.rawValue] as? [[String: Any]], let provider = entry["provider"] as? String, let model = entry["model"] as? String else { return }
    let kept = steps.filter { ($0["provider"] as? String) != provider || ($0["model"] as? String) != model }
    guard kept.count != steps.count else { return }
    roles[role.rawValue] = kept.isEmpty ? nil : kept
    failover["roles"] = roles.isEmpty ? nil : roles
    file["failover"] = failover.isEmpty ? nil : failover
}
