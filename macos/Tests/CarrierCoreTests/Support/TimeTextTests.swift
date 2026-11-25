import Foundation
import Testing
@testable import CarrierCore

// 2027-01-15 16:00 UTC; the event is 14:32 that day, the day before, or five days before.
private let now = Date(timeIntervalSince1970: 1_800_028_800)
private let utc = TimeZone(identifier: "UTC")!
private let en = Locale(identifier: "en_US")
private let today = now.addingTimeInterval(-(88 * 60))
private let yesterday = today.addingTimeInterval(-86_400)
private let older = today.addingTimeInterval(-5 * 86_400)

private func text(_ date: Date, _ style: TimeStyle, _ hours: ClockHours = .h24, locale: Locale = en) -> String {
    timeText(date, now: now, style: style, hours: hours, locale: locale, timeZone: utc, bundle: english.bundle)
}

@Test func relativeIsWhatTheAppShowedBefore() {
    #expect(text(now.addingTimeInterval(-5), .relative) == "now")
    #expect(text(now.addingTimeInterval(-300), .relative) == "5m")
    #expect(text(now.addingTimeInterval(-3 * 3600), .relative) == "3h")
    #expect(text(now.addingTimeInterval(-2 * 86400), .relative) == "2d")
    #expect(text(now.addingTimeInterval(60), .relative) == "now")
    // the hours do not matter to an age
    #expect(text(now.addingTimeInterval(-300), .relative, .h12) == "5m")
}

@Test func clockIsTheTimeOfTheEventAndYesterdayAndOlderSayTheirDay() {
    #expect(text(today, .clock, .h24) == "14:32")
    #expect(text(yesterday, .clock, .h24) == "Yesterday 14:32")
    #expect(text(older, .clock, .h24) == "Jan 10 14:32")
}

@Test func twelveHoursWritesAmAndPm() {
    #expect(text(today, .clock, .h12) == "2:32 PM")
    #expect(text(yesterday, .clock, .h12) == "Yesterday 2:32 PM")
    #expect(text(older, .clock, .h12) == "Jan 10 2:32 PM")
    #expect(text(today.addingTimeInterval(-14 * 3600), .clock, .h12) == "12:32 AM")
}

@Test func systemFollowsTheLocale() {
    // a locale of 12 hours writes AM and PM (with a narrow space that the system picks), one of 24 hours does not
    let american = text(today, .clock, .system, locale: en)
    #expect(american.hasPrefix("2:32") && american.hasSuffix("PM"))
    #expect(text(today, .clock, .system, locale: Locale(identifier: "de_DE")) == "14:32")
    #expect(text(yesterday, .clock, .system, locale: Locale(identifier: "en_GB")) == "Yesterday 14:32")
}

@Test func theDayChangesWithTheTimeZoneOfTheReader() {
    let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    // 14:32 UTC is 23:32 on the 15th in Tokyo, where 16:00 UTC is already 01:00 on the 16th
    #expect(timeText(today, now: now, style: .clock, hours: .h24, locale: en, timeZone: tokyo, bundle: english.bundle) == "Yesterday 23:32")
}

@Test func aClockRangeHasOnlyTheTimeOfDay() {
    #expect(clockTime(yesterday, hours: .h24, locale: en, timeZone: utc) == "14:32")
    #expect(clockTime(yesterday, hours: .h12, locale: en, timeZone: utc) == "2:32 PM")
}

@Test func anAgoLineKeepsItsFormInRelativeAndBecomesTheTimeInClock() {
    let ms = { (date: Date) in Int(date.timeIntervalSince1970 * 1000) }
    let relative = TimeFormat(style: .relative, hours: .h24, locale: en, timeZone: utc)
    let clock = TimeFormat(style: .clock, hours: .h24, locale: en, timeZone: utc)
    #expect(agoText(ms(today), now: ms(now), format: relative, bundle: english.bundle) == "1h 28m ago")
    #expect(agoText(ms(today), now: ms(now), format: clock, bundle: english.bundle) == "14:32")
    #expect(agoText(ms(yesterday), now: ms(now), format: clock, bundle: english.bundle) == "Yesterday 14:32")
}

@Test func theSpokenAgeIsInWordsWhateverTheFormat() {
    #expect(spokenAge(now.addingTimeInterval(-300), now: now, locale: en) == "5 minutes ago")
}

@Test func theFormatReadsTheSavedPreferencesAndDefaultsToRelativeOnTheSystemClock() {
    let name = "time-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    #expect(TimeFormat.stored(in: defaults).style == .relative && TimeFormat.stored(in: defaults).hours == .system)
    let store = AppPreferences(defaults: defaults)
    store.timeStyle = .clock
    store.clockHours = .h12
    let relaunched = TimeFormat.stored(in: UserDefaults(suiteName: name)!)
    #expect(relaunched.style == .clock && relaunched.hours == .h12)
}

