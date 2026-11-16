import Foundation
import Testing
@testable import CarrierCore

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

/// 2023-11-14 12:00 UTC.
private let now = Date(timeIntervalSince1970: 1_699_963_200)

private func count(daysAgo: Int, words: Int, dictations: Int = 1, seconds: Double = 10) -> DictationCount {
    let day = dictationDayKey(now.addingTimeInterval(-Double(daysAgo) * 86400), calendar: utc)
    return DictationCount(day: day, hour: 9, model: "Apple", dictations: dictations, words: words, seconds: seconds, longest: seconds)
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
