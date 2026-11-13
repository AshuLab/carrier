import Charts
import CarrierCore
import SwiftUI

/// The consumption part of the Usage page (docs/specs/usage-and-limits.md): four cards, the filters, the stacked daily chart and the two tables.
/// `usageKpis`, `usageBars`, `usageTooltip` and the row functions of `CarrierCore` decide every number and word; this only draws them. The
/// filters live in the store, and a change of one asks the host again.
struct ConsumptionSection: View {
    @Bindable var store: UsageStore
    @State private var mapping: UsageModelRow?
    @State private var searched = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            filters
            if let snapshot = store.snapshot {
                kpis(snapshot)
                chart(snapshot)
                modelTable(snapshot)
                workspaceTable(snapshot)
            }
        }
        .sheet(item: $mapping) { row in
            MapSheet(row: row, catalog: store.snapshot?.catalogModels ?? [], store: store).themed()
        }
        .onChange(of: store.days) { reload() }
        .onChange(of: store.sourceFilter) { reload() }
        .onChange(of: store.providerFilter) { reload() }
        // the search asks a moment after the last key, not at every one
        .task(id: store.searchText) {
            guard store.searchText != searched else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard Task.isCancelled == false else { return }
            searched = store.searchText
            await store.load()
        }
        .onAppear { searched = store.searchText }
    }

    private func reload() { Task { await store.load() } }

    // MARK: filters

    private var filters: some View {
        HStack(spacing: 8) {
            SegmentedChoice(
                options: [(UsageMetric.cost, "Cost", "dollarsign.circle"), (.tokens, "Tokens", "number")], selection: $store.metric
            )
            .accessibilityLabel("Metric")
            SegmentedChoice(options: [7, 14, 30, 90].map { ($0, "\($0)d", nil) }, selection: $store.days).accessibilityLabel("Range")
            ChoicePopUp(
                label: "Provider",
                options: [(.all, "All providers"), (.claude, "Claude"), (.codex, "Codex"), (.agy, "Antigravity"), (.local, "Local")],
                selection: $store.providerFilter, width: 130
            )
            ChoicePopUp(
                label: "Source", options: [(.all, "All sources"), (.epic, "Epic"), (.chat, "Chat"), (.external, "External")], selection: $store.sourceFilter, width: 120
            )
            Spacer(minLength: 8)
            TextField("Search model or workspace", text: $store.searchText).settingsField(width: 200, icon: "magnifyingglass")
        }
    }

    // MARK: cards

    private func kpis(_ snapshot: UsageSnapshot) -> some View {
        SettingsTabCard {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(usageKpis(snapshot).enumerated()), id: \.offset) { index, kpi in
                    if index > 0 { SettingsDivider(vertical: true).padding(.vertical, 12) }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(kpi.title).sectionLabel()
                        Text(kpi.value).font(.scaled(20, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                        // the footnote of the cost is the one that matters: an unpriced model is missing from the number
                        Text(kpi.footnote ?? " ").font(.scaled(11)).foregroundStyle(kpi.title == "Est. API Cost" && kpi.footnote != nil ? .orange : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12).padding(.leading, index > 0 ? 14 : 0)
                    .accessibilityElement(children: .combine)
                }
            }
            // the cards' lines take the height of the tallest card
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: chart

    private func chart(_ snapshot: UsageSnapshot) -> some View {
        let bars = usageBars(snapshot, metric: store.metric)
        return SettingsTabCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Daily \(store.metric == .cost ? "estimated API cost" : "tokens")").sectionLabel()
                if usageIsEmpty(snapshot) {
                    if store.hasActiveFilters {
                        EmptyStateView(
                            icon: "chart.bar", title: "Nothing matches these filters", line: "Clear them to see all of the last \(store.days) days.",
                            action: ("Clear filters", { store.clearFilters(); reload() }), actionIcon: "xmark"
                        )
                        .frame(minHeight: 220)
                    } else {
                        EmptyStateView(icon: "chart.bar", title: "No usage in the last \(store.days) days", line: "Epics, chats and terminal sessions show here once they run.")
                            .frame(minHeight: 220)
                    }
                } else if bars.contains(where: { $0.total > 0 }) {
                    DailyChart(bars: bars, metric: store.metric)
                } else {
                    // every bar is zero (all the models are unpriced): a chart of zeros draws nothing and looks broken
                    EmptyStateView(
                        icon: "chart.bar", title: "No cost to chart",
                        line: "The models used have no price yet, so no cost is counted. Map them below, or look at the tokens.",
                        action: ("Show tokens", { store.metric = .tokens }), actionIcon: "number"
                    )
                    .frame(minHeight: 220)
                }
            }
            .padding(.vertical, 12)
        }
    }

    // MARK: tables

    private func modelTable(_ snapshot: UsageSnapshot) -> some View {
        let rows = usageModelRows(snapshot)
        return VStack(alignment: .leading, spacing: 6) {
            Text("By model").sectionLabel().padding(.leading, 14)
            SettingsTabCard {
                if rows.isEmpty { emptyRow("No models used") }
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { SettingsDivider() }
                    HStack(spacing: 12) {
                        UsageProviderMark(title: row.provider, size: 16).frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.model).font(.scaled(12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                            Text(row.provider).font(.scaled(11)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text(row.detail).font(.scaled(11)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                        costCell(row).frame(width: 150, alignment: .trailing)
                    }
                    .padding(.vertical, 9).frame(minHeight: 40)
                }
                if rows.isEmpty == false {
                    let total = usageModelTotal(snapshot)
                    UsageFooter(title: total.model, detail: total.detail, cost: total.cost ?? "")
                }
            }
        }
    }

    @ViewBuilder private func costCell(_ row: UsageModelRow) -> some View {
        HStack(spacing: 6) {
            if let cost = row.cost { Text(cost).font(.scaled(12, weight: .medium)).monospacedDigit() }
            if row.unpriced {
                Button { mapping = row } label: { Badge(text: "Unpriced · Map", icon: "exclamationmark.triangle.fill", tint: .orange) }
                    .buttonStyle(.plain).accessibilityLabel("Unpriced. Map \(row.model) to a price")
                    .help("This model is not in the price table: its cost is missing, not zero. Map it to a price.")
            } else if row.overridden {
                Button { mapping = row } label: { Badge(text: "Custom", icon: "pencil", tint: .secondary) }
                    .buttonStyle(.plain).accessibilityLabel("Custom price. Edit the price of \(row.model)")
                    .help("You set this model's price. Edit or clear it.")
            }
        }
    }

    private func workspaceTable(_ snapshot: UsageSnapshot) -> some View {
        let rows = usageWorkspaceRows(snapshot)
        return VStack(alignment: .leading, spacing: 6) {
            Text("By workspace & source").sectionLabel().padding(.leading, 14)
            SettingsTabCard {
                if rows.isEmpty { emptyRow("No workspaces used") }
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { SettingsDivider() }
                    HStack(spacing: 12) {
                        Image(systemName: sourceSymbol(row.source)).font(.scaled(13)).foregroundStyle(.secondary).frame(width: 20).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.name).font(.scaled(12, weight: .medium)).lineLimit(1).truncationMode(.middle).help(row.path)
                            Text(row.source).font(.scaled(11)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text(row.detail).font(.scaled(11)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                        Text(row.cost).font(.scaled(12, weight: .medium)).monospacedDigit().frame(width: 150, alignment: .trailing)
                    }
                    .padding(.vertical, 9).frame(minHeight: 40)
                }
                if rows.isEmpty == false {
                    let total = usageWorkspaceTotal(snapshot)
                    UsageFooter(title: total.name, detail: total.detail, cost: total.cost)
                }
            }
        }
    }

    /// The sidebar's own symbols: Carrier's epics, the chat's bubbles, a terminal for what ran outside both.
    private func sourceSymbol(_ source: String) -> String {
        switch source {
        case "Epic": "paperplane"
        case "Chat": "bubble.left.and.bubble.right"
        default: "terminal"
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 14)
    }
}

/// The foot of a table: the total, on a band of its own that reaches a little past the rows' text so it reads as a sum and not as one more row.
private struct UsageFooter: View {
    let title: String
    let detail: String
    let cost: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sum").font(.scaled(13, weight: .semibold)).foregroundStyle(.secondary).frame(width: 20).accessibilityHidden(true)
            Text(title).font(.scaled(12, weight: .semibold)).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 8)
            Text(detail).font(.scaled(11)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
            Text(cost).font(.scaled(13, weight: .semibold)).monospacedDigit().frame(width: 150, alignment: .trailing)
        }
        .padding(.vertical, 9).padding(.horizontal, 8).frame(minHeight: 40)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.07)))
        .padding(.horizontal, -8).padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

