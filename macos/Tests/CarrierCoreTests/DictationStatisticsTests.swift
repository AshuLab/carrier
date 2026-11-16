import Foundation
import Testing
@testable import CarrierCore

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.locale = Locale(identifier: "en_US")
    return calendar
}

/// 2023-11-14 12:00 UTC.
private let now = Date(timeIntervalSince1970: 1_699_963_200)

private func count(daysAgo: Int, words: Int, dictations: Int = 1, seconds: Double = 10, hour: Int = 9, longest: Double? = nil) -> DictationCount {
    let day = dictationDayKey(now.addingTimeInterval(-Double(daysAgo) * 86400), calendar: utc)
    return DictationCount(day: day, hour: hour, model: "Apple", dictations: dictations, words: words, seconds: seconds, longest: longest ?? seconds)
}

@Test func timeSavedIsTheTypingTimeMinusTheSpeakingTimeAndNeverNegative() {
    #expect(timeSaved(words: 0, speaking: .seconds(30), wpm: 40) == .zero)
    #expect(timeSaved(words: 100, speaking: .seconds(30), wpm: 0) == .zero)
    // 20 words at 40 a minute is 30 s of typing, and 60 s of speaking is longer
    #expect(timeSaved(words: 20, speaking: .seconds(60), wpm: 40) == .zero)
    // 100 words at 40 a minute is 150 s of typing, minus 30 s of speaking
    #expect(timeSaved(words: 100, speaking: .seconds(30), wpm: 40) == .seconds(120))
}

@Test func aRangeTotalsItsDaysAndTheSameNumberOfDaysBeforeIt() {
    let counts = [
        count(daysAgo: 0, words: 10), count(daysAgo: 6, words: 20, dictations: 2), count(daysAgo: 7, words: 100),
        count(daysAgo: 13, words: 50, dictations: 3), count(daysAgo: 14, words: 1000),
    ]
    let week = dictationFigures(counts, range: .week, now: now, calendar: utc)
    #expect(week.current == DictationTotals(dictations: 3, words: 30, seconds: 20))
    #expect(week.previous == DictationTotals(dictations: 4, words: 150, seconds: 20))
    #expect(week.days.count == 7 && week.days.last?.words == 10 && week.days.first?.words == 20 && week.days[1].dictations == 0)
    let month = dictationFigures(counts, range: .month, now: now, calendar: utc)
    #expect(month.current.words == 1180 && month.previous == DictationTotals())
    #expect(month.days.count == 30)
}

@Test func allTimeRunsFromTheFirstDayAndHasNothingBeforeIt() {
    let counts = [count(daysAgo: 3, words: 5), count(daysAgo: 1, words: 7)]
    let all = dictationFigures(counts, range: .all, now: now, calendar: utc)
    #expect(all.previous == nil && all.current.words == 12 && all.days.count == 4)
    #expect(dictationFigures([], range: .all, now: now, calendar: utc).days.count == 1)
}

@Test func theChangeIsAPercentAgainstThePreviousPeriodAndNothingWithoutOne() {
    #expect(statisticsChange(150, from: 100) == "▲ 50% vs previous")
    #expect(statisticsChange(50, from: 100) == "▼ 50% vs previous")
    #expect(statisticsChange(100, from: 100) == "No change vs previous")
    #expect(statisticsChange(10, from: 0) == nil && statisticsChange(10, from: nil) == nil)
}

@Test func aLengthOfTimeIsReadInSecondsMinutesOrHours() {
    #expect(statisticsDuration(0) == "0 s" && statisticsDuration(42) == "42 s")
    #expect(statisticsDuration(720) == "12 min" && statisticsDuration(3900) == "1 h 05 min")
}

@Test func theBusiestHourIsTheOneWithMostDictationsInTheRangeAndTheEarliestOnATie() {
    let counts = [
        count(daysAgo: 0, words: 5, dictations: 2, hour: 15), count(daysAgo: 1, words: 5, dictations: 2, hour: 8), count(daysAgo: 2, words: 5, dictations: 1, hour: 15),
        count(daysAgo: 20, words: 5, dictations: 9, hour: 22),
    ]
    let week = dictationHours(counts, range: .week, now: now, calendar: utc)
    #expect(week.dictations.count == 24 && week.dictations[15] == 3 && week.dictations[8] == 2 && week.busiest == 15)
    #expect(statisticsHoursLine(week) == "You dictate most around 15:00.")
    #expect(dictationHours(counts, range: .month, now: now, calendar: utc).busiest == 22)
    let tie = dictationHours([count(daysAgo: 0, words: 1, hour: 18), count(daysAgo: 0, words: 1, hour: 7)], range: .week, now: now, calendar: utc)
    #expect(tie.busiest == 7)
}

@Test func withNoDictationsInTheRangeThereIsNoBusiestHour() {
    let empty = dictationHours([], range: .all, now: now, calendar: utc)
    #expect(empty.busiest == nil && empty.dictations == Array(repeating: 0, count: 24))
    #expect(statisticsHoursLine(empty) == "Nothing dictated in this range yet.")
    #expect(dictationHours([count(daysAgo: 10, words: 1)], range: .week, now: now, calendar: utc).busiest == nil)
}

