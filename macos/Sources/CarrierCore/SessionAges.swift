import Foundation

// The Sessions section of Settings that needs no view: the two ages of the session lifecycle (docs/specs/session-lifecycle.md), read from and
// written to the chat's own `chat.json` (ADR 0016, ADR 0019). The host reads the file each pass, so a save is used with no restart.

/// An age of the session clock: a whole number of days, or `never` (that part of the clock is off).
public enum SessionAge: Equatable {
    case days(Int)
    case never
}

/// `archiveAfterDays` and `deleteAfterDays` of `chat.json`.
public struct SessionAges: Equatable {
    public var archive: SessionAge
    public var delete: SessionAge
    public init(archive: SessionAge = .days(defaultArchiveAfterDays), delete: SessionAge = .days(defaultDeleteAfterDays)) {
        self.archive = archive
        self.delete = delete
    }
}

/// The host's defaults (src/chat/config.ts); a value equal to its default is left out of the file.
public let defaultArchiveAfterDays = 15
public let defaultDeleteAfterDays = 30

public enum SessionAgeField { case archive, delete }

private let archiveKey = "archiveAfterDays"
private let deleteKey = "deleteAfterDays"

/// The ages `chat.json` holds; a key that is missing or that the host would refuse reads as its default. nil `chatJSON` is no file yet.
public func sessionAges(chatJSON: Data?) -> SessionAges {
    let object = chatJSON.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
    func age(_ key: String, _ fallback: Int) -> SessionAge {
        if object?[key] as? String == "never" { return .never }
        if let days = object?[key] as? Int, days > 0 { return .days(days) }
        return .days(fallback)
    }
    return SessionAges(archive: age(archiveKey, defaultArchiveAfterDays), delete: age(deleteKey, defaultDeleteAfterDays))
}

/// What the fields say is wrong, in words, by field: a number under one day, and (on delete) a delete age that is not greater than the
/// archive age. The host's own rule: with `never` on either side there is no comparison.
public func sessionAgeProblems(_ ages: SessionAges, unparsable: Set<SessionAgeField> = []) -> [SessionAgeField: String] {
    var problems: [SessionAgeField: String] = [:]
    for (field, age) in [(SessionAgeField.archive, ages.archive), (.delete, ages.delete)] {
        if case .days(let days) = age, days < 1 { problems[field] = "Use a whole number of days, 1 or more" }
    }
    if case .days(let archive) = ages.archive, case .days(let delete) = ages.delete, problems[.delete] == nil, delete <= archive {
        problems[.delete] = "Must be greater than the archive age (\(archive) days)"
    }
    // a field whose text is not a number is refused, except the delete one while it is off: it is not saved then, so it cannot block the other
    for field in unparsable where !(field == .delete && deleteAgeOffReason(ages) != nil) { problems[field] = "Must be a number" }
    return problems
}

/// Why the delete field is off, in words; nil when it is on. Archive at `never` means nothing is deleted by the clock, whatever delete says.
public func deleteAgeOffReason(_ ages: SessionAges) -> String? {
    ages.archive == .never ? "Off while archive is Never: nothing is deleted by the clock" : nil
}

/// `json` with the two ages set; the file's other keys are left as they were, and an age equal to its default is left out. `json` nil is a
/// `chat.json` that is not there yet, which this makes. nil when `json` is not a JSON object (the app never overwrites a file it cannot
/// read) or when the ages break a rule (`sessionAgeProblems`): a value the host would refuse is never written.
public func applyingSessionAges(_ ages: SessionAges, to json: Data?) -> Data? {
    guard sessionAgeProblems(ages).isEmpty else { return nil }
    var file: [String: Any] = [:]
    if let json {
        guard let object = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else { return nil }
        file = object
    }
    func set(_ key: String, _ age: SessionAge, default fallback: Int) {
        switch age {
        case .never: file[key] = "never"
        case .days(let days): file[key] = days == fallback ? nil : days
        }
    }
    set(archiveKey, ages.archive, default: defaultArchiveAfterDays)
    set(deleteKey, ages.delete, default: defaultDeleteAfterDays)
    return try? JSONSerialization.data(withJSONObject: file, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
}
