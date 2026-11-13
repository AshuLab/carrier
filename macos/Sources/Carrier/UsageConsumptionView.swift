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
        FlowLayout(spacing: 8) {
            Picker("Metric", selection: $store.metric) {
                Text("Cost ($)").tag(UsageMetric.cost)
                Text("Tokens").tag(UsageMetric.tokens)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 150)
            Picker("Range", selection: $store.days) {
                ForEach([7, 14, 30], id: \.self) { Text("\($0)d").tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 140)
            ChoicePopUp(
                label: "Source", options: [(.all, "All sources"), (.epic, "Epic"), (.chat, "Chat"), (.external, "External")], selection: $store.sourceFilter, width: 130
            )
            if store.providerFilter != .all {
                FilterChip(title: usageProviderTitle(store.providerFilter.rawValue), icon: "xmark", on: true) {
                    store.providerFilter = .all
                    reload()
                }
                .help("Showing \(usageProviderTitle(store.providerFilter.rawValue)) only; click to show all providers")
            }
            TextField("Search model or workspace", text: $store.searchText).settingsField(width: 210, icon: "magnifyingglass")
        }
    }

    // MARK: cards

    private func kpis(_ snapshot: UsageSnapshot) -> some View {
        SettingsTabCard {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(usageKpis(snapshot).enumerated()), id: \.offset) { index, kpi in
                    if index > 0 { Divider().padding(.vertical, 12) }
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
        }
    }

    // MARK: chart

    private func chart(_ snapshot: UsageSnapshot) -> some View {
        SettingsTabCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Daily \(store.metric == .cost ? "estimated API cost" : "tokens")").sectionLabel()
                if usageIsEmpty(snapshot) {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.bar").font(.scaled(22)).foregroundStyle(.secondary).accessibilityHidden(true)
                        Text(store.hasActiveFilters ? "Nothing matches these filters" : "No usage in the last \(store.days) days")
                            .font(.callout).foregroundStyle(.secondary)
                        if store.hasActiveFilters {
                            Button("Clear filters") { store.clearFilters(); reload() }.buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
                        }
                    }
                    .frame(maxWidth: .infinity).frame(height: 160)
                } else {
                    DailyChart(bars: usageBars(snapshot, metric: store.metric), metric: store.metric)
                }
            }
            .padding(.vertical, 12)
        }
    }

    // MARK: tables

    private func modelTable(_ snapshot: UsageSnapshot) -> some View {
        let rows = usageModelRows(snapshot)
        return VStack(alignment: .leading, spacing: 6) {
            Text("By model").sectionLabel()
            SettingsTabCard {
                if rows.isEmpty { emptyRow("No models used") }
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { SettingsDivider() }
                    HStack(spacing: 12) {
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
            }
        }
    }

    @ViewBuilder private func costCell(_ row: UsageModelRow) -> some View {
        HStack(spacing: 6) {
            if let cost = row.cost { Text(cost).font(.scaled(12, weight: .medium)).monospacedDigit() }
            if row.unpriced {
                Button("Unpriced · Map") { mapping = row }
                    .buttonStyle(.plain).font(.scaled(11, weight: .semibold)).foregroundStyle(.orange)
                    .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(Color.orange.opacity(0.15)))
                    .help("This model is not in the price table: its cost is missing, not zero. Map it to a price.")
            } else if row.overridden {
                Button { mapping = row } label: { Label("Custom", systemImage: "pencil") }
                    .buttonStyle(.plain).font(.scaled(11, weight: .semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(Color.primary.opacity(0.08)))
                    .help("You set this model's price. Edit or clear it.")
            }
        }
    }

    private func workspaceTable(_ snapshot: UsageSnapshot) -> some View {
        let rows = usageWorkspaceRows(snapshot)
        return VStack(alignment: .leading, spacing: 6) {
            Text("By workspace & source").sectionLabel()
            SettingsTabCard {
                if rows.isEmpty { emptyRow("No workspaces used") }
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { SettingsDivider() }
                    HStack(spacing: 12) {
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
            }
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 14)
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

    var body: some View {
        // one label in a few, so thirty days do not run into each other
        let step = max(1, Int((Double(bars.count) / 7).rounded(.up)))
        let titles = usageChartProviders.map(usageProviderTitle)
        let valueName: String = metric == .cost ? "Cost" : "Tokens"
        Chart {
            ForEach(bars) { bar in
                ForEach(bar.segments) { segment in
                    let dimmed: Bool = shown != nil && shown?.id != bar.id
                    let provider: String = usageProviderTitle(segment.provider)
                    BarMark(x: .value("Day", bar.label), y: .value(valueName, segment.value))
                        .foregroundStyle(by: .value("Provider", provider))
                        .opacity(dimmed ? 0.45 : 1)
                }
            }
            if let shown {
                RuleMark(x: .value("Day", shown.label)).foregroundStyle(Color.secondary.opacity(0.25))
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) { Tooltip(tooltip: usageTooltip(shown, metric: metric)) }
            }
        }
        .chartForegroundStyleScale(domain: titles, range: titles.map { providerColors[$0] ?? .gray })
        .chartXAxis { AxisMarks(values: bars.enumerated().filter { $0.offset % step == 0 }.map(\.element.label)) { _ in AxisValueLabel() } }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel { if let amount = value.as(Double.self) { Text(usageFormat(amount, metric)) } }
            }
        }
        .chartLegend(position: .bottom, alignment: .leading)
        .chartOverlay { proxy in
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
        }
        .frame(height: 220)
        .accessibilityLabel("Daily \(metric == .cost ? "cost" : "tokens") by provider")
        .accessibilityValue(shown.map { tip in usageTooltip(tip, metric: metric).lines.map { "\($0.provider) \($0.value)" }.joined(separator: ", ") } ?? "")
    }

    private func day(at point: CGPoint, _ proxy: ChartProxy, _ geometry: GeometryProxy) -> String? {
        guard let frame = proxy.plotFrame else { return nil }
        return proxy.value(atX: point.x - geometry[frame].origin.x, as: String.self)
    }
}

private struct Tooltip: View {
    let tooltip: UsageTooltip

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(tooltip.title).font(.scaled(11, weight: .semibold))
            if tooltip.lines.isEmpty { Text("No usage").font(.scaled(11)).foregroundStyle(.secondary) }
            ForEach(tooltip.lines, id: \.provider) { line in
                HStack(spacing: 8) {
                    Circle().fill(providerColors[line.provider] ?? .gray).frame(width: 7, height: 7)
                    Text(line.provider).font(.scaled(11))
                    Spacer(minLength: 10)
                    Text(line.value).font(.scaled(11)).monospacedDigit()
                }
            }
            if tooltip.lines.count > 1 {
                Divider()
                HStack { Text("Total").font(.scaled(11, weight: .semibold)); Spacer(minLength: 10); Text(tooltip.total).font(.scaled(11, weight: .semibold)).monospacedDigit() }
            }
        }
        .frame(width: 170).padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
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
            if let refusal {
                Label(refusal, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange).textSelection(.enabled)
            }
            HStack {
                Spacer()
                if saving { ProgressView().controlSize(.small) }
                Button("Cancel") { dismiss() }.buttonStyle(SecondaryCapsuleButtonStyle()).keyboardShortcut(.cancelAction)
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
        if let text { Text(text).font(.caption).foregroundStyle(.orange) }
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
