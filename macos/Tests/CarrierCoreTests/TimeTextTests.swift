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
    timeText(date, now: now, style: style, hours: hours, locale: locale, timeZone: utc)
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
    #expect(timeText(today, now: now, style: .clock, hours: .h24, locale: en, timeZone: tokyo) == "Yesterday 23:32")
}

@Test func aClockRangeHasOnlyTheTimeOfDay() {
    #expect(clockTime(yesterday, hours: .h24, locale: en, timeZone: utc) == "14:32")
    #expect(clockTime(yesterday, hours: .h12, locale: en, timeZone: utc) == "2:32 PM")
}

@Test func anAgoLineKeepsItsFormInRelativeAndBecomesTheTimeInClock() {
    let ms = { (date: Date) in Int(date.timeIntervalSince1970 * 1000) }
    let relative = TimeFormat(style: .relative, hours: .h24, locale: en, timeZone: utc)
    let clock = TimeFormat(style: .clock, hours: .h24, locale: en, timeZone: utc)
    #expect(agoText(ms(today), now: ms(now), format: relative) == "1h 28m ago")
    #expect(agoText(ms(today), now: ms(now), format: clock) == "14:32")
    #expect(agoText(ms(yesterday), now: ms(now), format: clock) == "Yesterday 14:32")
}

@Test func theSpokenAgeIsInWordsWhateverTheFormat() {
    #expect(spokenAge(now.addingTimeInterval(-300), now: now) == "5 minutes ago")
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
    #expect(updateCheckedText(nil, now: now, format: format) == "Never")
    #expect(updateCheckedText(today, now: now, format: format) == "14:32")
    #expect(updateCheckedText(yesterday, now: now, format: format) == "Yesterday 14:32")
}
