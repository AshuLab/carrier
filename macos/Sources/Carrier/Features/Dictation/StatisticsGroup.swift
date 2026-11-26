import CarrierUI
import Charts
import CarrierCore
import SwiftUI

/// The Statistics screen of the Dictation page, a group for each thing it shows: the range and four figures, a chart by day, the hours of the day, the week
/// against the one before, the records, and the settings (typing speed, Reset statistics).
struct StatisticsGroup: View {
    var dictation = DictationController.shared
    @AppStorage(Preference.dictationStatisticsWpm) private var wpm
    @State private var range = StatisticsRange.month
    @State private var metric = StatisticsMetric.words
    @State private var confirmingReset = false
    @State private var unparsable: Set<String> = []
    @State private var cardsWidth = CGFloat.infinity
    @Environment(\.textScale) private var textScale

    var body: some View {
        let records = dictation.records
        Group {
            if records.counts.isEmpty {
                SettingsGroup(title: "") {
                    EmptyStateView(
                        icon: .chartBar, title: Copy.dictationNoStats(), line: Copy.dictationNoStatsLine()
                    )
                    .frame(minHeight: 220)
                }
            } else {
                let speed = min(max(wpm, AppPreferences.dictationTypingSpeedRange.lowerBound), AppPreferences.dictationTypingSpeedRange.upperBound)
                let figures = dictationFigures(records.counts, range: range, now: Date())
                SettingsGroup(id: "overview", title: Copy.dictationGroupOverview(), accessory: {
                    SegmentedChoice(options: StatisticsRange.allCases.map { (value: $0, title: $0.title(), icon: nil) }, selection: $range)
                }, content: { cards(figures, wpm: speed) })
                SettingsGroup(title: Copy.dictationPerDay(metric: metric.title()), accessory: {
                    SegmentedChoice(options: StatisticsMetric.allCases.map { (value: $0, title: $0.title(), icon: nil) }, selection: $metric)
                }, content: { StatisticsChart(days: figures.days, metric: metric).padding(.vertical, Tokens.Space.s8) })
                SettingsGroup(id: "by-hour-of-the-day", title: Copy.dictationGroupHours()) { hoursContent(dictationHours(records.counts, range: range, now: Date())) }
                SettingsGroup(id: "this-week", title: Copy.dictationGroupWeek()) { weekContent(dictationFigures(records.counts, range: .week, now: Date()), wpm: speed) }
                recordsGroup(statisticsRecords(records.counts))
            }
            settings
        }
        .alert(Copy.dictationResetStatsTitle(), isPresented: $confirmingReset) {
            Button(Copy.dictationCancel(), role: .cancel) {}
            Button(Copy.dictationReset(), role: .destructive) { records.resetStatistics() }
        } message: {
            Text(Copy.dictationResetStatsMessage())
        }
    }

    private func cards(_ figures: DictationFigures, wpm: Int) -> some View {
        let now = figures.current
        let before = figures.previous
        let dictations = StatisticsCard(title: Copy.dictationCardDictations(), value: now.dictations.formatted(), line: statisticsChange(Double(now.dictations), from: before.map { Double($0.dictations) }))
        let words = StatisticsCard(title: Copy.dictationCardWords(), value: now.words.formatted(), line: statisticsChange(Double(now.words), from: before.map { Double($0.words) }))
        let speaking = StatisticsCard(title: Copy.dictationCardSpeaking(), value: statisticsDuration(now.seconds), line: statisticsChange(now.seconds, from: before?.seconds))
        let saved = StatisticsCard(
            title: Copy.dictationCardSaved(), value: statisticsDuration(now.saved(wpm: wpm).inSeconds),
            line: statisticsChange(now.saved(wpm: wpm).inSeconds, from: before.map { $0.saved(wpm: wpm).inSeconds }), highlighted: true)
        return cardGrid([dictations, words, speaking, saved])
    }

