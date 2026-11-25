import Charts
import CarrierCore
import SwiftUI

private let providerColors: [String: Color] = [
    "claude": Color(Tokens.Provider.claude), "codex": Color(Tokens.Provider.codex),
    "agy": Color(Tokens.Provider.antigravity), "local": Color.gray,
]

/// The days as stacked bars, one colour a provider. Hovering a day shows its breakdown and a click keeps it (a second click lets go).
struct DailyChart: View {
    let bars: [UsageBar]
    let metric: UsageMetric
    @State private var hovered: String?
    @State private var pinned: String?

    private var shown: UsageBar? { bars.first { $0.label == (pinned ?? hovered) } }

    // Its own function, with the plotted values typed, so the compiler has one small expression to solve.
    @ChartContentBuilder
    private func segmentMark(_ bar: UsageBar, _ segment: UsageSegment, _ valueName: String) -> some ChartContent {
        let day: PlottableValue<String> = .value(Copy.usageChartDay(), bar.label)
        let amount: PlottableValue<Double> = .value(valueName, segment.value)
        let provider: PlottableValue<String> = .value(Copy.usageFilterProvider(), usageProviderTitle(segment.provider))
        let dimmed: Bool = shown != nil && shown?.id != bar.id
        let opacity: Double = dimmed ? 0.45 : 1
        // VoiceOver reads each segment, so a day's numbers do not depend on the pointer
        let spoken: String = Copy.usageChartSegment(day: bar.label, provider: usageProviderTitle(segment.provider))
        let worth: String = usageFormat(segment.value, metric)
        BarMark(x: day, y: amount)
            .foregroundStyle(by: provider)
            .opacity(opacity)
            .accessibilityLabel(spoken)
            .accessibilityValue(worth)
    }

    /// A day with nothing used: a low grey stub, so it reads as "no use" and not as a missing day.
    @ChartContentBuilder
    private func quietMark(_ bar: UsageBar, floor: Double) -> some ChartContent {
        let day: PlottableValue<String> = .value(Copy.usageChartDay(), bar.label)
        let level: PlottableValue<Double> = .value(Copy.usageChartNoUse(), floor)
        BarMark(x: day, y: level).foregroundStyle(Color.primary.opacity(0.16)).accessibilityLabel(Copy.usageChartDayNoUse(day: bar.label))
    }

    var body: some View {
        // one label in a few, so thirty days do not run into each other
        let step = max(1, Int((Double(bars.count) / 7).rounded(.up)))
        let titles = usageChartProviders.map { usageProviderTitle($0) }
        let valueName: String = Copy.usageMetricName(metric: metric == .cost ? .cost : .tokens)
        let floor: Double = (bars.map(\.total).max() ?? 0) * 0.012
        Chart {
            ForEach(bars) { bar in
                ForEach(bar.segments) { segment in
                    segmentMark(bar, segment, valueName)
                }
                if bar.total == 0 { quietMark(bar, floor: floor) }
            }
            if let shown {
                RuleMark(x: .value(Copy.usageChartDay(), shown.label)).foregroundStyle(Color.secondary.opacity(0.25))
            }
        }
        // every day has its column, with or without marks: the axis only knows the days that have one
        .chartXScale(domain: bars.map(\.label))
        .chartForegroundStyleScale(domain: titles, range: usageChartProviders.map { providerColors[$0] ?? .gray })
        .chartXAxis { AxisMarks(values: bars.enumerated().filter { $0.offset % step == 0 }.map(\.element.label)) { _ in AxisValueLabel() } }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel { if let amount = value.as(Double.self) { Text(usageFormat(amount, metric)) } }
            }
        }
        .chartBackground { proxy in weekendBands(proxy) }
        .chartLegend(position: .bottom, alignment: .leading)
        .chartOverlay { proxy in
            ZStack(alignment: .topLeading) {
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            if case .active(let point) = phase { hovered = day(at: point, proxy, geometry) } else { hovered = nil }
                        }
                        .onTapGesture { point in
                            let tapped = day(at: point, proxy, geometry)
                            pinned = pinned == tapped ? nil : tapped
                        }
                }
                tooltipLayer(proxy)
            }
        }
        .frame(height: 220)
        .accessibilityLabel(Copy.usageChartLabel(metric: metric == .cost ? .cost : .tokens))
    }

    /// The tooltip beside the hovered day, on the side with more room. It is a view of the overlay and not a chart annotation: an annotation
    /// is drawn without the bundled provider marks.
    @ViewBuilder private func tooltipLayer(_ proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            if let shown, let frame = proxy.plotFrame, let x = proxy.position(forX: shown.label) {
                let plot: CGRect = geometry[frame]
                let left: Bool = x > plot.width / 2
                Tooltip(tooltip: usageTooltip(shown, metric: metric))
                    .offset(x: plot.minX + x + (left ? -224 : 12), y: plot.minY + 6)
            }
        }
        .allowsHitTesting(false)
    }

    /// A faint column behind each Saturday and Sunday, so the weekends read at a glance.
    @ViewBuilder private func weekendBands(_ proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            if let frame = proxy.plotFrame {
                let plot: CGRect = geometry[frame]
                let band: CGFloat = plot.width / CGFloat(max(bars.count, 1))
                ForEach(bars.filter(\.weekend)) { bar in
                    if let x = proxy.position(forX: bar.label) {
                        Rectangle().fill(Color.primary.opacity(0.06)).frame(width: band, height: plot.height).position(x: plot.minX + x, y: plot.midY)
                    }
                }
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }

    private func day(at point: CGPoint, _ proxy: ChartProxy, _ geometry: GeometryProxy) -> String? {
        guard let frame = proxy.plotFrame else { return nil }
        return proxy.value(atX: point.x - geometry[frame].origin.x, as: String.self)
    }
}

/// The chart's tooltip, drawn as the cards are: the window's own colour with a lift, a one point edge, a day and its weekday on top, a line per
/// provider with its mark and the total under a line.
private struct Tooltip: View {
    let tooltip: UsageTooltip

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s8) {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s6) {
                Text(tooltip.title).scaledFont(12, weight: .semibold)
                Text(tooltip.weekday).scaledFont(11).foregroundStyle(.secondary)
            }
            if tooltip.lines.isEmpty { Text(Copy.usageChartNoUse()).scaledFont(11).foregroundStyle(.secondary) }
            VStack(spacing: Tokens.Space.s5) {
                ForEach(tooltip.lines, id: \.provider) { line in
                    HStack(spacing: Tokens.Space.s8) {
                        Circle().fill(providerColors[line.providerId] ?? .gray).frame(width: 7, height: 7)
                        UsageProviderMark(title: line.provider, size: 12).frame(width: 14)
                        Text(line.provider).scaledFont(11)
                        Spacer(minLength: 14)
                        Text(line.value).scaledFont(11).monospacedDigit()
                    }
                }
            }
            if tooltip.lines.count > 1 {
                SettingsDivider()
                HStack { Text(Copy.usageTooltipTotal()).scaledFont(11, weight: .semibold); Spacer(minLength: 14); Text(tooltip.total).scaledFont(11, weight: .semibold).monospacedDigit() }
            }
        }
        .frame(width: 200).padding(Tokens.Space.s12)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.card).fill(Color.themeWindow))
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.card).fill(Color.primary.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.card).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
    }
}