/// A provider's logo in the text colour, from the bundled icons; the local servers have none and get a computer.
struct UsageProviderMark: View {
    /// `Claude`, `Codex`, `Antigravity` or `Local`.
    let title: String
    var size: CGFloat = 16

    var body: some View {
        if AgentAvatar.mark(title.lowercased()) != nil {
            ProviderMark(name: title.lowercased(), size: size).foregroundStyle(.primary).accessibilityHidden(true)
        } else {
            Image(systemName: "desktopcomputer").font(.scaled(size - 3)).foregroundStyle(.secondary).accessibilityHidden(true)
        }
    }
}

private let providerColors: [String: Color] = [
    "Claude": Color(red: 0.85, green: 0.47, blue: 0.34), "Codex": Color(red: 0.25, green: 0.6, blue: 0.55),
    "Antigravity": Color(red: 0.4, green: 0.45, blue: 0.85), "Local": Color.gray,
]

/// The days as stacked bars, one colour a provider. Hovering a day shows its breakdown and a click keeps it (a second click lets go).
private struct DailyChart: View {
    let bars: [UsageBar]
    let metric: UsageMetric
    @State private var hovered: String?
    @State private var pinned: String?

    private var shown: UsageBar? { bars.first { $0.label == (pinned ?? hovered) } }

