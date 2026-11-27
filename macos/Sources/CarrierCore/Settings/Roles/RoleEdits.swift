import Foundation

// What a role's screen sends as a field changes (docs/specs/roles-and-identities-in-settings.md, "How the app writes"): the three fixed roles keep the requests they use, and an extra reviewer's
// are the same requests pointing at it by its key (ADR 0057), which does not change when its name does. The engine (src/config/role-edit.ts) writes `engine.json`, one request at a time through `EngineConfigQueue`.

extension RoleSlot {
    /// The pick of a field or two of the Who and Model groups.
    public func edit(_ changes: [RoleChange]) -> EngineConfigChange {
        switch self {
        case .author: .role(.author, changes)
        case .reviewer: .role(.reviewer, changes)
        case .lead: .role(.leadReviewer, changes)
        case .extra(let key): .extraReviewerRole(key: key, name: nil, type: nil, changes)
        }
    }

    /// The Persona group: either text alone, or both; nil for both takes it out.
    public func persona(name: String?, prompt: String?) -> EngineConfigChange {
        switch self {
        case .author: .persona(role: .author, name: name, prompt: prompt)
        case .reviewer: .persona(role: .reviewer, name: name, prompt: prompt)
        case .lead: .persona(role: .leadReviewer, name: name, prompt: prompt)
        case .extra(let key): .extraReviewerPersona(key: key, name: name, prompt: prompt)
        }
    }

    /// The first two steps of When it runs out of tokens; both nil takes the role's own list out (an extra reviewer then takes the Reviewer's).
    public func failover(first: FailoverStep?, second: FailoverStep?) -> EngineConfigChange {
        switch self {
        case .author: .failover(role: .author, first: first, second: second)
        case .reviewer: .failover(role: .reviewer, first: first, second: second)
        case .lead: .failover(role: .leadReviewer, first: first, second: second)
        case .extra(let key): .extraReviewerFailover(key: key, first: first, second: second)
        }
    }

    /// An extra reviewer's new name; the key stays. nil for the fixed roles, which have none.
    public func renamed(_ name: String) -> EngineConfigChange? {
        guard case .extra(let key) = self else { return nil }
        return .extraReviewerRole(key: key, name: name, type: nil, [])
    }

    /// An extra reviewer's new type. nil for the fixed roles.
    public func retyped(_ type: String) -> EngineConfigChange? {
        guard case .extra(let key) = self else { return nil }
        return .extraReviewerRole(key: key, name: nil, type: type, [])
    }

    /// Takes an extra reviewer out of the file, and nothing else. nil for the fixed roles.
    public var removal: EngineConfigChange? {
        guard case .extra(let key) = self else { return nil }
        return .removeExtraReviewer(key: key)
    }
}

/// What the Roles page offers for the extra reviewers. The engine announces `extraReviewers` when it has the requests that edit them; without it the fields are read only and there is no Add a reviewer.
public struct ExtraReviewerOffer: Equatable, Sendable {
    /// The hello of the engine lists `extraReviewers`.
    public var canEdit: Bool
    public var count: Int

    public init(canEdit: Bool, count: Int) { (self.canEdit, self.count) = (canEdit, count) }

    public init(canEdit: Bool, page: RolesPage) { self.init(canEdit: canEdit, count: page.rows.filter { $0.slot.isExtra }.count) }

    /// Add a reviewer is on the page only for an engine that can write it.
    public var showsAdd: Bool { canEdit }

    /// It is on while fewer than three extra reviewers (four reviewers with the Reviewer) are in the file.
    public var canAdd: Bool { canEdit && count < RoleSlot.maxExtra }

    /// Under Add a reviewer: how many more can run, or that four is the most.
    public func addDetail(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        count < RoleSlot.maxExtra ? Copy.rolesAddReviewerCan(count: RoleSlot.maxExtra - count, bundle: bundle, locale: locale) : Copy.rolesAddReviewerFull(bundle: bundle, locale: locale)
    }
}
