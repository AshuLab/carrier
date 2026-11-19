import Charts
import CarrierCore
import SwiftUI

/// The Statistics screen of the Dictation page, a group for each thing it shows: the range and four figures, a chart by day, the hours of the day, the week
/// against the one before, the records, and the settings (typing speed, Reset statistics).
struct StatisticsGroup: View {
    var dictation = DictationController.shared
    @AppStorage(AppPreferences.dictationTypingSpeedKey) private var wpm = AppPreferences.defaultDictationTypingSpeed
    @State private var range = StatisticsRange.month
    @State private var metric = StatisticsMetric.words
    @State private var confirmingReset = false
    @State private var unparsable: Set<String> = []
    @State private var cardsWidth = CGFloat.infinity

    var body: some View {
        let records = dictation.records
        Group {
            if records.counts.isEmpty {
                SettingsGroup(title: "") {
                    EmptyStateView(
                        icon: .chartBar, title: "No statistics yet",
                        line: "Dictate with the microphone or the shortcut and finish with the text pasted or copied: the numbers start here."
                    )
                    .frame(minHeight: 220)
                }
            } else {
                let speed = min(max(wpm, AppPreferences.dictationTypingSpeedRange.lowerBound), AppPreferences.dictationTypingSpeedRange.upperBound)
                let figures = dictationFigures(records.counts, range: range, now: Date())
                SettingsGroup(title: "Overview", accessory: {
                    SegmentedChoice(options: StatisticsRange.allCases.map { (value: $0, title: $0.title, icon: nil) }, selection: $range)
                }, content: { cards(figures, wpm: speed) })
                SettingsGroup(title: "\(metric.title) per day", accessory: {
                    SegmentedChoice(options: StatisticsMetric.allCases.map { (value: $0, title: $0.title, icon: nil) }, selection: $metric)
                }, content: { StatisticsChart(days: figures.days, metric: metric).padding(.vertical, 8) })
                SettingsGroup(title: "By hour of the day") { hoursContent(dictationHours(records.counts, range: range, now: Date())) }
                SettingsGroup(title: "This week") { weekContent(dictationFigures(records.counts, range: .week, now: Date()), wpm: speed) }
                recordsGroup(statisticsRecords(records.counts))
            }
            settings
        }
        .alert("Reset statistics?", isPresented: $confirmingReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { records.resetStatistics() }
        } message: {
            Text("It deletes the counters of every day. The history of dictations stays as it is.")
        }
    }

