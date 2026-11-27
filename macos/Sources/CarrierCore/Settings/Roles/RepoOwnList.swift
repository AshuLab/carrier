import Foundation

// A repo's own list of extra reviewers, as Watching edits it (docs/specs/roles-and-identities-in-settings.md, "Watching" and "How the app writes"): the engine replaces the global map with a repo's whole,
// so the three choices are one request each (`setRepoExtraReviewers`: `nil` takes the repo's key out, `[]` is none, a list is the map) and every change of an own list sends the whole map again.
// The engine writes the file and checks it (src/config/role-edit.ts, `setRepoExtraReviewers`); this only decides what is sent and what waits. The persona, failover steps and skills of an entry are the Reviewer's.

extension RepoExtraReviewer: Identifiable {
    public var id: String { key }
}

/// The reviewers of the map `agents.extraReviewers` of `config`, as the file has them and in its order (an entry that lacks a field has it empty, so the engine refuses it by name when the map is sent).
public func rolesExtraEntries(config: Data) -> [RepoExtraReviewer] {
    guard let file = (try? JSONSerialization.jsonObject(with: config)) as? [String: Any] else { return [] }
    let map = (file["agents"] as? [String: Any])?["extraReviewers"] as? [String: Any] ?? [:]
    return entries(map, keys: jsonKeys(in: config, at: ["agents", "extraReviewers"]) ?? [])
}

/// The reviewers of `repo`'s own map, in the order of the file; empty when it has no map or an empty one.
public func repoOwnEntries(config: Data, repo: String) -> [RepoExtraReviewer] {
    guard let file = (try? JSONSerialization.jsonObject(with: config)) as? [String: Any],
        let position = (file["repos"] as? [[String: Any]])?.firstIndex(where: { $0["name"] as? String == repo }),
        let map = ((file["repos"] as? [[String: Any]])?[position]["agents"] as? [String: Any])?["extraReviewers"] as? [String: Any]
    else { return [] }
    return entries(map, keys: jsonKeys(in: config, at: ["repos", String(position), "agents", "extraReviewers"]) ?? [])
}

private func entries(_ map: [String: Any], keys: [String]) -> [RepoExtraReviewer] {
    keys.compactMap { key in
        guard let entry = map[key] as? [String: Any] else { return nil }
        func text(_ field: String) -> String { entry[field] as? String ?? "" }
        return RepoExtraReviewer(key: key, type: text("type"), name: text("name"), profile: text("profile"), provider: text("provider"), model: text("model"), effort: (entry["effort"] as? String).flatMap { $0.isEmpty ? nil : $0 })
    }
}

extension RepoExtraReviewers {
    /// The request that choosing this state sends for `repo`: Same as everywhere takes the key out, None is `{}`, and Own list is a copy of the map of Roles (`roles`), sent whole.
    /// nil for an Own list that would start empty, since Roles has no extra reviewers: `{}` would be None, so nothing is written until the first entry is added.
    public func choosing(repo: String, roles: [RepoExtraReviewer]) -> EngineConfigChange? {
        switch self {
        case .sameAsEverywhere: .repoExtraReviewers(repo: repo, nil)
        case .noExtras: .repoExtraReviewers(repo: repo, [])
        case .ownList: roles.isEmpty ? nil : .repoExtraReviewers(repo: repo, roles)
        }
    }
}

/// One field of an entry of an own list, as its screen changes it: the name, the type, the identity (the name of a profile of the file), the account with the model chosen on it, or the effort (nil takes it out).
public enum RepoReviewerEdit: Equatable, Sendable {
    case name(String)
    case type(String)
    case profile(String)
    case account(provider: String, model: String?)
    case effort(String?)
}

extension RepoExtraReviewer {
    /// The reviewer being added to a repo's own list, while it is not in the file yet: no key (the list gives it one when it is added), a `general` type, and nothing else. It is an entry with its
    /// fields empty, which is what a file's entry that lacks them reads as, so one type and one `applying` serve the entries and the draft.
    public static var draft: RepoExtraReviewer { RepoExtraReviewer(key: "", type: "general", name: "", profile: "", provider: "", model: "") }

