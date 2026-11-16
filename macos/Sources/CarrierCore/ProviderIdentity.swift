import Foundation

// What tells one account from another where the app names it: an icon, a color and a label, each optional, kept on the account in
// `providers.json` next to its `displayName` (the engine's schema, `src/config/providers.ts`, is the source of the allowed values).

/// The eight colors an account can have. Names, not hex: the app tints for light and dark, and a name the engine does not know reads as none.
public enum AccountColor: String, CaseIterable {
    case red, orange, yellow, green, teal, blue, purple, pink
}

/// The icons an account can have besides its tool's own mark (which is no icon at all): a glyph, or the account's first letter.
public enum AccountIcon: String, CaseIterable {
    case bolt, star, briefcase, person, people, code, flask, leaf, moon, heart, cube, letter

    /// The SF Symbol of a glyph; nil for `letter`.
    public var symbol: String? {
        switch self {
        case .bolt: "bolt"
        case .star: "star"
        case .briefcase: "briefcase"
        case .person: "person"
        case .people: "person.2"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .flask: "flask"
        case .leaf: "leaf"
        case .moon: "moon"
        case .heart: "heart"
        case .cube: "cube"
        case .letter: nil
        }
    }
}

/// An account's icon, color and label as `providers.json` has them. Every part is optional; a value the schema would refuse reads as absent.
public struct ProviderIdentity: Equatable {
    public var icon: AccountIcon?
    public var color: AccountColor?
    public var label: String?

    public static let none = ProviderIdentity()
    /// The most characters a label has (the engine's limit).
    public static let labelLimit = 12

    public init(icon: AccountIcon? = nil, color: AccountColor? = nil, label: String? = nil) {
        self.icon = icon
        self.color = color
        self.label = label
    }

    /// From an account object of the file.
    public init(account: [String: Any]) {
        icon = (account["icon"] as? String).flatMap(AccountIcon.init(rawValue:))
        color = (account["color"] as? String).flatMap(AccountColor.init(rawValue:))
        label = (account["label"] as? String).map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty || $0.count > Self.labelLimit ? nil : $0 }
    }
}

/// The identity of each account of `providers.json`, by account name; an account with none is not in the result.
public func providerIdentities(providersJSON: Data?) -> [String: ProviderIdentity] {
    guard let providersJSON, let file = (try? JSONSerialization.jsonObject(with: providersJSON)) as? [String: Any],
          let declared = file["providers"] as? [String: Any]
    else { return [:] }
    return declared.reduce(into: [:]) { identities, entry in
        guard let account = entry.value as? [String: Any] else { return }
        let identity = ProviderIdentity(account: account)
        if identity != .none { identities[entry.key] = identity }
    }
}
