import Foundation

// The statistics of dictation (docs/adr/0031-dictation-keeps-a-history-and-its-statistics-live-apart-from-it.md): counters per day and hour, with no text,
// kept by `DictationRecords` apart from the history, and the figures of the Statistics segment as pure functions of them.

/// What was dictated in one hour of one day with one speech model, as `DictationRecords` counts it when a dictation ends pasted or copied.
public struct DictationCount: Codable, Equatable, Sendable {
    /// The day in the person's calendar, "2026-11-16".
    public let day: String
    public let hour: Int
    public let model: String
    public var dictations: Int
    public var words: Int
    /// Seconds dictated, that is, of audio.
    public var seconds: Double
    /// The longest dictation of the hour, in seconds.
    public var longest: Double
}

/// "2026-11-16", the day of `date` in `calendar`: counters are keyed by it so that a change of time zone never moves a day.
public func dictationDayKey(_ date: Date, calendar: Calendar = .current) -> String {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
}

private func dictationDay(_ key: String, calendar: Calendar) -> Date? {
    let parts = key.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
}

/// The time saved by dictating `words` over typing them at `wpm` words a minute, minus the time spent speaking; never negative, and zero when there
/// is nothing to compare.
public func timeSaved(words: Int, speaking: Duration, wpm: Int) -> Duration {
    guard words > 0, wpm > 0 else { return .zero }
    return max(.zero, .seconds(Double(words) / Double(wpm) * 60) - speaking)
}

/// The range of the Statistics segment: the last days up to today, or everything.
public enum StatisticsRange: CaseIterable, Sendable {
    case week, month, quarter, all

    public var title: String {
        switch self {
        case .week: "7 days"
        case .month: "30 days"
        case .quarter: "90 days"
        case .all: "All time"
        }
    }

    /// How many days it covers, today included; nil for all time.
    public var days: Int? {
        switch self {
        case .week: 7
        case .month: 30
        case .quarter: 90
        case .all: nil
        }
    }
}

public struct DictationTotals: Equatable, Sendable {
    public var dictations = 0
    public var words = 0
    public var seconds = 0.0

    public init(dictations: Int = 0, words: Int = 0, seconds: Double = 0) {
        self.dictations = dictations
        self.words = words
        self.seconds = seconds
    }

    /// The time saved by these dictations at `wpm` words a minute.
    public func saved(wpm: Int) -> Duration { timeSaved(words: words, speaking: .seconds(seconds), wpm: wpm) }
}

/// One day of the chart, with its words and dictations (zero for a day with none).
public struct StatisticsDay: Equatable, Identifiable, Sendable {
    public let day: Date
    public let words: Int
    public let dictations: Int
    public var id: Date { day }
}

public struct DictationFigures: Equatable, Sendable {
    public let current: DictationTotals
    /// The same number of days just before the range; nil for all time, which has nothing before it.
    public let previous: DictationTotals?
    /// Every day of the range, oldest first, up to `now`'s.
    public let days: [StatisticsDay]
}

/// The figures of `range` as of `now`: its totals, those of the period before it and a day each for the chart.
public func dictationFigures(_ counts: [DictationCount], range: StatisticsRange, now: Date, calendar: Calendar = .current) -> DictationFigures {
    let today = calendar.startOfDay(for: now)
    let first: Date
    if let days = range.days {
        first = calendar.date(byAdding: .day, value: 1 - days, to: today) ?? today
    } else {
        first = counts.compactMap { dictationDay($0.day, calendar: calendar) }.min() ?? today
    }
    var perDay: [String: DictationTotals] = [:]
    for count in counts {
        perDay[count.day, default: DictationTotals()].add(DictationTotals(dictations: count.dictations, words: count.words, seconds: count.seconds))
    }
    var days: [StatisticsDay] = []
    var current = DictationTotals()
    var date = first
    while date <= today {
        let totals = perDay[dictationDayKey(date, calendar: calendar)] ?? DictationTotals()
        days.append(StatisticsDay(day: date, words: totals.words, dictations: totals.dictations))
        current.add(totals)
        guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
        date = next
    }
    var previous: DictationTotals?
    if let length = range.days, let start = calendar.date(byAdding: .day, value: -length, to: first) {
        var totals = DictationTotals()
        for offset in 0..<length {
            if let day = calendar.date(byAdding: .day, value: offset, to: start) { totals.add(perDay[dictationDayKey(day, calendar: calendar)] ?? DictationTotals()) }
        }
        previous = totals
    }
    return DictationFigures(current: current, previous: previous, days: days)
}

extension DictationTotals {
    fileprivate mutating func add(_ other: DictationTotals) {
        dictations += other.dictations
        words += other.words
        seconds += other.seconds
    }
}

/// The change from `previous` to `current` as a line under a card ("▲ 12% vs previous"); nil when there is nothing before it to compare with.
public func statisticsChange(_ current: Double, from previous: Double?) -> String? {
    guard let previous, previous > 0 else { return nil }
    let percent = Int(((current - previous) / previous * 100).rounded())
    return percent == 0 ? "No change vs previous" : "\(percent > 0 ? "▲" : "▼") \(abs(percent))% vs previous"
}

/// A length of time as a card shows it: "42 s", "12 min", "1 h 05 min".
public func statisticsDuration(_ seconds: Double) -> String {
    let total = Int(seconds.rounded())
    if total < 60 { return "\(total) s" }
    let minutes = total / 60
    return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h " + String(format: "%02d", minutes % 60) + " min"
}