    /// Which of the five things the entry needs are still to choose, in the screen's order.
    public var missing: [NewExtraReviewer.Field] {
        NewExtraReviewer.missing(name: name, type: type, hasIdentity: profile.isEmpty == false, hasAccount: provider.isEmpty == false, model: model)
    }

    public var isComplete: Bool { missing.isEmpty }

    public func applying(_ edit: RepoReviewerEdit) -> RepoExtraReviewer {
        var next = self
        switch edit {
        case .name(let name): next.name = name
        case .type(let type): next.type = type
        case .profile(let profile): next.profile = profile
        case .account(let provider, let model):
            next.provider = provider
            if let model { next.model = model }
        case .effort(let effort): next.effort = effort
        }
        return next
    }
}

/// A repo's own list as the screen edits it: each change gives the list the whole map would then be, which the screen sends with `request(repo:)`.
public struct RepoOwnList: Equatable, Sendable {
    public var entries: [RepoExtraReviewer]

    public init(_ entries: [RepoExtraReviewer]) { self.entries = entries }

    /// Add a reviewer is on while there are fewer than three (four reviewers with the Reviewer).
    public var canAdd: Bool { entries.count < RoleSlot.maxExtra }

    public func request(repo: String) -> EngineConfigChange { .repoExtraReviewers(repo: repo, entries) }

    /// Another entry than `key` has this name, whatever its case: the engine refuses two reviewers with one name, so the app does not send them.
    public func nameTaken(_ name: String, except key: String? = nil) -> Bool {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return entries.contains { $0.key != key && $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == wanted }
    }

    /// The list with `edit` applied to the entry `key` (the key stays, whatever the name becomes); the same list when there is no such entry, and nil when the edit gives it a name another entry has.
    public func applying(_ edit: RepoReviewerEdit, to key: String) -> RepoOwnList? {
        if case .name(let name) = edit, nameTaken(name, except: key) { return nil }
        return RepoOwnList(entries.map { $0.key == key ? $0.applying(edit) : $0 })
    }

    public func removing(_ key: String) -> RepoOwnList { RepoOwnList(entries.filter { $0.key != key }) }

    /// The list with the draft at the end, under the key its name gives it; nil while the draft is not complete, its name is another's or there are three already.
    public func adding(_ draft: RepoExtraReviewer) -> RepoOwnList? {
        guard canAdd, draft.isComplete, nameTaken(draft.name) == false else { return nil }
        var entry = draft
        entry.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.key = extraReviewerKey(entry.name, taken: Set(entries.map(\.key)))
        return RepoOwnList(entries + [entry])
    }

    /// Said on the screen while the draft is not saved: what it still needs, or that its name is another's.
    public func hint(for draft: RepoExtraReviewer, bundle: Bundle? = nil, locale: Locale = .current) -> String? {
        if draft.missing.isEmpty == false { return NewExtraReviewer.hint(missing: draft.missing, bundle: bundle, locale: locale) }
        return nameTaken(draft.name) ? Copy.watchingOwnNameTaken(name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines), bundle: bundle, locale: locale) : nil
    }
}

/// The key an extra reviewer gets from its name (`extraReviewerKey` of src/config/extra-reviewer-key.ts), never typed: lowercase, accents out, every run of other characters one hyphen, `r-` in front
/// when it does not start with a letter, `extra` when nothing is left, cut so the key is at most 40 characters, and `-2`, `-3`… while it is taken or is a role's word.
public func extraReviewerKey(_ name: String, taken: Set<String>) -> String {
    let slug = name.folding(options: .diacriticInsensitive, locale: nil).lowercased()
        .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    let base = slug.isEmpty ? "extra" : slug.first?.isLetter == true ? slug : "r-\(slug)"
    for number in 1... {
        let suffix = number == 1 ? "" : "-\(number)"
        let key = String(base.prefix(40 - suffix.count)) + suffix
        if taken.contains(key) == false, ["author", "reviewer", "lead", "lead-reviewer"].contains(key) == false { return key }
    }
    return base
}