    /// The cards of a group, with no container behind them: four in a row while each has the room its longest title and value need (equal shares, at the
    /// person's text size), two by two when the window is narrow. In the form the row has no background and no inset, so the cards are the group.
    private func cardGrid(_ cards: [StatisticsCard]) -> some View {
        let four = cardsWidth >= 4 * 130 * CGFloat(textScale.percent) / 100 + 30
        return Group {
            if four {
                HStack(alignment: .top, spacing: Tokens.Space.s10) { ForEach(cards.indices, id: \.self) { cards[$0] } }
            } else {
                VStack(spacing: Tokens.Space.s10) {
                    HStack(alignment: .top, spacing: Tokens.Space.s10) { cards[0]; cards[1] }
                    HStack(alignment: .top, spacing: Tokens.Space.s10) { cards[2]; cards[3] }
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { cardsWidth = $0 }
        .padding(.vertical, Tokens.Space.s4)
        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
    }

    /// 24 cells, one per hour, as strong as the dictations of that hour, and the line that says the hour the person dictates most.
    private func hoursContent(_ hours: DictationHours) -> some View {
        let most = max(hours.dictations.max() ?? 0, 1)
        let line = statisticsHoursLine(hours)
        return VStack(alignment: .leading, spacing: Tokens.Space.s4) {
            HStack(spacing: Tokens.Space.s2) {
                ForEach(0..<24, id: \.self) { hour in
                    RoundedRectangle(cornerRadius: Tokens.Radius.tiny).fill(.tint.opacity(0.08 + 0.92 * Double(hours.dictations[hour]) / Double(most)))
                        .frame(height: 34).help(Copy.dictationHourHelp(hour: String(format: "%02d:00", hour), count: hours.dictations[hour]))
                }
            }
            HStack(spacing: Tokens.Space.none) {
                ForEach([0, 6, 12, 18], id: \.self) { hour in
                    Text("\(hour)").frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .scaledFont(10).foregroundStyle(.secondary)
            Text(line).scaledFont(11).foregroundStyle(.secondary).padding(.top, Tokens.Space.s4)
        }
        .padding(.vertical, Tokens.Space.s6).frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore).accessibilityLabel(Copy.dictationHoursLabel()).accessibilityValue(line)
    }

    /// The last 7 days against the 7 before, in a sentence and a small chart of the words of each day.
    private func weekContent(_ week: DictationFigures, wpm: Int) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s8) {
            Text(weeklySummary(week, wpm: wpm)).scaledFont(12).fixedSize(horizontal: false, vertical: true)
            WeekChart(days: week.days)
        }
        .padding(.vertical, Tokens.Space.s6).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recordsGroup(_ records: StatisticsRecords) -> some View {
        func on(_ day: Date?) -> String { day?.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) ?? Copy.dictationNothingYet() }
        return SettingsGroup(id: "records", title: Copy.dictationGroupRecords(), footer: Copy.dictationRecordsFooter()) {
            cardGrid([
                StatisticsCard(title: Copy.dictationRecordMostDictations(), value: (records.mostDictations?.value ?? 0).formatted(), line: on(records.mostDictations?.day)),
                StatisticsCard(title: Copy.dictationRecordMostWords(), value: (records.mostWords?.value ?? 0).formatted(), line: on(records.mostWords?.day)),
                StatisticsCard(title: Copy.dictationRecordLongest(), value: statisticsDuration(records.longest?.value ?? 0), line: on(records.longest?.day)),
                StatisticsCard(title: Copy.dictationRecordStreak(), value: Copy.dictationStreakDays(days: records.streak), line: Copy.dictationDaysInARow()),
            ])
        }
    }

    private var settings: some View {
        SettingsGroup(id: "statistics-settings", title: Copy.dictationGroupStatsSettings()) {
            SettingsTabRow(
                id: "typing-speed", title: Copy.dictationTypingSpeed(), detail: Copy.dictationTypingSpeedDetail(), first: true,
                problem: unparsable.isEmpty
                    ? nil
                    : Copy.dictationTypingSpeedProblem(
                        low: AppPreferences.dictationTypingSpeedRange.lowerBound, high: AppPreferences.dictationTypingSpeedRange.upperBound)
            ) {
                // the counter of Behavior's numbers: a number between the range's ends, − and + by 5; text that is not one keeps the last good value
                HStack(spacing: Tokens.Space.s6) {
                    NumberField(
                        key: Copy.dictationTypingSpeedField(), value: $wpm, unparsable: $unparsable,
                        parse: { Int($0).flatMap { AppPreferences.dictationTypingSpeedRange.contains($0) ? $0 : nil } }, format: { String($0) },
                        // a click goes to the end of the range when 5 would pass it, and nowhere when it is already there
                        step: { value, direction in
                            let range = AppPreferences.dictationTypingSpeedRange
                            let next = min(max(value + direction * 5, range.lowerBound), range.upperBound)
                            return next == value ? nil : next
                        })
                    Text(Copy.dictationWordsPerMinute()).scaledFont(11).foregroundStyle(.secondary)
                }
            }
            SettingsTabRow(id: "reset-statistics", title: Copy.dictationResetStats(), detail: Copy.dictationResetStatsDetail()) {
                Button(role: .destructive) { confirmingReset = true } label: { Label(Copy.dictationResetStatsButton(), icon: .trash) }
                    .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
            }
        }
    }
}

enum StatisticsMetric: CaseIterable {
    case words, dictations

    func title() -> String { self == .words ? Copy.dictationCardWords() : Copy.dictationCardDictations() }
}

private struct StatisticsCard: View {
    let title: String
    let value: String
    let line: String?
    var highlighted = false

    var body: some View {
        let face = VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            Text(title).sectionLabel().lineLimit(1)
            Text(value).scaledFont(24, weight: .bold).foregroundStyle(.primary).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(line ?? " ").scaledFont(10).foregroundStyle(.secondary)
        }
        // every card is as tall as the tallest, whatever each one wraps
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(.horizontal, Tokens.Space.s14).padding(.vertical, Tokens.Space.s12)
        return Group {
            if highlighted { face.background(RoundedRectangle(cornerRadius: Tokens.Radius.roomy).fill(.tint.opacity(0.14))) } else { face.settingsCard() }
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
            BarMark(x: .value(Copy.dictationChartDay(), day.day, unit: .day), y: .value(metric.title(), value(day)))
                .foregroundStyle(.tint.opacity(value(day) == most && most > 0 ? 1 : 0.7))
                .accessibilityLabel(day.day.formatted(.dateTime.weekday(.wide).month().day()))
                .accessibilityValue(metric == .words ? Copy.dictationWordsCount(count: value(day)) : Copy.dictationCount(count: value(day)))
        }
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
        .frame(height: 150)
        .accessibilityLabel(Copy.dictationPerDay(metric: metric.title()))
    }
}

/// A small bar a day for the last 7 days, the busiest day in the full accent.
private struct WeekChart: View {
    let days: [StatisticsDay]

    var body: some View {
        let busiest = busiestDay(days)?.day
        Chart(days) { day in
            BarMark(x: .value(Copy.dictationChartDay(), day.day, unit: .day), y: .value(Copy.dictationCardWords(), day.words))
                .foregroundStyle(.tint.opacity(day.day == busiest ? 1 : 0.6))
                .accessibilityLabel(day.day.formatted(.dateTime.weekday(.wide).month().day()))
                .accessibilityValue(Copy.dictationWordsCount(count: day.words))
        }
        .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true) } }
        .chartYAxis(.hidden)
        .frame(height: 70)
        .accessibilityLabel(Copy.dictationWeekChartLabel())
    }
}
