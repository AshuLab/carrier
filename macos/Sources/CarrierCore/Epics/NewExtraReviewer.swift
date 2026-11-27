import Foundation

// The Add a reviewer draft of the Roles page (docs/specs/roles-and-identities-in-settings.md, "A role's screen"), kept as `LeadReviewerDraft` is: nothing is sent until the reviewer has
// a name, a type, an identity, an account and a model, and then the whole entry goes in one request (`EngineConfigChange.addExtraReviewer`), so the file never holds half a reviewer.
// The engine does it and refuses a name another reviewer has (src/config/role-edit.ts, `addExtraReviewer`).

/// What the person has chosen for the extra reviewer they are adding, while it is not in the file yet.
public struct NewExtraReviewer: Equatable, Sendable {
    public var name = ""
    /// A slug that says what it looks at; `general` until the person writes another.
    public var type = "general"
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

    /// The five things the entry needs before it is written; `account` is the provider.
    public enum Field: Equatable { case name, type, identity, account, model }

    /// Which of them are still to choose, in the screen's order. The one rule of what a reviewer needs, for this draft and for an entry of a repo's own list (`RepoExtraReviewer.missing`).
    public static func missing(name: String, type: String, hasIdentity: Bool, hasAccount: Bool, model: String) -> [Field] {
        func empty(_ text: String) -> Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return [empty(name) ? .name : nil, empty(type) ? .type : nil, hasIdentity ? nil : .identity, hasAccount ? nil : .account, empty(model) ? .model : nil].compactMap { $0 }
    }

    /// Which of them are still to choose, in the screen's order.
    public var missing: [Field] { Self.missing(name: name, type: type, hasIdentity: identity != nil, hasAccount: provider != nil, model: model) }

    public var isComplete: Bool { missing.isEmpty }

    /// Another reviewer of `page` has this name, whatever its case (the engine's rule): it would be refused, so the app does not send it.
    public func nameTaken(in page: RolesPage) -> Bool {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return wanted.isEmpty == false && page.rows.contains { $0.slot.isExtra && $0.slot != .draft && ($0.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == wanted }
    }

    /// The whole entry for `addExtraReviewer`; nil while something is missing.
    public var request: ExtraReviewerDraft? {
        guard isComplete, let identity, let provider else { return nil }
        return ExtraReviewerDraft(name: name, type: type, identity: identity, provider: provider, model: model, effort: effort)
    }

    /// Said on the screen while the entry is not saved: what it still needs, or that its name is another reviewer's of `page`.
    public func hint(in page: RolesPage, bundle: Bundle? = nil, locale: Locale = .current) -> String? {
        if missing.isEmpty == false { return Self.hint(missing: missing, bundle: bundle, locale: locale) }
        return nameTaken(in: page) ? Copy.watchingOwnNameTaken(name: name.trimmingCharacters(in: .whitespacesAndNewlines), bundle: bundle, locale: locale) : nil
    }

    /// Said on the screen while the entry is not complete: it is not saved and nothing is written until it is.
    public func hint(bundle: Bundle? = nil, locale: Locale = .current) -> String? { Self.hint(missing: missing, bundle: bundle, locale: locale) }

    /// "Not saved yet. It needs a name, a type and an identity; …" for what is `missing`; nil when nothing is.
    public static func hint(missing: [Field], bundle: Bundle? = nil, locale: Locale = .current) -> String? {
        let names = missing.map { field in
            switch field {
            case .name: Copy.rolesDraftNeeds(which: .name, bundle: bundle, locale: locale)
            case .type: Copy.rolesDraftNeeds(which: .type, bundle: bundle, locale: locale)
            case .identity: Copy.rolesDraftNeeds(which: .identity, bundle: bundle, locale: locale)
            case .account: Copy.rolesDraftNeeds(which: .account, bundle: bundle, locale: locale)
            case .model: Copy.rolesDraftNeeds(which: .model, bundle: bundle, locale: locale)
            }
        }
        guard let last = names.last else { return nil }
        // "a name", "a name and a type", "a name, a type and an identity"
        let list = names.count == 1 ? last : Copy.engineNamesAnd(first: names.dropLast().joined(separator: ", "), second: last, bundle: bundle, locale: locale)
        return Copy.rolesDraftHint(list: list, bundle: bundle, locale: locale)
    }

    /// The reviewer as the page shows it while it is being filled in: its choices, the Reviewer's failover steps (it has none of its own) and no key, since the engine gives it one when it is written.
    public func row(in page: RolesPage, bundle: Bundle? = nil, locale: Locale = .current) -> RoleRow {
        var identity = RoleIdentity.unset
        var profile: String?
        switch self.identity {
        case .bot(let bot)?: (identity, profile) = (.forge(bot), bot)
        case .gh?: (identity, profile) = (.gh, "gh")
        default: break
        }
        return RoleRow(
            slot: .draft, name: name.isEmpty ? nil : name, type: type, what: RoleSlot.draft.purpose(bundle: bundle, locale: locale),
            fields: RoleFields(profile: profile, provider: provider, model: model.isEmpty ? nil : model, effort: effort), identity: identity,
            providerMissing: false, steps: page.rows.first { $0.slot == .reviewer }?.steps ?? [], ownSteps: false, off: false, drafting: true
        )
    }
}

extension RoleSlot {
    /// The reviewer being added: the map has no key for it until the engine writes it, and no key is empty.
    public static let draft = RoleSlot.extra(key: "")

    /// The place of the draft's screen, which no key can spell (a key starts with a letter).
    public static let draftPlaceName = "_new"
}

extension RolesPage {
    /// The page with the reviewer being added in the order of the epic, before the Lead reviewer: the strip of a role's screen shows it.
    public func adding(_ draft: RoleRow) -> RolesPage {
        var page = self
        page.rows.insert(draft, at: rows.firstIndex { $0.slot == .lead } ?? rows.endIndex)
        return page
    }
}
