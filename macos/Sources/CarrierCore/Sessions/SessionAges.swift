import Foundation

// The Sessions section of Settings that needs no view: the two ages of the session lifecycle (docs/specs/session-lifecycle.md), read from and
// changed through `editChatSettings` (ConfigRequests.swift), which Node writes into the chat's own `chat.json` (ADR 0034, ADR 0019, ADR 0053). The host reads the file each pass, so a save is used with no restart.

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
public func sessionAgeProblems(_ ages: SessionAges, unparsable: Set<SessionAgeField> = [], bundle: Bundle? = nil, locale: Locale = .current) -> [SessionAgeField: String] {
    var problems: [SessionAgeField: String] = [:]
    for (field, age) in [(SessionAgeField.archive, ages.archive), (.delete, ages.delete)] {
        if case .days(let days) = age, days < 1 { problems[field] = Copy.sessionAgeWholeNumber(bundle: bundle, locale: locale) }
    }
    if case .days(let archive) = ages.archive, case .days(let delete) = ages.delete, problems[.delete] == nil, delete <= archive {
        problems[.delete] = Copy.sessionAgeGreaterThanArchive(days: archive, bundle: bundle, locale: locale)
    }
    // a field whose text is not a number is refused, except the delete one while it is off: it is not saved then, so it cannot block the other
    for field in unparsable where !(field == .delete && deleteAgeOffReason(ages) != nil) { problems[field] = Copy.sessionAgeMustBeNumber(bundle: bundle, locale: locale) }
    return problems
}

/// Why the delete field is off, in words; nil when it is on. Archive at `never` means nothing is deleted by the clock, whatever delete says.
public func deleteAgeOffReason(_ ages: SessionAges, bundle: Bundle? = nil, locale: Locale = .current) -> String? {
    ages.archive == .never ? Copy.sessionAgeDeleteOff(bundle: bundle, locale: locale) : nil
}

/// The line of the Sessions page about a session left alone from `today`, in dates: both ages count from the same last activity, so both
/// dates are `today` plus each age. The year is written only for a date that is not in `today`'s year. nil while an age is refused (or its
/// field is `unparsable`), since the dates would be a guess.
public func sessionAgesLine(
    _ ages: SessionAges, today: Date, calendar: Calendar = .current, unparsable: Set<SessionAgeField> = [], bundle: Bundle? = nil, locale: Locale = .current
) -> String? {
    guard sessionAgeProblems(ages, unparsable: unparsable, bundle: bundle, locale: locale).isEmpty else { return nil }
    guard case .days(let archive) = ages.archive else { return Copy.sessionAgeNever(bundle: bundle, locale: locale) }
    func date(after days: Int) -> String {
        let day = calendar.date(byAdding: .day, value: days, to: today) ?? today
        let formatter = DateFormatter()
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: today)
        (formatter.locale, formatter.calendar, formatter.timeZone, formatter.dateFormat) = (Locale(identifier: "en_US_POSIX"), calendar, calendar.timeZone, sameYear ? "MMM d" : "MMM d, yyyy")
        return formatter.string(from: day)
    }
    guard case .days(let delete) = ages.delete else { return Copy.sessionAgeArchivedNeverDeleted(archive: date(after: archive), bundle: bundle, locale: locale) }
    return Copy.sessionAgeArchivedAndDeleted(archive: date(after: archive), delete: date(after: delete), bundle: bundle, locale: locale)
}
