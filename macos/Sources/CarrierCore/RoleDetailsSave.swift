import Foundation

// The Details and "When it runs out of tokens" cards of the Agents page (docs/specs/agents-in-settings.md): the persona of `agents.<role>` and the
// steps of `failover.roles.<role>` in `config.json`, and nothing else. The file is read again inside the save and every key the app does not know
// stays. The persona's limits are the ones of a repo's role (`RoleFields.problems`, RepoRoleSave.swift).

/// Reads the file, lets `edit` change it (a returned value stops the save, nothing is written) and writes it back.
private func updateConfig(path: String, reload: AfterWrite, _ edit: (inout [String: Any]) -> RoleSave?) -> RoleSave {
    let url = URL(fileURLWithPath: path)
    guard let current = try? Data(contentsOf: url), var file = (try? JSONSerialization.jsonObject(with: current)) as? [String: Any] else {
        return .failed("The config file could not be read.")
    }
    if let stop = edit(&file) { return stop }
    do {
        try JSONSerialization.data(withJSONObject: file, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: url, options: .atomic)
        return written(reload)
    } catch {
        FileHandle.standardError.write(Data("carrier: saving \(path) failed: \(error)\n".utf8))
        return .failed("Could not save the config file: \(error.localizedDescription)")
    }
}

/// Sets the global `role`'s persona to `name` and `prompt`, either one alone or both; nil for both removes it. A text given but empty, a name over
/// 40 characters or with a line break, or a prompt over 4000 characters is refused before writing.
public func saveGlobalPersona(name: String?, prompt: String?, role: AgentRole, path: String, reload: AfterWrite = reloadInBackground) -> RoleSave {
    for (label, text) in [("name", name), ("prompt", prompt)] where text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
        return .refused("The persona’s \(label) cannot be empty. Leave it out instead.")
    }
    let persona = RolePersona(name: name, prompt: prompt)
    let problems = RoleFields(persona: persona).normalized().problems(profiles: [], accounts: [])
    if problems.isEmpty == false { return .refused(problems.joined(separator: " ")) }
    return updateConfig(path: path, reload: reload) { file in
        var agents = file["agents"] as? [String: Any] ?? [:]
        guard var entry = agents[role.rawValue] as? [String: Any] else { return .refused("\(role.title) has no entry in config.json. Add it there first.") }
        let clean = RoleFields(persona: persona).normalized().persona
        entry["persona"] = clean.map { ["name": $0.name, "prompt": $0.prompt].compactMapValues { $0 } }
        agents[role.rawValue] = entry
        file["agents"] = agents
        return nil
    }
}

/// Sets the first two steps of the global `role`'s failover to `first` and `second`, and keeps the steps after them that the file has. Both nil
/// is Switch automatically off: the role's list is removed. Each step needs a declared provider; a step equal to another of the list or to the
/// role's own provider and model is refused (the engine's rule, `failover.roles.<role>.<n>`), with its position.
public func saveGlobalFailover(first: FailoverStep?, second: FailoverStep?, role: AgentRole, path: String, accounts: [String], reload: AfterWrite = reloadInBackground) -> RoleSave {
    if first == nil, second != nil { return .refused("Then needs a First step.") }
    func clean(_ step: FailoverStep) -> FailoverStep {
        let model = step.model?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effort = step.effort?.trimmingCharacters(in: .whitespacesAndNewlines)
        return FailoverStep(
            provider: step.provider.trimmingCharacters(in: .whitespacesAndNewlines), model: model?.isEmpty == true ? nil : model,
            effort: effort?.isEmpty == true ? nil : effort
        )
    }
    let edited = [first, second].compactMap { $0.map(clean) }
    for (index, step) in edited.enumerated() where accounts.contains(step.provider) == false {
        return .refused("\(index == 0 ? "First" : "Then"): “\(step.provider)” is not an account of providers.json. Pick another one.")
    }
    return updateConfig(path: path, reload: reload) { file in
        guard let own = (file["agents"] as? [String: Any])?[role.rawValue] as? [String: Any] else {
            return .refused("\(role.title) has no entry in config.json. Add it there first.")
        }
        var failover = file["failover"] as? [String: Any] ?? [:]
        var roles = failover["roles"] as? [String: Any] ?? [:]
        if edited.isEmpty {
            roles.removeValue(forKey: role.rawValue)
        } else {
            let kept = Array((roles[role.rawValue] as? [[String: Any]] ?? []).dropFirst(2))
            var steps: [[String: Any]] = edited.map { step in
                ["provider": step.provider].merging(step.model.map { ["model": $0] } ?? [:]) { $1 }.merging(step.effort.map { ["effort": $0] } ?? [:]) { $1 }
            }
            steps.append(contentsOf: kept)
            var seen: [[String: String]] = []
            for (index, step) in steps.enumerated() {
                let pair = step.compactMapValues { $0 as? String }.filter { $0.key == "provider" || $0.key == "model" }
                let label = index == 0 ? "First" : index == 1 ? "Then" : "Step \(index + 1)"
                if seen.contains(pair) { return .refused("\(label) repeats another step of the list.") }
                if pair["provider"] == own["provider"] as? String, pair["model"] == own["model"] as? String {
                    return .refused("\(label) is the role’s own provider and model, so it would move nowhere.")
                }
                seen.append(pair)
            }
            roles[role.rawValue] = steps
        }
        failover["roles"] = roles.isEmpty ? nil : roles
        file["failover"] = failover.isEmpty ? nil : failover
        return nil
    }
}
