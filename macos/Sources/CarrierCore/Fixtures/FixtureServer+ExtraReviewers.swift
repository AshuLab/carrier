import Foundation

// `addExtraReviewer`, `removeExtraReviewer` and `editRole`, `editPersona` and `editFailover` pointing at an extra reviewer by its key, as the real engine answers them (src/config/role-edit.ts, ADR 0057):
// the same checks with the same words, against the fixture home's `engine.json`. The file is written with its keys in order of the alphabet, so a reviewer added here takes its place in the map by its key and
// not at the end, which the engine does.

/// The words of a refusal; nothing was written.
struct Refused: Error { let words: String }

/// Runs `body`, which throws a `Refused` to refuse: its words, or nil when it went through.
func attempt(_ body: () throws -> Void) -> String? {
    do { try body() } catch let refused as Refused { return refused.words } catch { return "internal error" }
    return nil
}

extension FixtureServer {
    private static let english = (bundle: Copy.bundle("en"), locale: Locale(identifier: "en_US"))

    /// The persona as the engine reads it (every text trimmed, none when neither is left) or the words that refuse it.
    static func checkedPersona(name: String?, prompt: String?) -> (persona: RolePersona?, words: String?) {
        for (label, text) in [("name", name), ("prompt", prompt)] where text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            return (nil, "The persona’s \(label) cannot be empty. Leave it out instead.")
        }
        let persona = RoleFields(persona: RolePersona(name: name, prompt: prompt)).normalized().persona
        let problems = RoleFields(persona: persona).problems(profiles: [], accounts: [], bundle: english.bundle, locale: english.locale)
        return (persona, problems.isEmpty ? nil : problems.joined(separator: " "))
    }

    /// The steps of a failover list after `first` and `second` replace its first two (the ones after them stay): empty when both are nil, which takes the list out. `own` is the entry the list is of,
    /// asked for once the accounts are checked; `who` is how a refusal calls it.
    static func failoverSteps(first: FailoverStep?, second: FailoverStep?, accounts: [String], who: String, before: [[String: Any]], own: () throws -> [String: Any]) throws -> [[String: Any]] {
        if first == nil, second != nil { throw Refused(words: "Then needs a First step.") }
        func clean(_ step: FailoverStep) -> FailoverStep {
            let model = step.model?.trimmingCharacters(in: .whitespacesAndNewlines)
            let effort = step.effort?.trimmingCharacters(in: .whitespacesAndNewlines)
            return FailoverStep(provider: step.provider.trimmingCharacters(in: .whitespacesAndNewlines), model: model?.isEmpty == true ? nil : model, effort: effort?.isEmpty == true ? nil : effort)
        }
        let edited = [first, second].compactMap { $0.map(clean) }
        for (index, step) in edited.enumerated() where accounts.contains(step.provider) == false {
            throw Refused(words: "\(index == 0 ? "First" : "Then"): “\(step.provider)” is not an account of providers.json. Pick another one.")
        }
        let entry = try own()
        guard edited.isEmpty == false else { return [] }
        var steps: [[String: Any]] = edited.map { step in
            ["provider": step.provider].merging(step.model.map { ["model": $0] } ?? [:]) { $1 }.merging(step.effort.map { ["effort": $0] } ?? [:]) { $1 }
        }
        steps.append(contentsOf: Array(before.dropFirst(2)))
        var seen: [[String: String]] = []
        for (index, step) in steps.enumerated() {
            let pair = step.compactMapValues { $0 as? String }.filter { $0.key == "provider" || $0.key == "model" }
            let label = index == 0 ? "First" : index == 1 ? "Then" : "Step \(index + 1)"
            if seen.contains(pair) { throw Refused(words: "\(label) repeats another step of the list.") }
            if pair["provider"] == entry["provider"] as? String, pair["model"] == entry["model"] as? String { throw Refused(words: "\(label) is the \(who)’s own provider and model, so it would move nowhere.") }
            seen.append(pair)
        }
        return steps
    }

    /// `changes` applied together to `entry` and `profiles` (copies the caller owns): a bot the registry does not list, a provider that is not an account, an empty model or an entry left without
    /// identity, provider or model is refused. `called` is how the refusal calls the entry.
    static func applyChanges(_ changes: [RoleChange], to entry: inout [String: Any], profiles: inout [String: Any], called title: String, accounts: [String], bots: [String]) -> String? {
        /// The profile of that kind (and agent) the file has, else a new one named `name`, or `name-2`, `name-3`… when `name` already means something else.
        func profile(_ name: String, kind: String, agent: String?) -> String {
            let found = profiles.keys.sorted().first { (profiles[$0] as? [String: Any]).map { $0["kind"] as? String == kind && $0["agent"] as? String == agent } ?? false }
            var candidate = name
            var number = 2
            while found == nil, profiles[candidate] != nil {
                candidate = "\(name)-\(number)"
                number += 1
            }
            let key = found ?? candidate
            profiles[key] = profiles[key] ?? (agent.map { ["kind": kind, "agent": $0] } ?? ["kind": kind])
            return key
        }
        for change in changes {
            switch change {
            case .bot(let name):
                guard bots.contains(name) else { return "“\(name)” is not in Agent Forge’s list. Pick another one." }
                entry["profile"] = profile(name, kind: "forge", agent: name)
            case .gh: entry["profile"] = profile("gh", kind: "gh", agent: nil)
            case .provider(let provider): entry["provider"] = provider
            case .model(let model): entry["model"] = model.trimmingCharacters(in: .whitespacesAndNewlines)
            case .effort(let effort): entry["effort"] = effort
            }
        }
        let fields = roleFields(entry).normalized()
        if fields.profile == nil || fields.provider == nil || fields.model == nil {
            return fields.model == nil ? "The model cannot be empty." : "\(title) needs an identity, a provider and a model."
        }
        let problems = fields.problems(profiles: Array(profiles.keys), accounts: accounts, bundle: english.bundle, locale: english.locale)
        return problems.isEmpty ? nil : problems.joined(separator: " ")
    }

    // MARK: the extra reviewers

    /// A name an extra reviewer may have: one line of 1 to 40 characters that no other reviewer has, whatever the case (`others` are the entries of the map without this one).
    private static func checkedName(_ name: String, others: [Any]) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw Refused(words: "The name cannot be empty.") }
        if trimmed.utf16.count > 40 || name.contains(where: \.isNewline) { throw Refused(words: "The name is one line of up to 40 characters.") }
        if others.contains(where: { (($0 as? [String: Any])?["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == trimmed.lowercased() }) {
            throw Refused(words: "“\(trimmed)” is already another reviewer’s name. Pick another one.")
        }
        return trimmed
    }

    private static func checkedType(_ type: String) throws -> String {
        let trimmed = type.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: "^[a-z][a-z0-9-]{0,39}$", options: .regularExpression) != nil else {
            throw Refused(words: "The type is a slug of up to 40 characters: it starts with a letter and holds lowercase letters, digits and hyphens.")
        }
        return trimmed
    }

    private static func extrasOf(_ file: [String: Any]) -> [String: Any] { (file["agents"] as? [String: Any])?["extraReviewers"] as? [String: Any] ?? [:] }

    private static func set(_ extras: [String: Any], in file: inout [String: Any]) {
        var agents = file["agents"] as? [String: Any] ?? [:]
        agents["extraReviewers"] = extras.isEmpty ? nil : extras
        file["agents"] = agents
    }

    private static func existing(_ key: String, in extras: [String: Any]) throws -> [String: Any] {
        guard let entry = extras[key] as? [String: Any] else { throw Refused(words: "There is no extra reviewer “\(key)” in engine.json.") }
        return entry
    }

    /// `editRole` pointing at the reviewer `key`: its name, its type and the changes together; the key stays.
    static func editExtra(key: String, name: String?, type: String?, changes: [RoleChange], accounts: [String], bots: [String], to file: inout [String: Any]) -> String? {
        attempt {
            var extras = extrasOf(file)
            var entry = try existing(key, in: extras)
            if let name { entry["name"] = try checkedName(name, others: extras.filter { $0.key != key }.map(\.value)) }
            if let type { entry["type"] = try checkedType(type) }
            var profiles = file["profiles"] as? [String: Any] ?? [:]
            if let words = applyChanges(changes, to: &entry, profiles: &profiles, called: "The extra reviewer", accounts: accounts, bots: bots) { throw Refused(words: words) }
            // a reviewer that now runs on the provider and model one of its own steps names has no use for that step
            if let steps = entry["failover"] as? [[String: Any]] {
                let kept = steps.filter { $0["provider"] as? String != entry["provider"] as? String || $0["model"] as? String != entry["model"] as? String }
                entry["failover"] = kept.isEmpty ? nil : kept
            }
            extras[key] = entry
            set(extras, in: &file)
            file["profiles"] = profiles
        }
    }

    /// `editPersona` pointing at the reviewer `key`.
    static func editExtraPersona(key: String, name: String?, prompt: String?, to file: inout [String: Any]) -> String? {
        attempt {
            let (persona, words) = checkedPersona(name: name, prompt: prompt)
            if let words { throw Refused(words: words) }
            var extras = extrasOf(file)
            var entry = try existing(key, in: extras)
            entry["persona"] = persona.map { ["name": $0.name, "prompt": $0.prompt].compactMapValues { $0 } }
            extras[key] = entry
            set(extras, in: &file)
        }
    }

    /// `editFailover` pointing at the reviewer `key`: its own list, which it has no more of when both steps are nil (it takes the Reviewer's again).
    static func editExtraFailover(key: String, first: FailoverStep?, second: FailoverStep?, accounts: [String], to file: inout [String: Any]) -> String? {
        attempt {
            var extras = extrasOf(file)
            var entry = try existing(key, in: extras)
            let steps = try failoverSteps(first: first, second: second, accounts: accounts, who: "reviewer", before: entry["failover"] as? [[String: Any]] ?? []) { try existing(key, in: extras) }
            entry["failover"] = steps.isEmpty ? nil : steps
            extras[key] = entry
            set(extras, in: &file)
        }
    }

    /// `addExtraReviewer`: the whole entry, with the key its name gives it; a field left out is refused by name, so no half a reviewer is written.
    static func addExtra(draft: [String: Any], accounts: [String], bots: [String], to file: inout [String: Any]) -> String? {
        attempt {
            func text(_ value: Any?) -> String? { (value as? String).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 } }
            let missing = [("name", text(draft["name"])), ("type", text(draft["type"])), ("identity", draft["identity"] as? [String: Any] == nil ? nil : "set"), ("provider", text(draft["provider"])), ("model", text(draft["model"]))]
                .filter { $0.1 == nil }.map(\.0)
            if missing.isEmpty == false { throw Refused(words: "An extra reviewer needs \(missing.joined(separator: ", ")).") }
            let type = try checkedType(draft["type"] as? String ?? "")
            if let effort = text(draft["effort"]), roleEfforts.contains(effort) == false { throw Refused(words: "Effort must be one of \(roleEfforts.joined(separator: ", ")).") }
            var extras = extrasOf(file)
            if extras.count >= RoleSlot.maxExtra { throw Refused(words: "At most \(RoleSlot.maxExtra) extra reviewers: remove one first.") }
            let name = try checkedName(draft["name"] as? String ?? "", others: Array(extras.values))
            var entry: [String: Any] = ["type": type, "name": name]
            var changes: [RoleChange] = []
            if let identity = draft["identity"] as? [String: Any] { changes.append(identity["kind"] as? String == "gh" ? .gh : .bot(identity["agent"] as? String ?? "")) }
            changes.append(.provider(draft["provider"] as? String ?? ""))
            changes.append(.model(draft["model"] as? String ?? ""))
            if let effort = text(draft["effort"]) { changes.append(.effort(effort)) }
            var profiles = file["profiles"] as? [String: Any] ?? [:]
            if let words = applyChanges(changes, to: &entry, profiles: &profiles, called: "An extra reviewer", accounts: accounts, bots: bots) { throw Refused(words: words) }
            extras[extraReviewerKey(name, taken: Set(extras.keys))] = entry
            set(extras, in: &file)
            file["profiles"] = profiles
        }
    }

    /// `setRepoExtraReviewers`: a repo's own map written whole (the entries are what was sent, trimmed; nothing of the earlier map stays), `{}` for none, and nil taking the key out, `agents` going with it when
    /// it was the only one. The entries are checked as the engine does, one by one in the order of their keys, and the first one refused refuses the request.
    static func setRepoExtras(repo: String, reviewers: [String: Any]?, accounts: [String], to file: inout [String: Any]) -> String? {
        attempt {
            guard var repos = file["repos"] as? [[String: Any]], let index = repos.firstIndex(where: { $0["name"] as? String == repo }) else { throw Refused(words: "\(repo) is no longer in the config file.") }
            var own: [String: Any]?
            if let reviewers {
                if reviewers.count > RoleSlot.maxExtra { throw Refused(words: "At most \(RoleSlot.maxExtra) extra reviewers.") }
                var checked: [String: Any] = [:]
                for key in reviewers.keys.sorted() {
                    let sent = reviewers[key] as? [String: Any] ?? [:]
                    func text(_ field: String) -> String? { (sent[field] as? String).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 } }
                    if key.range(of: "^[a-z][a-z0-9-]{0,39}$", options: .regularExpression) == nil || ["author", "reviewer", "lead", "lead-reviewer"].contains(key) {
                        throw Refused(words: "The key “\(key)” is a slug of up to 40 characters that starts with a letter, and it is not author, reviewer, lead, lead-reviewer.")
                    }
                    let missing = ["type", "name", "profile", "provider", "model"].filter { text($0) == nil }
                    if missing.isEmpty == false { throw Refused(words: "An extra reviewer needs \(missing.joined(separator: ", ")).") }
                    var entry: [String: Any] = [
                        "type": try checkedType(text("type") ?? ""), "name": try checkedName(text("name") ?? "", others: Array(checked.values)),
                        "profile": text("profile") ?? "", "provider": text("provider") ?? "", "model": text("model") ?? "",
                    ]
                    entry["effort"] = text("effort")
                    let problems = roleFields(entry).normalized().problems(profiles: Array((file["profiles"] as? [String: Any] ?? [:]).keys), accounts: accounts, bundle: english.bundle, locale: english.locale)
                    if problems.isEmpty == false { throw Refused(words: problems.joined(separator: " ")) }
                    checked[key] = entry
                }
                own = checked
            }
            var agents = repos[index]["agents"] as? [String: Any] ?? [:]
            if let own { agents["extraReviewers"] = own } else { agents["extraReviewers"] = nil }
            repos[index]["agents"] = agents.isEmpty ? nil : agents
            file["repos"] = repos
        }
    }

    /// `removeExtraReviewer`: the entry and its steps, nothing else (the profile it used stays); the map goes with the last one.
    static func removeExtra(key: String, from file: inout [String: Any]) -> String? {
        attempt {
            var extras = extrasOf(file)
            _ = try existing(key, in: extras)
            extras[key] = nil
            set(extras, in: &file)
        }
    }
}