@Test func theWeekIsComparedWithTheOneBeforeInWordsDictationsPercentBusiestDayAndTimeSaved() {
    // today is a Tuesday; 100 words in 4 dictations on Sunday is the busiest day of the week, against 100 words the week before
    let counts = [
        count(daysAgo: 0, words: 50, dictations: 2, seconds: 30), count(daysAgo: 2, words: 150, dictations: 6, seconds: 90),
        count(daysAgo: 8, words: 100, dictations: 5, seconds: 60),
    ]
    let week = dictationFigures(counts, range: .week, now: now, calendar: utc)
    #expect(busiestDay(week.days)?.words == 150 && busiestDay(week.days).map { utc.component(.weekday, from: $0.day) } == 1)
    // 200 words at 40 a minute is 300 s of typing, minus 120 s of speaking
    #expect(weeklySummary(week, wpm: 40, calendar: utc) == "You dictated 200 words in 8 dictations, 100% more than the 7 days before. Sunday was your busiest day, and you saved about 3 min.")
    #expect(weeklySummary(dictationFigures([count(daysAgo: 0, words: 50, dictations: 1), count(daysAgo: 8, words: 100)], range: .week, now: now, calendar: utc), wpm: 40, calendar: utc)
        .contains("50% less than the 7 days before"))
    #expect(weeklySummary(dictationFigures([count(daysAgo: 0, words: 100), count(daysAgo: 8, words: 100)], range: .week, now: now, calendar: utc), wpm: 40, calendar: utc)
        .contains("the same as the 7 days before"))
}

@Test func aPreviousWeekAtZeroOrAWeekWithNothingSaysWhatItCanWithoutDividingByZero() {
    // 1 word is typed faster than the 5 s it took to say, so nothing was saved and the sentence leaves it out
    let first = weeklySummary(dictationFigures([count(daysAgo: 0, words: 1, dictations: 1, seconds: 5)], range: .week, now: now, calendar: utc), wpm: 40, calendar: utc)
    #expect(first == "You dictated 1 word in 1 dictation, with nothing the 7 days before to compare with. Tuesday was your busiest day.")
    #expect(weeklySummary(dictationFigures([count(daysAgo: 9, words: 40, dictations: 3)], range: .week, now: now, calendar: utc), wpm: 40, calendar: utc)
        == "No dictations in the last 7 days, against 3 dictations in the 7 before.")
    let empty = dictationFigures([], range: .week, now: now, calendar: utc)
    #expect(weeklySummary(empty, wpm: 40, calendar: utc) == "No dictations in the last 7 days." && busiestDay(empty.days) == nil)
    #expect(weeklySummary(empty, wpm: 0, calendar: utc) == "No dictations in the last 7 days.")
}

@Test func theBusiestDayOfAWeekWithTwoEqualDaysIsTheEarlierOne() {
    let week = dictationFigures([count(daysAgo: 1, words: 20), count(daysAgo: 4, words: 20)], range: .week, now: now, calendar: utc)
    #expect(busiestDay(week.days)?.day == utc.startOfDay(for: now.addingTimeInterval(-4 * 86400)))
}

@Test func theRecordsKeepTheEarliestDayOnATieAndTheLongestDictationOfAnyHour() {
    let counts = [
        count(daysAgo: 5, words: 100, dictations: 3, seconds: 30, longest: 12), count(daysAgo: 5, words: 20, dictations: 1, seconds: 5, hour: 14, longest: 45),
        count(daysAgo: 2, words: 120, dictations: 4, seconds: 30, longest: 45), count(daysAgo: 0, words: 120, dictations: 4, seconds: 30),
    ]
    let records = statisticsRecords(counts, calendar: utc)
    let day = { (ago: Int) in utc.startOfDay(for: now.addingTimeInterval(-Double(ago) * 86400)) }
    #expect(records.mostDictations == StatisticsRecord(value: 4, day: day(5)))
    #expect(records.mostWords == StatisticsRecord(value: 120, day: day(5)))
    #expect(records.longest == StatisticsRecord(value: 45, day: day(5)))
}

@Test func theStreakIsTheLongestRunOfDaysInARowAndAGapEndsIt() {
    let counts = [0, 1, 2, 4, 5, 6, 7, 9].map { count(daysAgo: $0, words: 1) }
    #expect(statisticsRecords(counts, calendar: utc).streak == 4)
    #expect(statisticsRecords([count(daysAgo: 3, words: 1), count(daysAgo: 3, words: 1, hour: 10)], calendar: utc).streak == 1)
    #expect(statisticsRecords([count(daysAgo: 0, words: 1), count(daysAgo: 2, words: 1)], calendar: utc).streak == 1)
}

@Test func withNoCountersThereAreNoRecordsAndNoStreak() {
    #expect(statisticsRecords([], calendar: utc) == StatisticsRecords())
    #expect(statisticsRecords([], calendar: utc).streak == 0)
}

@MainActor @Test func theTypingSpeedStartsAtFortyStaysWithinTenAndTwoHundredAndResetsWithDictation() {
    let name = "typing-speed-\(UUID().uuidString)"
    let store = AppPreferences(defaults: UserDefaults(suiteName: name)!)
    #expect(store.dictationTypingSpeed == 40 && AppPreferences.dictationTypingSpeedKey == "dictation.statistics.wpm")
    store.dictationTypingSpeed = 65
    #expect(AppPreferences(defaults: UserDefaults(suiteName: name)!).dictationTypingSpeed == 65)
    store.dictationTypingSpeed = 5
    #expect(store.dictationTypingSpeed == 10)
    store.dictationTypingSpeed = 500
    #expect(store.dictationTypingSpeed == 200)
    store.reset(.dictation)
    #expect(store.dictationTypingSpeed == 40)
}
