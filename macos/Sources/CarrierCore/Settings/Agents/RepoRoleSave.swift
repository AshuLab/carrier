import Foundation

// A repo's role: the app sends `EngineConfigChange.repoRole` and the engine (src/config/role-edit.ts) writes `repos[].agents.<role>` of `engine.json`. What the page checks while the person
// types (`RoleFields.problems`) is here, and the fixture engine makes the same checks (FixtureServer+EngineConfig.swift).

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
    public func problems(profiles: [String], accounts: [String], bundle: Bundle? = nil, locale: Locale = .current) -> [String] {
        var found: [String] = []
        if let profile, profiles.contains(profile) == false { found.append(Copy.agentsFieldIdentity(profile: profile, bundle: bundle, locale: locale)) }
        if let provider, accounts.contains(provider) == false { found.append(Copy.agentsFieldProvider(provider: provider, bundle: bundle, locale: locale)) }
        if let effort, roleEfforts.contains(effort) == false { found.append(Copy.agentsFieldEffort(efforts: roleEfforts.joined(separator: ", "), bundle: bundle, locale: locale)) }
        if let name = persona?.name, name.count > 40 || name.contains(where: \.isNewline) { found.append(Copy.agentsFieldPersonaName(bundle: bundle, locale: locale)) }
        if let prompt = persona?.prompt, prompt.count > 4000 { found.append(Copy.agentsFieldPersonaPrompt(bundle: bundle, locale: locale)) }
        return found
    }
}

/// Said under a repo's roles when Author and Reviewer resolve to one identity: the engine accepts it and shares the epic's account.
public func signatureNote(_ rows: [RepoRoleRow], bundle: Bundle? = nil, locale: Locale = .current) -> String? {
    guard let author = rows.first(where: { $0.role == .author })?.value.profile,
          rows.first(where: { $0.role == .reviewer })?.value.profile == author
    else { return nil }
    return Copy.agentsSharedSame(profile: author, bundle: bundle, locale: locale)
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