    // Its own function, with the plotted values typed, so the compiler has one small expression to solve.
    @ChartContentBuilder
    private func segmentMark(_ bar: UsageBar, _ segment: UsageSegment, _ valueName: String) -> some ChartContent {
        let day: PlottableValue<String> = .value("Day", bar.label)
        let amount: PlottableValue<Double> = .value(valueName, segment.value)
        let provider: PlottableValue<String> = .value("Provider", usageProviderTitle(segment.provider))
        let dimmed: Bool = shown != nil && shown?.id != bar.id
        let opacity: Double = dimmed ? 0.45 : 1
        // VoiceOver reads each segment, so a day's numbers do not depend on the pointer
        let spoken: String = "\(bar.label), \(usageProviderTitle(segment.provider))"
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
        let day: PlottableValue<String> = .value("Day", bar.label)
        let level: PlottableValue<Double> = .value("No use", floor)
        BarMark(x: day, y: level).foregroundStyle(Color.primary.opacity(0.16)).accessibilityLabel("\(bar.label), no use")
    }

    var body: some View {
        // one label in a few, so thirty days do not run into each other
        let step = max(1, Int((Double(bars.count) / 7).rounded(.up)))
        let titles = usageChartProviders.map(usageProviderTitle)
        let valueName: String = metric == .cost ? "Cost" : "Tokens"
        let floor: Double = (bars.map(\.total).max() ?? 0) * 0.012
        Chart {
            ForEach(bars) { bar in
                ForEach(bar.segments) { segment in
                    segmentMark(bar, segment, valueName)
                }
                if bar.total == 0 { quietMark(bar, floor: floor) }
            }
            if let shown {
                RuleMark(x: .value("Day", shown.label)).foregroundStyle(Color.secondary.opacity(0.25))
            }
        }
        // every day has its column, with or without marks: the axis only knows the days that have one
        .chartXScale(domain: bars.map(\.label))
        .chartForegroundStyleScale(domain: titles, range: titles.map { providerColors[$0] ?? .gray })
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
        .accessibilityLabel("Daily \(metric == .cost ? "cost" : "tokens") by provider")
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(tooltip.title).font(.scaled(12, weight: .semibold))
                Text(tooltip.weekday).font(.scaled(11)).foregroundStyle(.secondary)
            }
            if tooltip.lines.isEmpty { Text("No use").font(.scaled(11)).foregroundStyle(.secondary) }
            VStack(spacing: 5) {
                ForEach(tooltip.lines, id: \.provider) { line in
                    HStack(spacing: 8) {
                        Circle().fill(providerColors[line.provider] ?? .gray).frame(width: 7, height: 7)
                        UsageProviderMark(title: line.provider, size: 12).frame(width: 14)
                        Text(line.provider).font(.scaled(11))
                        Spacer(minLength: 14)
                        Text(line.value).font(.scaled(11)).monospacedDigit()
                    }
                }
            }
            if tooltip.lines.count > 1 {
                SettingsDivider()
                HStack { Text("Total").font(.scaled(11, weight: .semibold)); Spacer(minLength: 14); Text(tooltip.total).font(.scaled(11, weight: .semibold)).monospacedDigit() }
            }
        }
        .frame(width: 200).padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.themeWindow))
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
    }
}