@Test func theLastUpdateCheckReadsNeverUntilTheUpdaterHasChecked() {
    let format = TimeFormat(style: .relative, hours: .h24, locale: en, timeZone: utc)
    #expect(updateCheckedText(nil, now: now, format: format, bundle: english.bundle) == "Never")
    #expect(updateCheckedText(today, now: now, format: format, bundle: english.bundle) == "14:32")
    #expect(updateCheckedText(yesterday, now: now, format: format, bundle: english.bundle) == "Yesterday 14:32")
}

@Test func aClockTimeKeepsItsFormatWhateverWasAskedBetween() {
    let buenosAires = TimeZone(identifier: "America/Argentina/Buenos_Aires")!
    let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    // the formatters are kept per clock, locale and zone: asking for another one in between never changes the next answer
    for _ in 0..<2 {
        #expect(text(today, .clock, .h24) == "14:32")
        #expect(text(today, .clock, .h12) == "2:32 PM")
        #expect(text(today, .clock, .h24) == "14:32")
        #expect(timeText(today, now: now, style: .clock, hours: .h24, locale: en, timeZone: buenosAires, bundle: english.bundle) == "11:32")
        #expect(timeText(older, now: now, style: .clock, hours: .h24, locale: en, timeZone: buenosAires, bundle: english.bundle) == "Jan 10 11:32")
        #expect(timeText(today, now: now, style: .clock, hours: .h24, locale: en, timeZone: tokyo, bundle: english.bundle) == "Yesterday 23:32")
        #expect(text(older, .clock, .h24) == "Jan 10 14:32")
        #expect(text(today, .clock, .system, locale: Locale(identifier: "de_DE")) == "14:32")
        let american = text(today, .clock, .system, locale: en)
        #expect(american.hasPrefix("2:32") && american.hasSuffix("PM"))
    }
}

private func read(_ date: Date, _ style: TimeStyle, _ hours: ClockHours, in language: (bundle: Bundle, locale: Locale)) -> String {
    timeText(date, now: now, style: style, hours: hours, locale: language.locale, timeZone: utc, bundle: language.bundle)
}

@Test func theSameInstantReadsInEnglishAndInSpanish() {
    let ages: [(Double, String, String)] = [(-5, "now", "ahora"), (-300, "5m", "5 min"), (-3 * 3600, "3h", "3 h"), (-2 * 86400, "2d", "2 d")]
    for (seconds, inEnglish, inSpanish) in ages {
        let date = now.addingTimeInterval(seconds)
        #expect(read(date, .relative, .system, in: english) == inEnglish)
        #expect(read(date, .relative, .system, in: spanish) == inSpanish)
    }
    #expect(read(today, .clock, .h24, in: english) == "14:32" && read(today, .clock, .h24, in: spanish) == "14:32")
    #expect(read(yesterday, .clock, .h24, in: english) == "Yesterday 14:32")
    #expect(read(yesterday, .clock, .h24, in: spanish) == "Ayer 14:32")
    #expect(read(older, .clock, .h24, in: english) == "Jan 10 14:32")
    #expect(read(older, .clock, .h24, in: spanish) == "10 ene 14:32")
}

@Test func twelveHoursWritesTheMarksOfTheLanguage() {
    #expect(read(today, .clock, .h12, in: english) == "2:32 PM")
    // the space inside "p. m." is a no-break one that the system picks, so the marks are checked around it
    let afternoon = read(today, .clock, .h12, in: spanish)
    #expect(afternoon.hasPrefix("2:32") && afternoon.contains("p.") && afternoon.hasSuffix("m.") && !afternoon.contains("PM"))
    #expect(read(yesterday, .clock, .h12, in: spanish) == "Ayer " + afternoon)
}

@Test func theAgoLineTheSpokenAgeAndTheLastCheckAreInTheLanguage() {
    let ms = { (date: Date) in Int(date.timeIntervalSince1970 * 1000) }
    let relative = TimeFormat(style: .relative, hours: .h24, locale: spanish.locale, timeZone: utc)
    #expect(agoText(ms(today), now: ms(now), format: relative, bundle: spanish.bundle) == "hace 1h 28m")
    #expect(spokenAge(now.addingTimeInterval(-300), now: now, locale: spanish.locale) == "hace 5 minutos")
    #expect(updateCheckedText(nil, now: now, format: relative, bundle: spanish.bundle) == "Nunca")
    #expect(updateCheckedText(yesterday, now: now, format: relative, bundle: spanish.bundle) == "Ayer 14:32")
}
