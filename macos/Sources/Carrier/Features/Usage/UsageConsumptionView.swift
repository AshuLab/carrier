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
        // the selects have no box, so their words need room of their own: 8 pt between the two segmented controls, 18 pt from them to the selects and between the selects
        HStack(spacing: 18) {
            HStack(spacing: 8) {
                SegmentedChoice(
                    options: [(UsageMetric.cost, "Cost", AppIcon.coin), (.tokens, "Tokens", .hash)], selection: $store.metric
                )
                .accessibilityLabel("Metric")
                SegmentedChoice(options: [7, 14, 30, 90].map { ($0, "\($0)d", nil) }, selection: $store.days).accessibilityLabel("Range")
            }
            ChoicePopUp(
                label: "Provider",
                options: [(.all, "All providers"), (.claude, "Claude"), (.codex, "Codex"), (.agy, "Antigravity"), (.local, "Local")],
                selection: $store.providerFilter
            )
            ChoicePopUp(
                label: "Source", options: [(.all, "All sources"), (.epic, "Epic"), (.chat, "Chat"), (.external, "External")], selection: $store.sourceFilter
            )
            Spacer(minLength: 8)
            TextField("Search model or workspace", text: $store.searchText).settingsField(width: 300, icon: .search)
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
                            icon: .chartBar, title: "Nothing matches these filters", line: "Clear them to see all of the last \(store.days) days.",
                            action: ("Clear filters", { store.clearFilters(); reload() }), actionIcon: .close
                        )
                        .frame(minHeight: 220)
                    } else {
                        EmptyStateView(icon: .chartBar, title: "No usage in the last \(store.days) days", line: "Epics, chats and terminal sessions show here once they run.")
                            .frame(minHeight: 220)
                    }
                } else if bars.contains(where: { $0.total > 0 }) {
                    DailyChart(bars: bars, metric: store.metric)
                } else {
                    // every bar is zero (all the models are unpriced): a chart of zeros draws nothing and looks broken
                    EmptyStateView(
                        icon: .chartBar, title: "No cost to chart",
                        line: "The models used have no price yet, so no cost is counted. Map them below, or look at the tokens.",
                        action: ("Show tokens", { store.metric = .tokens }), actionIcon: .hash
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
                Button { mapping = row } label: { Badge(text: "Unpriced · Map", icon: .warningFilled, tint: .orange) }
                    .buttonStyle(.plain).accessibilityLabel("Unpriced. Map \(row.model) to a price")
                    .help("This model is not in the price table: its cost is missing, not zero. Map it to a price.")
            } else if row.overridden {
                Button { mapping = row } label: { Badge(text: "Custom", icon: .pencil, tint: .secondary) }
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
                        Glyph(sourceSymbol(row.source), size: 13).foregroundStyle(.secondary).frame(width: 20).accessibilityHidden(true)
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
    private func sourceSymbol(_ source: String) -> AppIcon {
        switch source {
        case "Epic": .send
        case "Chat": .messages
        default: .terminal
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text).font(.scaled(12)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 14)
    }
}

/// The foot of a table: the total, on a band of its own that reaches a little past the rows' text so it reads as a sum and not as one more row.
private struct UsageFooter: View {
    let title: String
    let detail: String
    let cost: String

    var body: some View {
        HStack(spacing: 12) {
            Glyph(.sum, size: 13).foregroundStyle(.secondary).frame(width: 20).accessibilityHidden(true)
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
