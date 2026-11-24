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
public func pushedLine(_ iso: String?, now: Date) -> String {
    guard let iso, let date = ISO8601DateFormatter().date(from: iso) else { return "" }
    let seconds = max(0, Int(now.timeIntervalSince(date)))
    let days = seconds / 86_400
    switch seconds {
    case ..<3600: return "pushed just now"
    case ..<86_400: return "pushed \(seconds / 3600) h ago"
    default:
        if days == 1 { return "pushed yesterday" }
        if days < 14 { return "pushed \(days) d ago" }
        if days < 60 { return "pushed \(days / 7) w ago" }
        if days < 365 { return "pushed \(days / 30) mo ago" }
        let months = min(11, days % 365 / 30)
        return "pushed \(days / 365) y\(months > 0 ? " \(months) mo" : "") ago"
    }
}
