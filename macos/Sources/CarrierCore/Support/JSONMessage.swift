import Foundation

/// An agent's message that is one JSON object (a `ship` slice report, say), as the view lays it out instead of the raw braces.
public enum JSONMessage: Equatable {
    case slice(SliceReport)
    /// Any other object: a label and a value per key, in the order the agent wrote them.
    case fields([JSONField])
}

/// What `ship` prints when a slice is done: the keys the report card knows.
public struct SliceReport: Equatable {
    /// "Slice #285"; nil when the report has no `slice`.
    public var title: String?
    /// "Ready to merge".
    public var outcome: String
    public var tone: ResultCard.Tone
    /// "PR #289" and where it lives; nil without a web address.
    public var pull: ReportLink?
    public var branch: String?
    /// The definition of done, the ones that are not done first.
    public var checks: [ReportCheck]
    public var note: String?
}

public struct ReportCheck: Equatable {
    public var name: String
    public var passed: Bool
}

public struct ReportLink: Equatable {
    public var label: String
    public var url: URL
}

public struct JSONField: Equatable {
    public var label: String
    public var value: Value

    public enum Value: Equatable {
        case flag(Bool)
        case number(String)
        case text(String)
        /// A branch, a path, an id: one word with a slash or a hash in it.
        case code(String)
        case link(ReportLink)
        case list([String])
        /// An object of true and false, as a checklist.
        case checks([ReportCheck])
    }
}

private let sliceKeys: Set = ["slice", "outcome", "branch", "pr", "definitionOfDone", "note"]

/// The message as a JSON object, bare or in a code fence; nil when it is anything else, which stays text. The slice report
/// needs exactly its keys, so a report with an extra one shows every key as a field instead of dropping it.
public func jsonMessage(_ text: String, bundle: Bundle? = nil, locale: Locale = .current) -> JSONMessage? {
    var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if body.hasPrefix("```") {
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 2, lines.last == "```" else { return nil }
        body = lines.dropFirst().dropLast().joined(separator: "\n")
    }
    guard body.hasPrefix("{"), let object = (try? JSONSerialization.jsonObject(with: Data(body.utf8), options: .json5Allowed)) as? [String: Any], object.isEmpty == false
    else { return nil }
    // ponytail: JSONSerialization loses the key order, so keys go by where their name first shows in the text (quoted, or bare as
    // JSON5 allows: the `ship` skill's template has bare keys and agents copy it); a nested key with the same name earlier would
    // swap two fields. A real ordered parser if that ever shows.
    func position(_ key: String) -> String.Index {
        (body.range(of: "\"\(key)\"") ?? body.range(of: "\(key):"))?.lowerBound ?? body.endIndex
    }
    func ordered<V>(_ dict: [String: V]) -> [(key: String, value: V)] {
        dict.map { (key: $0.key, value: $0.value) }.sorted { position($0.key) < position($1.key) }
    }
    func checks(_ value: Any) -> [ReportCheck]? {
        guard let dict = value as? [String: Any], dict.isEmpty == false else { return nil }
        let all = ordered(dict).compactMap { entry in flag(entry.value).map { ReportCheck(name: entry.key, passed: $0) } }
        return all.count == dict.count ? all.filter { $0.passed == false } + all.filter(\.passed) : nil
    }
    if object.keys.allSatisfy(sliceKeys.contains), let outcome = object["outcome"] as? String, let done = object["definitionOfDone"].flatMap(checks) {
        let pull = (object["pr"] as? String).flatMap(browserURL).map { ReportLink(label: pullLabel($0, bundle: bundle, locale: locale), url: $0) }
        let title = sliceTitle(object["slice"], bundle: bundle, locale: locale)
        return .slice(SliceReport(
            title: title, outcome: sentence(outcome),
            tone: outcome.contains("ready") ? .good : outcome.contains("human") ? .stop : .warning,
            pull: pull, branch: object["branch"] as? String, checks: done, note: object["note"] as? String
        ))
    }
    return .fields(ordered(object).compactMap { key, value in
        fieldValue(value, checks: checks).map { JSONField(label: sentence(key), value: $0) }
    })
}

/// A JSON true or false; `as? Bool` alone also takes the numbers 0 and 1.
private func flag(_ value: Any) -> Bool? {
    guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
    return number.boolValue
}

private func fieldValue(_ value: Any, checks: (Any) -> [ReportCheck]?) -> JSONField.Value? {
    if let on = flag(value) { return .flag(on) }
    if let number = value as? NSNumber { return .number(number.stringValue) }
    if let text = value as? String {
        if let url = browserURL(text) { return .link(ReportLink(label: url.host == "github.com" ? String(url.path.dropFirst()) : text, url: url)) }
        let word = text.contains(where: \.isWhitespace) == false && text.contains(where: { "/#".contains($0) })
        return word ? .code(text) : .text(text)
    }
    if let list = value as? [Any], list.allSatisfy({ $0 is String || $0 is NSNumber }) { return .list(list.map { "\($0)" }) }
    if let done = checks(value) { return .checks(done) }
    if value is NSNull { return nil }
    // a nested object or a list of them: what the agent sent, compact, rather than a guess at its shape
    return JSONSerialization.isValidJSONObject(value)
        ? (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])).map { .code(String(decoding: $0, as: UTF8.self)) }
        : nil
}

/// "Slice #285" for the report's `slice`, a string that says its own "#" or a bare number; nil when it is neither.
private func sliceTitle(_ slice: Any?, bundle: Bundle?, locale: Locale) -> String? {
    if let text = slice as? String { return Copy.jsonMessageSlice(slice: text, bundle: bundle, locale: locale) }
    if let number = slice as? NSNumber { return Copy.jsonMessageSliceNumber(number: number.stringValue, bundle: bundle, locale: locale) }
    return nil
}

/// "PR #289" for a pull request's address, "Pull request" for any other.
private func pullLabel(_ url: URL, bundle: Bundle?, locale: Locale) -> String {
    if url.pathComponents.dropLast().last == "pull" {
        return Copy.jsonMessagePullRequestNumber(number: url.lastPathComponent, bundle: bundle, locale: locale)
    }
    return Copy.jsonMessagePullRequest(bundle: bundle, locale: locale)
}

/// "ready-to-merge", "definitionOfDone" or "pr_url" as "Ready to merge", "Definition of done", "Pr url".
private func sentence(_ key: String) -> String {
    let words = key.replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
        .replacingOccurrences(of: "[-_]", with: " ", options: .regularExpression).lowercased()
    return words.prefix(1).uppercased() + words.dropFirst()
}
