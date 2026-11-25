import Foundation

// What tells one account from another where the app names it: an icon, a color and a label, each optional, kept on the account in
// `providers.json` next to its `displayName` (the engine's schema, `src/config/providers.ts`, is the source of the allowed values).

/// The colors an account can have. Names, not hex: the app tints for light and dark, and a name the engine does not know reads as none.
/// The first eight are the ones every host with `accountIdentity` knows; the rest need `accountPalette` (`offered(palette:)`).
public enum AccountColor: String, CaseIterable {
    case red, orange, yellow, green, teal, blue, purple, pink
    case mint, cyan, indigo, brown, gray

    private static let earlier = 8

    /// What the editor offers: all of them when the host knows the later ones, else the first eight, which an older host takes.
    public static func offered(palette: Bool) -> [AccountColor] { palette ? allCases : Array(allCases.prefix(earlier)) }

    /// The color's name as the person reads it.
    public func title(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        switch self {
        case .red: Copy.providersColorName(which: .red, bundle: bundle, locale: locale)
        case .orange: Copy.providersColorName(which: .orange, bundle: bundle, locale: locale)
        case .yellow: Copy.providersColorName(which: .yellow, bundle: bundle, locale: locale)
        case .green: Copy.providersColorName(which: .green, bundle: bundle, locale: locale)
        case .teal: Copy.providersColorName(which: .teal, bundle: bundle, locale: locale)
        case .blue: Copy.providersColorName(which: .blue, bundle: bundle, locale: locale)
        case .purple: Copy.providersColorName(which: .purple, bundle: bundle, locale: locale)
        case .pink: Copy.providersColorName(which: .pink, bundle: bundle, locale: locale)
        case .mint: Copy.providersColorName(which: .mint, bundle: bundle, locale: locale)
        case .cyan: Copy.providersColorName(which: .cyan, bundle: bundle, locale: locale)
        case .indigo: Copy.providersColorName(which: .indigo, bundle: bundle, locale: locale)
        case .brown: Copy.providersColorName(which: .brown, bundle: bundle, locale: locale)
        case .gray: Copy.providersColorName(which: .gray, bundle: bundle, locale: locale)
        }
    }
}

/// The icons an account can have besides its tool's own mark (which is no icon at all): a glyph, or the account's first letter.
/// The first twelve are the ones every host with `accountIdentity` knows; the rest need `accountPalette` (`offered(palette:)`).
public enum AccountIcon: String, CaseIterable {
    case bolt, star, briefcase, person, people, code, flask, leaf, moon, heart, cube, letter
    case flame, sparkles, paperplane, globe, shield, key, house, book, hammer, cloud, bell

    private static let earlier = 12

    /// What the editor offers: all of them when the host knows the later ones, else the first twelve, which an older host takes.
    public static func offered(palette: Bool) -> [AccountIcon] { palette ? allCases : Array(allCases.prefix(earlier)) }

    /// The icon's name as the person reads it.
    public func title(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        switch self {
        case .bolt: Copy.providersIconName(which: .bolt, bundle: bundle, locale: locale)
        case .star: Copy.providersIconName(which: .star, bundle: bundle, locale: locale)
        case .briefcase: Copy.providersIconName(which: .briefcase, bundle: bundle, locale: locale)
        case .person: Copy.providersIconName(which: .person, bundle: bundle, locale: locale)
        case .people: Copy.providersIconName(which: .people, bundle: bundle, locale: locale)
        case .code: Copy.providersIconName(which: .code, bundle: bundle, locale: locale)
        case .flask: Copy.providersIconName(which: .flask, bundle: bundle, locale: locale)
        case .leaf: Copy.providersIconName(which: .leaf, bundle: bundle, locale: locale)
        case .moon: Copy.providersIconName(which: .moon, bundle: bundle, locale: locale)
        case .heart: Copy.providersIconName(which: .heart, bundle: bundle, locale: locale)
        case .cube: Copy.providersIconName(which: .cube, bundle: bundle, locale: locale)
        case .letter: Copy.providersIconName(which: .letter, bundle: bundle, locale: locale)
        case .flame: Copy.providersIconName(which: .flame, bundle: bundle, locale: locale)
        case .sparkles: Copy.providersIconName(which: .sparkles, bundle: bundle, locale: locale)
        case .paperplane: Copy.providersIconName(which: .paperplane, bundle: bundle, locale: locale)
        case .globe: Copy.providersIconName(which: .globe, bundle: bundle, locale: locale)
        case .shield: Copy.providersIconName(which: .shield, bundle: bundle, locale: locale)
        case .key: Copy.providersIconName(which: .key, bundle: bundle, locale: locale)
        case .house: Copy.providersIconName(which: .house, bundle: bundle, locale: locale)
        case .book: Copy.providersIconName(which: .book, bundle: bundle, locale: locale)
        case .hammer: Copy.providersIconName(which: .hammer, bundle: bundle, locale: locale)
        case .cloud: Copy.providersIconName(which: .cloud, bundle: bundle, locale: locale)
        case .bell: Copy.providersIconName(which: .bell, bundle: bundle, locale: locale)
        }
    }

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
        case .flame: "flame"
        case .sparkles: "sparkles"
        case .paperplane: "paperplane"
        case .globe: "globe"
        case .shield: "shield"
        case .key: "key"
        case .house: "house"
        case .book: "book"
        case .hammer: "hammer"
        case .cloud: "cloud"
        case .bell: "bell"
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

/// The display name of each account of `providers.json` that has one, by account name: what the app calls the account where there is room,
/// and where there is little the short name falls back to it when the account has no label.
public func providerDisplayNames(providersJSON: Data?) -> [String: String] {
    guard let providersJSON, let file = (try? JSONSerialization.jsonObject(with: providersJSON)) as? [String: Any],
          let declared = file["providers"] as? [String: Any]
    else { return [:] }
    return declared.reduce(into: [:]) { names, entry in
        guard let account = entry.value as? [String: Any], let name = (account["displayName"] as? String)?.trimmingCharacters(in: .whitespaces), name.isEmpty == false
        else { return }
        names[entry.key] = name
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

/// The short name of an account where there is little room: its label, else its display name, else the name it has always had. `agent` is an
/// account or a chat agent that runs on one.
public func providerShortName(of agent: String, identities: [String: ProviderIdentity], displayNames: [String: String]) -> String {
    let account = AgentAccounts.account(of: agent)
    return (identities[account] ?? .none).label ?? displayNames[account] ?? agent
}

/// What an account's mark is drawn from: the SF Symbol of its glyph, or the letter it was given (`initials`, the first of the name it is shown
/// under), else the tool whose mark stands for it; and its color, which is none when the account has none.
public struct AccountMarkLook: Equatable {
    public var symbol: String?
    public var initials: String
    public var tool: String
    public var color: AccountColor?
}

/// The look of the mark of `account` (an account or a chat agent that runs on one) given its identity. `icon` is what the tool's mark is looked up
/// by when the account has no icon of its own; the harness of the agent when not given.
public func accountMarkLook(of account: String, identity: ProviderIdentity, icon: String? = nil) -> AccountMarkLook {
    let tool = icon ?? AgentAccounts.harness(of: account)
    let initials = identity.icon == .letter ? String(account.prefix(1)).uppercased() : ""
    return AccountMarkLook(symbol: identity.icon?.symbol, initials: initials, tool: tool, color: identity.color)
}