extension Duration {
    /// This length as seconds, for `statisticsDuration`.
    public var inSeconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}

/// How many dictations fell in each hour of the day over a range, and the hour with the most.
public struct DictationHours: Equatable, Sendable {
    /// The dictations of hours 0 to 23.
    public let dictations: [Int]

    /// The hour with the most dictations, the earliest on a tie; nil when there are none.
    public var busiest: Int? {
        guard let most = dictations.max(), most > 0 else { return nil }
        return dictations.firstIndex(of: most)
    }
}

/// The hours of the day of `range` as of `now`: the dictations of its days, summed by the hour they began in.
public func dictationHours(_ counts: [DictationCount], range: StatisticsRange, now: Date, calendar: Calendar = .current) -> DictationHours {
    let today = dictationDayKey(now, calendar: calendar)
    var first = ""  // day keys sort as dates do, and "" is before all of them
    if let days = range.days, let start = calendar.date(byAdding: .day, value: 1 - days, to: calendar.startOfDay(for: now)) {
        first = dictationDayKey(start, calendar: calendar)
    }
    var hours = Array(repeating: 0, count: 24)
    for count in counts where count.day >= first && count.day <= today && hours.indices.contains(count.hour) {
        hours[count.hour] += count.dictations
    }
    return DictationHours(dictations: hours)
}

/// The line under the hours: "You dictate most around 09:00."
public func statisticsHoursLine(_ hours: DictationHours) -> String {
    guard let hour = hours.busiest else { return "Nothing dictated in this range yet." }
    return "You dictate most around " + String(format: "%02d:00", hour) + "."
}

/// The busiest day of `days` by words, the earliest on a tie; nil when none has any.
public func busiestDay(_ days: [StatisticsDay]) -> StatisticsDay? {
    days.max { $0.words < $1.words }.flatMap { $0.words > 0 ? $0 : nil }
}

/// The last 7 days against the 7 before as a sentence, from the figures of `.week`. It says what it can: with nothing in the week there is no busiest
/// day, and with nothing the week before there is no percent to give.
public func weeklySummary(_ week: DictationFigures, wpm: Int, calendar: Calendar = .current) -> String {
    let now = week.current
    let before = week.previous ?? DictationTotals()
    guard now.dictations > 0 else {
        let earlier = before.dictations > 0 ? ", against \(counted(before.dictations, "dictation")) in the 7 before" : ""
        return "No dictations in the last 7 days" + earlier + "."
    }
    var sentence = "You dictated \(counted(now.words, "word")) in \(counted(now.dictations, "dictation"))"
    if before.words > 0 {
        let percent = Int(((Double(now.words) - Double(before.words)) / Double(before.words) * 100).rounded())
        sentence += percent == 0 ? ", the same as the 7 days before" : ", \(abs(percent))% \(percent > 0 ? "more" : "less") than the 7 days before"
    } else {
        sentence += ", with nothing the 7 days before to compare with"
    }
    sentence += "."
    if let day = busiestDay(week.days) {
        sentence += " \(calendar.weekdaySymbols[calendar.component(.weekday, from: day.day) - 1]) was your busiest day"
        let saved = now.saved(wpm: wpm).inSeconds
        sentence += saved > 0 ? ", and you saved about \(statisticsDuration(saved))." : "."
    }
    return sentence
}

private func counted(_ number: Int, _ noun: String) -> String { "\(number.formatted()) \(noun)\(number == 1 ? "" : "s")" }

/// A best of all the counters: its figure and the day it was first reached.
public struct StatisticsRecord<Value: Equatable & Sendable>: Equatable, Sendable {
    public let value: Value
    public let day: Date
}

/// The records of the person's whole history of counters; a record is nil until something is dictated.
public struct StatisticsRecords: Equatable, Sendable {
    public var mostDictations: StatisticsRecord<Int>?
    public var mostWords: StatisticsRecord<Int>?
    /// The longest dictation, in seconds.
    public var longest: StatisticsRecord<Double>?
    /// The most days in a row with a dictation.
    public var streak = 0
}

/// The records of `counts`. On a tie the record stays with the earliest day, which is when it was reached; a gap of a day ends a streak.
public func statisticsRecords(_ counts: [DictationCount], calendar: Calendar = .current) -> StatisticsRecords {
    var perDay: [String: (dictations: Int, words: Int, longest: Double)] = [:]
    for count in counts {
        var day = perDay[count.day] ?? (0, 0, 0)
        day.dictations += count.dictations
        day.words += count.words
        day.longest = max(day.longest, count.longest)
        perDay[count.day] = day
    }
    var records = StatisticsRecords()
    var run = 0
    var previous: Date?
    for key in perDay.keys.sorted() {
        guard let figures = perDay[key], figures.dictations > 0, let date = dictationDay(key, calendar: calendar) else { continue }
        if figures.dictations > records.mostDictations?.value ?? 0 { records.mostDictations = StatisticsRecord(value: figures.dictations, day: date) }
        if figures.words > records.mostWords?.value ?? 0 { records.mostWords = StatisticsRecord(value: figures.words, day: date) }
        if figures.longest > records.longest?.value ?? 0 { records.longest = StatisticsRecord(value: figures.longest, day: date) }
        let next = previous.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) }
        run = next.map { calendar.isDate($0, inSameDayAs: date) } == true ? run + 1 : 1
        records.streak = max(records.streak, run)
        previous = date
    }
    return records
}
