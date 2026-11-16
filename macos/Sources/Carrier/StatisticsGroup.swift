import Charts
import CarrierCore
import SwiftUI

/// The Statistics segment of the Dictation page: the range, four figures, a chart by day, and the settings (typing speed, Reset statistics).
struct StatisticsGroup: View {
    var dictation = DictationController.shared
    @AppStorage(AppPreferences.dictationTypingSpeedKey) private var wpm = AppPreferences.defaultDictationTypingSpeed
    @State private var range = StatisticsRange.month
    @State private var metric = StatisticsMetric.words
    @State private var confirmingReset = false

    var body: some View {
        let records = dictation.records
        VStack(alignment: .leading, spacing: 12) {
            if records.counts.isEmpty {
                VStack(spacing: 4) {
                    Text("No statistics yet").fontWeight(.medium)
                    Text("Dictate with the microphone or the shortcut and finish with the text pasted or copied: the numbers start here.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 36)
            } else {
                let speed = min(max(wpm, AppPreferences.dictationTypingSpeedRange.lowerBound), AppPreferences.dictationTypingSpeedRange.upperBound)
                let figures = dictationFigures(records.counts, range: range, now: Date())
                HStack {
                    Text("Overview").sectionLabel().padding(.leading, 14)
                    Spacer(minLength: 8)
                    SegmentedChoice(options: StatisticsRange.allCases.map { (value: $0, title: $0.title, icon: nil) }, selection: $range)
                }
                cards(figures, wpm: speed)
                HStack {
                    Text("\(metric.title) per day").sectionLabel().padding(.leading, 14)
                    Spacer(minLength: 8)
                    SegmentedChoice(options: StatisticsMetric.allCases.map { (value: $0, title: $0.title, icon: nil) }, selection: $metric)
                }
                SettingsTabCard { StatisticsChart(days: figures.days, metric: metric).padding(.horizontal, 14).padding(.vertical, 10) }
                Text("The statistics are their own counters: they hold no text, and turning the history off or deleting entries does not change them.")
                    .font(.caption).foregroundStyle(.secondary)
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
        return HStack(spacing: 10) {
            StatisticsCard(title: "Dictations", value: now.dictations.formatted(), line: statisticsChange(Double(now.dictations), from: before.map { Double($0.dictations) }))
            StatisticsCard(title: "Words", value: now.words.formatted(), line: statisticsChange(Double(now.words), from: before.map { Double($0.words) }))
            StatisticsCard(title: "Speaking time", value: statisticsDuration(now.seconds), line: statisticsChange(now.seconds, from: before?.seconds))
            StatisticsCard(
                title: "Time saved", value: statisticsDuration(durationSeconds(now.saved(wpm: wpm))),
                line: statisticsChange(durationSeconds(now.saved(wpm: wpm)), from: before.map { durationSeconds($0.saved(wpm: wpm)) }), highlighted: true)
        }
    }

    private func durationSeconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    private var settings: some View {
        SettingsGroup(title: "Statistics settings") {
            SettingsTabRow(title: "Typing speed", detail: "Used for the time saved: words ÷ speed, minus the time you spent speaking", first: true) {
                Stepper(value: $wpm, in: AppPreferences.dictationTypingSpeedRange, step: 5) {
                    Text("\(wpm) words/min").monospacedDigit()
                }
                .accessibilityLabel("Typing speed, words per minute")
            }
            SettingsTabRow(title: "Reset statistics", detail: "Deletes the counters. The history stays, and deleting history never changes the statistics") {
                Button("Reset statistics…", role: .destructive) { confirmingReset = true }
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
        VStack(alignment: .leading, spacing: 3) {
            Text(title).sectionLabel()
            Text(value).font(.scaled(24, weight: .bold)).foregroundStyle(highlighted ? Color.themeAccent : .primary).monospacedDigit()
            Text(line ?? " ").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(highlighted ? Color.themeAccent.opacity(0.14) : Color.primary.opacity(0.06)))
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