    private func cards(_ figures: DictationFigures, wpm: Int) -> some View {
        let now = figures.current
        let before = figures.previous
        let dictations = StatisticsCard(title: "Dictations", value: now.dictations.formatted(), line: statisticsChange(Double(now.dictations), from: before.map { Double($0.dictations) }))
        let words = StatisticsCard(title: "Words", value: now.words.formatted(), line: statisticsChange(Double(now.words), from: before.map { Double($0.words) }))
        let speaking = StatisticsCard(title: "Speaking time", value: statisticsDuration(now.seconds), line: statisticsChange(now.seconds, from: before?.seconds))
        let saved = StatisticsCard(
            title: "Time saved", value: statisticsDuration(now.saved(wpm: wpm).inSeconds),
            line: statisticsChange(now.saved(wpm: wpm).inSeconds, from: before.map { $0.saved(wpm: wpm).inSeconds }), highlighted: true)
        // four in a row while each has the room its longest title and value need (equal shares, at the person's text size), two by two when the window is narrow
        let four = cardsWidth >= 4 * 130 * CGFloat(TextSize.shared.percent) / 100 + 30
        return Group {
            if four {
                HStack(alignment: .top, spacing: 10) { dictations; words; speaking; saved }
            } else {
                VStack(spacing: 10) {
                    HStack(alignment: .top, spacing: 10) { dictations; words }
                    HStack(alignment: .top, spacing: 10) { speaking; saved }
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { cardsWidth = $0 }
        .padding(.vertical, 6)
    }

    /// 24 cells, one per hour, as strong as the dictations of that hour, and the line that says the hour the person dictates most.
    private func hoursContent(_ hours: DictationHours) -> some View {
        let most = max(hours.dictations.max() ?? 0, 1)
        let line = statisticsHoursLine(hours)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 2) {
                ForEach(0..<24, id: \.self) { hour in
                    RoundedRectangle(cornerRadius: 3).fill(Color.themeAccent.opacity(0.08 + 0.92 * Double(hours.dictations[hour]) / Double(most)))
                        .frame(height: 34).help("\(String(format: "%02d", hour)):00 · \(hours.dictations[hour]) dictations")
                }
            }
            HStack(spacing: 0) {
                ForEach([0, 6, 12, 18], id: \.self) { hour in
                    Text("\(hour)").frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .font(.scaled(10)).foregroundStyle(.secondary)
            Text(line).font(.scaled(11)).foregroundStyle(.secondary).padding(.top, 4)
        }
        .padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore).accessibilityLabel("Dictations by hour of the day").accessibilityValue(line)
    }

    /// The last 7 days against the 7 before, in a sentence and a small chart of the words of each day.
    private func weekContent(_ week: DictationFigures, wpm: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(weeklySummary(week, wpm: wpm)).font(.scaled(12)).fixedSize(horizontal: false, vertical: true)
            WeekChart(days: week.days)
        }
        .padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recordsGroup(_ records: StatisticsRecords) -> some View {
        func on(_ day: Date?) -> String { day?.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) ?? "Nothing yet" }
        return SettingsGroup(title: "Records", footer: "The statistics are their own counters: they hold no text, and turning the history off or deleting entries does not change them.") {
            SettingsTabRow(title: "Most dictations in a day", detail: on(records.mostDictations?.day), first: true) {
                Text((records.mostDictations?.value ?? 0).formatted()).fontWeight(.semibold).monospacedDigit()
            }
            SettingsTabRow(title: "Most words in a day", detail: on(records.mostWords?.day)) {
                Text((records.mostWords?.value ?? 0).formatted()).fontWeight(.semibold).monospacedDigit()
            }
            SettingsTabRow(title: "Longest dictation", detail: on(records.longest?.day)) {
                Text(statisticsDuration(records.longest?.value ?? 0)).fontWeight(.semibold).monospacedDigit()
            }
            SettingsTabRow(title: "Longest streak", detail: "Days in a row with a dictation") {
                Text("\(records.streak) \(records.streak == 1 ? "day" : "days")").fontWeight(.semibold).monospacedDigit()
            }
        }
    }

    private var settings: some View {
        SettingsGroup(title: "Statistics settings") {
            SettingsTabRow(
                title: "Typing speed", detail: "Used for the time saved: words ÷ speed, minus the time you spent speaking", first: true,
                problem: unparsable.isEmpty ? nil : "Must be between \(AppPreferences.dictationTypingSpeedRange.lowerBound) and \(AppPreferences.dictationTypingSpeedRange.upperBound)"
            ) {
                // the counter of Behavior's numbers: a number between the range's ends, − and + by 5; text that is not one keeps the last good value
                HStack(spacing: 6) {
                    NumberField(
                        key: "Typing speed, words per minute", value: $wpm, unparsable: $unparsable,
                        parse: { Int($0).flatMap { AppPreferences.dictationTypingSpeedRange.contains($0) ? $0 : nil } }, format: { String($0) },
                        // a click goes to the end of the range when 5 would pass it, and nowhere when it is already there
                        step: { value, direction in
                            let range = AppPreferences.dictationTypingSpeedRange
                            let next = min(max(value + direction * 5, range.lowerBound), range.upperBound)
                            return next == value ? nil : next
                        })
                    Text("words/min").font(.scaled(11)).foregroundStyle(.secondary)
                }
            }
            SettingsTabRow(title: "Reset statistics", detail: "Deletes the counters. The history stays, and deleting history never changes the statistics") {
                Button(role: .destructive) { confirmingReset = true } label: { Label("Reset statistics…", icon: .trash) }
                    .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
            }
        }
    }
}

enum StatisticsMetric: CaseIterable {
    case words, dictations

    var title: String { self == .words ? "Words" : "Dictations" }
}

private struct StatisticsCard: View {
    let title: String
    let value: String
    let line: String?
    var highlighted = false

    var body: some View {
        let face = VStack(alignment: .leading, spacing: 3) {
            Text(title).sectionLabel().lineLimit(1)
            Text(value).font(.scaled(24, weight: .bold)).foregroundStyle(.primary).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(line ?? " ").font(.scaled(10)).foregroundStyle(.secondary)
        }
        // every card is as tall as the tallest, whatever each one wraps
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(.horizontal, 14).padding(.vertical, 12)
        return Group {
            if highlighted { face.background(RoundedRectangle(cornerRadius: 14).fill(Color.themeAccent.opacity(0.14))) } else { face.settingsCard() }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A bar a day for the range, the day with the most in the accent.
private struct StatisticsChart: View {
    let days: [StatisticsDay]
    let metric: StatisticsMetric

    private func value(_ day: StatisticsDay) -> Int { metric == .words ? day.words : day.dictations }

    var body: some View {
        let most = days.map(value).max() ?? 0
        Chart(days) { day in
            BarMark(x: .value("Day", day.day, unit: .day), y: .value(metric.title, value(day)))
                .foregroundStyle(Color.themeAccent.opacity(value(day) == most && most > 0 ? 1 : 0.7))
                .accessibilityLabel(day.day.formatted(.dateTime.weekday(.wide).month().day()))
                .accessibilityValue("\(value(day)) \(metric == .words ? "words" : "dictations")")
        }
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
        .frame(height: 150)
        .accessibilityLabel("\(metric.title) per day")
    }
}

/// A small bar a day for the last 7 days, the busiest day in the full accent.
private struct WeekChart: View {
    let days: [StatisticsDay]

    var body: some View {
        let busiest = busiestDay(days)?.day
        Chart(days) { day in
            BarMark(x: .value("Day", day.day, unit: .day), y: .value("Words", day.words))
                .foregroundStyle(Color.themeAccent.opacity(day.day == busiest ? 1 : 0.6))
                .accessibilityLabel(day.day.formatted(.dateTime.weekday(.wide).month().day()))
                .accessibilityValue("\(day.words) words")
        }
        .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
        .chartYAxis(.hidden)
        .frame(height: 70)
        .accessibilityLabel("Words per day, last 7 days")
    }
}
