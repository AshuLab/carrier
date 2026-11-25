import Foundation

/// What Claude Code says when the agent publishes a code change (`code_change_published`): "created 946 (the-branch)", "pushed 738".
/// The engine keeps it as a note; the epic draws it as a row of its own, with the pull request as a link.
public struct PublishedNote: Equatable {
    /// "Created", "Pushed to", "Updated" (or their words in the other language): the words before the pull request.
    public var verb: String
    /// The pull request's number, when the identifier is one.
    public var number: Int?
    /// What Claude Code gave as the identifier, whole.
    public var identifier: String
    public var branch: String?
}

private let publishedVerbs: [String: Copy.PublishedVerb] = [
    "created": .created, "pushed": .pushed, "updated": .updated, "published": .published, "merged": .merged, "closed": .closed,
]

/// nil for any other note. Only the verbs above are read; anything else stays the plain line it was. The verb is said in the language of `locale`.
public func publishedNote(_ text: String, bundle: Bundle? = nil, locale: Locale = .current) -> PublishedNote? {
    let parts = text.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true).map(String.init)
    guard parts.count >= 2, let word = publishedVerbs[parts[0]] else { return nil }
    let verb = Copy.publishedVerb(verb: word, bundle: bundle, locale: locale)
    var branch: String?
    if parts.count == 3 {
        guard parts[2].hasPrefix("("), parts[2].hasSuffix(")") else { return nil }
        branch = String(parts[2].dropFirst().dropLast())
    }
    let identifier = parts[1]
    return PublishedNote(verb: verb, number: Int(identifier.drop { $0 == "#" }), identifier: identifier, branch: branch)
}
