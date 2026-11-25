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
        VStack(alignment: .leading, spacing: Tokens.Space.s14) {
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
        // the selects have no box, so their words need room of their own: 8 pt between the two segmented controls, 18 pt from them to the selects and between the selects
        HStack(spacing: Tokens.Space.s18) {
            HStack(spacing: Tokens.Space.s8) {
                SegmentedChoice(
                    options: [(UsageMetric.cost, Copy.usageMetricName(metric: .cost), AppIcon.coin), (.tokens, Copy.usageMetricName(metric: .tokens), .hash)],
                    selection: $store.metric
                )
                .accessibilityLabel(Copy.usageFilterMetric())
                SegmentedChoice(options: [7, 14, 30, 90].map { ($0, Copy.usageRangeDays(days: $0), nil) }, selection: $store.days).accessibilityLabel(Copy.usageFilterRange())
            }
            ChoicePopUp(
                label: Copy.usageFilterProvider(),
                options: [
                    (.all, Copy.usageAllProviders()), (.claude, usageProviderTitle("claude")), (.codex, usageProviderTitle("codex")), (.agy, usageProviderTitle("agy")),
                    (.local, usageProviderTitle("local")),
                ],
                selection: $store.providerFilter
            )
            ChoicePopUp(
                label: Copy.usageFilterSource(),
                options: [
                    (.all, Copy.usageAllSources()), (.epic, Copy.usageSourceName(which: .epic)), (.chat, Copy.usageSourceName(which: .chat)),
                    (.external, Copy.usageSourceName(which: .external)),
                ],
                selection: $store.sourceFilter
            )
            Spacer(minLength: 8)
            TextField(Copy.usageSearch(), text: $store.searchText).settingsField(width: 300, icon: .search)
        }
    }

    // MARK: cards

    private func kpis(_ snapshot: UsageSnapshot) -> some View {
        SettingsTabCard {
            HStack(alignment: .top, spacing: Tokens.Space.none) {
                ForEach(Array(usageKpis(snapshot).enumerated()), id: \.offset) { index, kpi in
                    if index > 0 { SettingsDivider(vertical: true).padding(.vertical, Tokens.Space.s12) }
                    VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                        Text(kpi.title).sectionLabel()
                        Text(kpi.value).scaledFont(20, weight: .semibold).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                        // the footnote of the cost is the one that matters: an unpriced model is missing from the number
                        Text(kpi.footnote ?? " ").scaledFont(11).foregroundStyle(kpi.warns ? .orange : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, Tokens.Space.s12).padding(.leading, index > 0 ? Tokens.Space.s14 : Tokens.Space.none)
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
            VStack(alignment: .leading, spacing: Tokens.Space.s8) {
                Text(Copy.usageChartTitle(metric: store.metric == .cost ? .cost : .tokens)).sectionLabel()
                if usageIsEmpty(snapshot) {
                    if store.hasActiveFilters {
                        EmptyStateView(
                            icon: .chartBar, title: Copy.usageNoMatchTitle(), line: Copy.usageNoMatchLine(days: store.days),
                            action: (Copy.usageClearFilters(), { store.clearFilters(); reload() }), actionIcon: .close
                        )
                        .frame(minHeight: 220)
                    } else {
                        EmptyStateView(icon: .chartBar, title: Copy.usageNoUsageTitle(days: store.days), line: Copy.usageNoUsageLine())
                            .frame(minHeight: 220)
                    }
                } else if bars.contains(where: { $0.total > 0 }) {
                    DailyChart(bars: bars, metric: store.metric)
                } else {
                    // every bar is zero (all the models are unpriced): a chart of zeros draws nothing and looks broken
                    EmptyStateView(
                        icon: .chartBar, title: Copy.usageNoCostTitle(), line: Copy.usageNoCostLine(),
                        action: (Copy.usageShowTokens(), { store.metric = .tokens }), actionIcon: .hash
                    )
                    .frame(minHeight: 220)
                }
            }
            .padding(.vertical, Tokens.Space.s12)
        }
    }

    // MARK: tables

    private func modelTable(_ snapshot: UsageSnapshot) -> some View {
        let rows = usageModelRows(snapshot)
        return VStack(alignment: .leading, spacing: Tokens.Space.s6) {
            Text(Copy.usageByModel()).sectionLabel().padding(.leading, Tokens.Space.s14)
            SettingsTabCard {
                if rows.isEmpty { emptyRow(Copy.usageNoModels()) }
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { SettingsDivider() }
                    HStack(spacing: Tokens.Space.s12) {
                        UsageProviderMark(title: row.provider, size: 16).frame(width: 20)
                        VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                            Text(row.model).scaledFont(12, weight: .medium).lineLimit(1).truncationMode(.middle)
                            Text(row.provider).scaledFont(11).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text(row.detail).scaledFont(11).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                        costCell(row).frame(width: 150, alignment: .trailing)
                    }
                    .padding(.vertical, Tokens.Space.s10).frame(minHeight: 40)
                }
                if rows.isEmpty == false {
                    let total = usageModelTotal(snapshot)
                    UsageFooter(title: total.model, detail: total.detail, cost: total.cost ?? "")
                }
            }
        }
    }

    @ViewBuilder private func costCell(_ row: UsageModelRow) -> some View {
        HStack(spacing: Tokens.Space.s6) {
            if let cost = row.cost { Text(cost).scaledFont(12, weight: .medium).monospacedDigit() }
            if row.unpriced {
                Button { mapping = row } label: { Badge(text: Copy.usageUnpricedMap(), icon: .warningFilled, tint: .orange) }
                    .buttonStyle(.plain).accessibilityLabel(Copy.usageUnpricedLabel(model: row.model))
                    .help(Copy.usageUnpricedHelp())
            } else if row.overridden {
                Button { mapping = row } label: { Badge(text: Copy.usageCustom(), icon: .pencil, tint: .secondary) }
                    .buttonStyle(.plain).accessibilityLabel(Copy.usageCustomLabel(model: row.model))
                    .help(Copy.usageCustomHelp())
            }
        }
    }

    private func workspaceTable(_ snapshot: UsageSnapshot) -> some View {
        let rows = usageWorkspaceRows(snapshot)
        return VStack(alignment: .leading, spacing: Tokens.Space.s6) {
            Text(Copy.usageByWorkspace()).sectionLabel().padding(.leading, Tokens.Space.s14)
            SettingsTabCard {
                if rows.isEmpty { emptyRow(Copy.usageNoWorkspaces()) }
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { SettingsDivider() }
                    HStack(spacing: Tokens.Space.s12) {
                        Glyph(sourceSymbol(row.sourceKind), size: 13).foregroundStyle(.secondary).frame(width: 20).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                            Text(row.name).scaledFont(12, weight: .medium).lineLimit(1).truncationMode(.middle).help(row.path)
                            Text(row.source).scaledFont(11).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text(row.detail).scaledFont(11).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                        Text(row.cost).scaledFont(12, weight: .medium).monospacedDigit().frame(width: 150, alignment: .trailing)
                    }
                    .padding(.vertical, Tokens.Space.s10).frame(minHeight: 40)
                }
                if rows.isEmpty == false {
                    let total = usageWorkspaceTotal(snapshot)
                    UsageFooter(title: total.name, detail: total.detail, cost: total.cost)
                }
            }
        }
    }

    /// The sidebar's own symbols: Carrier's epics, the chat's bubbles, a terminal for what ran outside both.
    private func sourceSymbol(_ source: String) -> AppIcon {
        switch source {
        case "epic": .send
        case "chat": .messages
        default: .terminal
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text).scaledFont(12).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, Tokens.Space.s14)
    }
}

/// The foot of a table: the total, on a band of its own that reaches a little past the rows' text so it reads as a sum and not as one more row.
private struct UsageFooter: View {
    let title: String
    let detail: String
    let cost: String

    var body: some View {
        HStack(spacing: Tokens.Space.s12) {
            Glyph(.sum, size: 13).foregroundStyle(.secondary).frame(width: 20).accessibilityHidden(true)
            Text(title).scaledFont(12, weight: .semibold).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 8)
            Text(detail).scaledFont(11).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
            Text(cost).scaledFont(13, weight: .semibold).monospacedDigit().frame(width: 150, alignment: .trailing)
        }
        .padding(.vertical, Tokens.Space.s10).padding(.horizontal, Tokens.Space.s8).frame(minHeight: 40)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.tile).fill(Color.primary.opacity(0.07)))
        .padding(.horizontal, -Tokens.Space.s8).padding(.vertical, Tokens.Space.s8)
        .accessibilityElement(children: .combine)
    }
}
