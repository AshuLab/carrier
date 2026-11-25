import Foundation

// A repository of the person's GitHub as the chat host lists it (the Add project sheet's search), and how long ago it was pushed. The app has no GitHub
// token (ADR 0005); the host does the read.

public struct AvailableRepo: Decodable, Equatable, Sendable {
    public var name: String
    public var isPrivate: Bool
    /// ISO 8601; nil when GitHub gave none.
    public var pushedAt: String?
    /// What GitHub says the repository is, in one line; only the chat host's listing carries it.
    public var about: String?

    public init(name: String, isPrivate: Bool = false, pushedAt: String? = nil, about: String? = nil) {
        self.name = name
        self.isPrivate = isPrivate
        self.pushedAt = pushedAt
        self.about = about
    }

    enum CodingKeys: String, CodingKey {
        case name, pushedAt
        case isPrivate = "private"
        case about = "description"
    }
}

/// "pushed 3 d ago", "pushed 1 y 2 mo ago"; empty when GitHub gave no time.
public func pushedLine(_ iso: String?, now: Date, bundle: Bundle? = nil, locale: Locale = .current) -> String {
    guard let iso, let date = ISO8601DateFormatter().date(from: iso) else { return "" }
    let seconds = max(0, Int(now.timeIntervalSince(date)))
    let days = seconds / 86_400
    switch seconds {
    case ..<3600: return Copy.projectsPushedNow(bundle: bundle, locale: locale)
    case ..<86_400: return Copy.projectsPushedHours(count: seconds / 3600, bundle: bundle, locale: locale)
    default:
        if days == 1 { return Copy.projectsPushedYesterday(bundle: bundle, locale: locale) }
        if days < 14 { return Copy.projectsPushedDays(count: days, bundle: bundle, locale: locale) }
        if days < 60 { return Copy.projectsPushedWeeks(count: days / 7, bundle: bundle, locale: locale) }
        if days < 365 { return Copy.projectsPushedMonths(count: days / 30, bundle: bundle, locale: locale) }
        let months = min(11, days % 365 / 30)
        if months > 0 { return Copy.projectsPushedYearsMonths(years: days / 365, months: months, bundle: bundle, locale: locale) }
        return Copy.projectsPushedYears(years: days / 365, bundle: bundle, locale: locale)
    }
}
