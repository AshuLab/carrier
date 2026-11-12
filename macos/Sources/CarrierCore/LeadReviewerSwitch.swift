import Foundation

// The Use a lead reviewer switch of the Agents page (docs/specs/agents-in-settings.md). Off removes `agents.leadReviewer` and its failover steps
// from `config.json` and keeps every other key. On writes nothing until identity, provider and model are chosen (`LeadReviewerDraft`), then the
// whole role goes in one write through `saveGlobalRole`, so the file never holds a half role.

/// What the person has chosen for the Lead reviewer while the switch is on in the page and the file has no role yet.
public struct LeadReviewerDraft: Equatable {
    /// `.bot` or `.gh`
    public var identity: RoleChange?
    public var provider: String?
    public var model = ""
    public var effort: String?

    public init() {}

    public mutating func apply(_ change: RoleChange) {
        switch change {
        case .bot, .gh: identity = change
        case .provider(let provider): self.provider = provider
        case .model(let model): self.model = model
        case .effort(let effort): self.effort = effort
        }
    }

    /// Which of the three required fields are still to choose, in the page's order.
    public var missing: [String] {
        [identity == nil ? "an identity" : nil, provider == nil ? "a provider" : nil,
         model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "a model" : nil].compactMap { $0 }
    }

    public var isComplete: Bool { missing.isEmpty }

    /// Said on the page while the role is not complete: nothing is written until it is.
    public var hint: String? {
        missing.isEmpty ? nil : "Choose \(missing.joined(separator: ", ").replacingLastComma()) to turn it on. Nothing is written until then."
    }

    /// `row` as the page shows it while the draft is being filled in: the draft's choices in place of the empty role.
    public func shown(in row: RoleRow) -> RoleRow {
        var row = row
        row.fields = RoleFields(profile: nil, provider: provider, model: model.isEmpty ? nil : model, effort: effort)
        switch identity {
        case .bot(let name)?: row.identity = .forge(name); row.fields.profile = name
        case .gh?: row.identity = .gh; row.fields.profile = "gh"
        default: row.identity = .unset
        }
        return row
    }

    var changes: [RoleChange] {
        [identity, provider.map(RoleChange.provider), .model(model), effort.map { RoleChange.effort($0) }].compactMap { $0 }
    }
}

private extension String {
    func replacingLastComma() -> String {
        guard let comma = range(of: ", ", options: .backwards) else { return self }
        return replacingCharacters(in: comma, with: " and ")
    }
}

extension RoleRow {
    /// The Lead reviewer's page can be used when the file has the role, or while the person is filling in the one they are turning on.
    public func usable(turningOn: Bool) -> Bool { off == false || turningOn }

    /// The switch row's line: what turning it off does, or that the file has no lead reviewer.
    public var switchDetail: String {
        off ? "Off: the file has no lead reviewer" : "Turning it off removes the lead reviewer and its failover steps from the file"
    }
}

/// Turns the Lead reviewer on with a complete `draft`; an incomplete one is refused before the file is read.
public func turnLeadReviewerOn(_ draft: LeadReviewerDraft, path: String, accounts: [String], bots: [String], reload: Reload = reloadInBackground) -> RoleSave {
    guard draft.isComplete else { return .refused("The lead reviewer needs \(draft.missing.joined(separator: ", ")).") }
    return saveGlobalRole(draft.changes, role: .leadReviewer, path: path, accounts: accounts, bots: bots, creating: true, reload: reload)
}

/// Turns the Lead reviewer off: removes `agents.leadReviewer` and `failover.roles.leadReviewer` from the file at `path`, read just now, and keeps
/// every other key. A file that already has neither is left as it is.
public func turnLeadReviewerOff(path: String, reload: Reload = reloadInBackground) -> RoleSave {
    let url = URL(fileURLWithPath: path)
    guard let current = try? Data(contentsOf: url), var file = (try? JSONSerialization.jsonObject(with: current)) as? [String: Any] else {
        return .failed("The config file could not be read.")
    }
    let key = AgentRole.leadReviewer.rawValue
    var agents = file["agents"] as? [String: Any] ?? [:]
    var failover = file["failover"] as? [String: Any]
    var roles = failover?["roles"] as? [String: Any]
    guard agents[key] != nil || roles?[key] != nil else { return .saved }
    agents[key] = nil
    file["agents"] = agents
    if roles?[key] != nil {
        roles?[key] = nil
        failover?["roles"] = roles
        file["failover"] = failover
    }
    do {
        let updated = try JSONSerialization.data(withJSONObject: file, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try updated.write(to: url, options: .atomic)
        return written(reload)
    } catch {
        FileHandle.standardError.write(Data("carrier: saving \(path) failed: \(error)\n".utf8))
        return .failed("Could not save the config file: \(error.localizedDescription)")
    }
}
