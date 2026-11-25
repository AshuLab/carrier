import Foundation

// The Use a lead reviewer switch of the Agents page (docs/specs/agents-in-settings.md). Off removes `agents.leadReviewer` and its failover steps
// from `engine.json` and keeps every other key. On sends nothing until identity, provider and model are chosen (`LeadReviewerDraft`), then the
// whole role goes in one request (`EngineConfigChange.leadReviewer`), so the file never holds a half role; the engine does it (src/config/role-edit.ts, `setLeadReviewer`).

/// What the person has chosen for the Lead reviewer while the switch is on in the page and the file has no role yet.
public struct LeadReviewerDraft: Equatable, Sendable {
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
        row.drafting = true
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
