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