// MARK: Map sheet

/// `Unpriced · Map`: prices a model as `$0.00` local, as a catalog model, or with rates of its own; `Clear` goes back to the table. The form is
/// checked by `UsageOverrideDraft` before the host is asked, and what was typed stays when the host refuses.
private struct MapSheet: View {
    let row: UsageModelRow
    let catalog: [String]
    let store: UsageStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: UsageOverrideDraft
    @State private var attempted = false
    @State private var saving = false
    @State private var refusal: String?

    init(row: UsageModelRow, catalog: [String], store: UsageStore) {
        self.row = row
        self.catalog = catalog
        self.store = store
        _draft = State(initialValue: UsageOverrideDraft(mode: catalog.isEmpty ? .custom : .alias))
    }

    private var errors: [UsageOverrideDraft.Field: String] { attempted ? draft.check(model: row.model, catalog: catalog).errors : [:] }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Price for \(row.model)").font(.title3.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                Text("The cost on this page follows what you set here. Nothing is guessed.").font(.callout).foregroundStyle(.secondary)
            }
            Picker("Price", selection: $draft.mode) {
                Text("$0.00 local").tag(UsageOverrideDraft.Mode.local)
                Text("Catalog model").tag(UsageOverrideDraft.Mode.alias)
                Text("Custom rates").tag(UsageOverrideDraft.Mode.custom)
                if row.overridden { Text("Clear").tag(UsageOverrideDraft.Mode.clear) }
            }
            .pickerStyle(.segmented).labelsHidden()
            fields
            if let refusal { ProblemLine(text: refusal) }
            HStack {
                Spacer()
                if saving { ProgressView().controlSize(.small) }
                Button("Cancel") { dismiss() }.buttonStyle(SecondaryCapsuleButtonStyle()).keyboardShortcut(.cancelAction).disabled(saving)
                Button("Save") { Task { await save() } }.buttonStyle(PrimaryCapsuleButtonStyle()).keyboardShortcut(.defaultAction).disabled(saving)
            }
        }
        .padding(20).frame(width: 480)
        .onChange(of: draft) { refusal = nil }
    }

    @ViewBuilder private var fields: some View {
        switch draft.mode {
        case .local:
            Text("Counts every token of this model as free, like a model running on your Mac.").font(.callout).foregroundStyle(.secondary)
        case .clear:
            Text("Goes back to the price table. If the model is not in it, it shows as unpriced again.").font(.callout).foregroundStyle(.secondary)
        case .alias:
            VStack(alignment: .leading, spacing: 4) {
                Text("Uses the rates of").font(.callout).foregroundStyle(.secondary)
                ChoicePopUp(label: "Catalog model", options: [("", "Choose a model")] + catalog.map { ($0, $0) }, selection: $draft.alias, width: 280)
                problem(errors[.alias])
            }
        case .custom:
            VStack(alignment: .leading, spacing: 8) {
                Text("US dollars per million tokens").font(.callout).foregroundStyle(.secondary)
                rate("Input", "required", $draft.input, .input)
                rate("Cached read", "optional", $draft.cachedInput, .cachedInput)
                rate("Cache write", "optional", $draft.cacheWrite, .cacheWrite)
                rate("Output", "required", $draft.output, .output)
            }
        }
    }

    private func rate(_ title: String, _ hint: String, _ text: Binding<String>, _ field: UsageOverrideDraft.Field) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).frame(width: 110, alignment: .leading)
                TextField(hint, text: text).settingsField(width: 120).environment(\.settingsInvalid, errors[field] != nil)
                    .accessibilityLabel("\(title) dollars per million tokens")
            }
            problem(errors[field]).padding(.leading, 110)
        }
    }

    @ViewBuilder private func problem(_ text: String?) -> some View {
        if let text { ProblemLine(text: text, font: .caption) }
    }

    private func save() async {
        attempted = true
        guard let override = draft.check(model: row.model, catalog: catalog).override else { return }
        saving = true
        refusal = await store.override(override)
        saving = false
        if refusal == nil { dismiss() }
    }
}
