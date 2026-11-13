import Foundation
import Testing
@testable import CarrierCore

// The consumption section of the Usage page: filter combinations, the KPI cards, the stacked chart and its tooltip, the tables and the checks
// of the price override form before `usageOverride` is called.

private let goldenFile = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/chat-usage.json")
private func golden() throws -> UsageSnapshot { try JSONDecoder().decode(UsageSnapshot.self, from: Data(contentsOf: goldenFile)) }

// MARK: filters

@MainActor @Test func everyFilterCombinationIsAskedOfTheHost() async throws {
    let combos: [(UsageMetric, Int, UsageProviderFilter, UsageSourceFilter, String)] = [
        (.cost, 30, .all, .all, ""), (.tokens, 7, .claude, .all, ""), (.cost, 14, .codex, .epic, "web"),
        (.tokens, 30, .agy, .chat, " opus "), (.cost, 7, .local, .external, "qwen"), (.tokens, 14, .all, .epic, "acme/web"),
    ]
    for (metric, days, provider, source, search) in combos {
        let host = try host()
        let store = UsageStore(host: host)
        store.metric = metric
        store.days = days
        store.providerFilter = provider
        store.sourceFilter = source
        store.searchText = search
        await store.load()
        // the metric only changes what the page draws; with a provider on, the quotas of all are asked first
        #expect(host.queries.last == UsageQuery(days: days, provider: provider, source: source, search: search))
        #expect(host.queries.count == (provider == .all ? 1 : 2))
        #expect(store.hasActiveFilters == (provider != .all || source != .all || search.isEmpty == false))
    }
}

@MainActor @Test func clearingTheFiltersLeavesTheMetricAndTheRange() throws {
    let store = UsageStore(host: try host())
    store.metric = .tokens
    store.days = 7
    store.providerFilter = .codex
    store.sourceFilter = .chat
    store.searchText = "x"
    store.clearFilters()
    #expect(store.hasActiveFilters == false && store.metric == .tokens && store.days == 7)
    store.searchText = "   "
    #expect(store.hasActiveFilters == false)
}

// MARK: cards

@Test func theFourCardsSayWhatWasSpentAndWhatIsMissing() throws {
    let kpis = usageKpis(try golden())
    #expect(kpis.map(\.title) == ["Est. API Cost", "Total Tokens", "Local Compute", "Active Epics / Chats"])
    #expect(kpis[0].value == "$46.82" && kpis[0].footnote == "1 unpriced model is not counted")
    // input + cache read + cache write + output; reasoning is a part of output
    #expect(kpis[1].value == "24.9M" && kpis[1].footnote == "318 turns")
    #expect(kpis[2].value == "$0.00" && kpis[2].footnote == "8 local turns")
    #expect(kpis[3].value == "1 / 1")
}

@Test func cardsOfAnEmptyHistoryAreQuiet() throws {
    let empty = try JSONDecoder().decode(UsageSnapshot.self, from: Data(#"{"summary":{}}"#.utf8))
    let kpis = usageKpis(empty)
    #expect(kpis[0].value == "$0.00" && kpis[0].footnote == nil)
    #expect(kpis[1].value == "0" && kpis[2].footnote == "No local models used" && kpis[3].value == "—")
    let full = try golden()
    #expect(usageIsEmpty(empty) && usageIsEmpty(full) == false)
}

@Test func countsAndMoneyAreShort() {
    #expect([0, 999, 1_000, 1_840_000, 21_400_000, 3_200_000_000].map(usageCount) == ["0", "999", "1K", "1.8M", "21.4M", "3.2B"])
    #expect(usageMoney(0) == "$0.00" && usageMoney(0.001) == "<$0.01" && usageMoney(46.8) == "$46.80")
}

// MARK: chart

@Test func theChartStacksTheProvidersOfEachDayInOrder() throws {
    let bars = usageBars(try golden(), metric: .cost)
    #expect(bars.count == 7 && bars[0].label == "Nov 7" && bars[0].date == "2026-11-07")
    // the first days ran no local model; the others did, at $0.00, and still show in the stack
    #expect(bars[0].segments.map(\.provider) == ["claude", "codex", "agy"])
    #expect(bars[6].segments.map(\.provider) == ["claude", "codex", "agy", "local"] && bars[6].segments[3].value == 0)
    // a day that ran nothing is an empty bar, not a missing one
    #expect(bars[3].segments.isEmpty && bars[3].total == 0)
    // the stacks add up to the day
    #expect(abs(bars[6].total - 5.62) < 0.01)
}

@Test func theChartKnowsItsWeekendsAndTheNumbersAreGrouped() throws {
    // 2026-11-07 is a Saturday
    #expect(usageBars(try golden(), metric: .cost).map(\.weekend) == [true, true, false, false, false, false, false])
    #expect(usageGrouped(1_234_567) == "1,234,567" && usageGrouped(999) == "999")
    #expect(usageMoney(1234.5) == "$1,234.50" && usageMoney(31.2) == "$31.20" && usageMoney(0.001) == "<$0.01")
}

@Test func aDrawerGroupsItsRowsUnderTheirHeadings() {
    let rows = [
        UsageLine(title: "Credits", value: "None"), UsageLine(title: "GEMINI", heading: true), UsageLine(title: "Weekly"), UsageLine(title: "5h"),
        UsageLine(title: "CLAUDE", heading: true), UsageLine(title: "Weekly"),
    ]
    let groups = usageLineGroups(rows)
    #expect(groups.map(\.title) == [nil, "GEMINI", "CLAUDE"] && groups.map(\.lines.count) == [1, 2, 1])
}

@Test func theMetricChangesTheHeightsAndNotTheStack() throws {
    let snapshot = try golden()
    let tokens = usageBars(snapshot, metric: .tokens)
    #expect(tokens[6].segments.map(\.provider) == usageBars(snapshot, metric: .cost)[6].segments.map(\.provider))
    #expect(Int(tokens[6].total) == 320_000 + 3_000_000 + 160_000 + 136_000)
}

@Test func theTooltipOfADaySaysEachProviderAndTheTotal() throws {
    let snapshot = try golden()
    let cost = usageTooltip(usageBars(snapshot, metric: .cost)[0], metric: .cost)
    #expect(cost.title == "Nov 7" && cost.weekday == "Saturday" && cost.lines.map(\.provider) == ["Claude", "Codex", "Antigravity"] && cost.total == "$3.10")
    #expect(cost.lines[1].value == "$0.93")
    let tokens = usageTooltip(usageBars(snapshot, metric: .tokens)[6], metric: .tokens)
    #expect(tokens.lines.map(\.provider) == ["Claude", "Codex", "Antigravity", "Local"] && tokens.total == "3.6M")
    #expect(usageTooltip(usageBars(snapshot, metric: .cost)[3], metric: .cost) == UsageTooltip(title: "Nov 10", weekday: "Tuesday", lines: [], total: "$0.00"))
}

@Test func aHostWithoutTheProviderSplitStillDecodes() throws {
    let day = try JSONDecoder().decode(UsageDay.self, from: Data(#"{"date":"2026-11-07","costUsd":1}"#.utf8))
    let snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: Data(#"{"summary":{},"daily":[{"date":"2026-11-07"}]}"#.utf8))
    #expect(day.providers.isEmpty && usageBars(snapshot, metric: .cost)[0].segments.isEmpty)
}

// MARK: tables

@Test func theModelTableMarksWhatNeedsAPrice() throws {
    let rows = usageModelRows(try golden())
    #expect(rows.map(\.model) == ["claude-opus-4-5", "gpt-5-codex", "gemini-4-argon", "my-agent-model", "qwen3:8b"])
    #expect(rows[0].detail == "900K in · 12.6M cache · 380K out" && rows[0].cost == "$31.20")
    // unpriced: no cost at all (it is not $0.00), and the row offers the mapping
    #expect(rows[2].cost == nil && rows[2].unpriced && rows[2].overridden == false)
    #expect(rows[3].overridden && rows[3].unpriced == false)
    #expect(rows[4].cost == "$0.00 · Local" && rows[4].provider == "Local")
}

@Test func theWorkspaceTableGroupsByRepoOrFolderAndSource() throws {
    let rows = usageWorkspaceRows(try golden())
    #expect(rows.map(\.source) == ["Epic", "Chat", "External"])
    #expect(rows.map(\.name) == ["acme/web", "Projects/web", "Projects/scratch"])
    #expect(rows[1].path == "/Users/demo/Projects/web" && rows[0].cost == "$28.40" && rows[0].detail == "15M tokens · 190 turns")
}

@Test func theWorkspaceTableListsTheTopAndTotalsTheWholeRange() throws {
    let snapshot = try golden()
    #expect(usageWorkspaceRows(snapshot, limit: 2).count == 2)
    #expect(usageWorkspaceTotal(snapshot).name == "Total · 3 workspaces")
    #expect(usageWorkspaceTotal(snapshot, limit: 2).name == "Total · 3 workspaces, top 2 by tokens")
    // the total is the range's, not the sum of the rows listed
    #expect(usageWorkspaceTotal(snapshot, limit: 2).cost == usageMoney(snapshot.summary.costUsd))
}

@Test func theWorkspaceTableListsTheMostTokensFirst() throws {
    let tokens = try golden().byWorkspace.map { usageTokenTotal($0.row.tokens) }.sorted(by: >)
    let rows = usageWorkspaceRows(try golden())
    #expect(rows.count == tokens.count)
    #expect(rows.first?.detail.hasPrefix(usageCount(tokens[0])) == true)
}

@Test func theModelTableTotalsTheRangeAndSaysWhatIsLeftOut() throws {
    let total = usageModelTotal(try golden())
    #expect(total.model == "Total · 5 models, 1 unpriced not counted")
    #expect(total.cost == usageMoney(try golden().summary.costUsd))
}

// MARK: override form

private let catalog = ["claude-opus-4-5", "gpt-5-codex"]

@Test func localAndClearNeedNothingElse() {
    #expect(UsageOverrideDraft(mode: .local).check(model: "m", catalog: catalog).override == UsageOverride(model: "m", action: .local))
    #expect(UsageOverrideDraft(mode: .clear).check(model: "m", catalog: catalog).override == UsageOverride(model: "m", action: .clear))
}

@Test func anAliasMustBeAModelOfTheCatalog() {
    var draft = UsageOverrideDraft(mode: .alias)
    #expect(draft.check(model: "m", catalog: catalog).errors == [.alias: "Choose a model"])
    draft.alias = "gpt-6"
    #expect(draft.check(model: "m", catalog: catalog).errors == [.alias: "Not a model of the price table"])
    draft.alias = " gpt-5-codex "
    #expect(draft.check(model: "m", catalog: catalog).override == UsageOverride(model: "m", action: .alias("gpt-5-codex")))
}

@Test func customRatesNeedInputAndOutputAndNothingNegativeOrInfinite() {
    var draft = UsageOverrideDraft(mode: .custom)
    #expect(draft.check(model: "m", catalog: catalog).errors == [.input: "Required", .output: "Required"])
    draft.input = "-1"
    draft.output = "abc"
    draft.cachedInput = "1e999"
    draft.cacheWrite = "20000"
    let bad = draft.check(model: "m", catalog: catalog)
    #expect(bad.override == nil)
    #expect(bad.errors == [.input: "Cannot be negative", .output: "Enter a number, like 1.25", .cachedInput: "Enter a number, like 1.25", .cacheWrite: "At most 10,000"])
    for text in ["nan", "inf", "-inf"] {
        draft.output = text
        #expect(draft.check(model: "m", catalog: catalog).errors[.output] != nil)
    }
}

@Test func validCustomRatesKeepTheOptionalOnesOut() {
    var draft = UsageOverrideDraft(mode: .custom)
    draft.input = "1.5"
    draft.output = " 6 "
    #expect(draft.check(model: "m", catalog: catalog).override == UsageOverride(model: "m", action: .rates(input: 1.5, cachedInput: nil, cacheWrite: nil, output: 6)))
    draft.cachedInput = "0.15"
    draft.cacheWrite = "0"
    #expect(draft.check(model: "m", catalog: catalog).override == UsageOverride(model: "m", action: .rates(input: 1.5, cachedInput: 0.15, cacheWrite: 0, output: 6)))
}

@MainActor @Test func aHostWithoutOverridesIsNotAskedAndSaysWhatToDo() async throws {
    let host = try host()
    host.capabilitiesAnswer = [.usage]
    let refusal = await UsageStore(host: host).override(UsageOverride(model: "m", action: .local))
    #expect(refusal == usageNeedsNewerHost && host.overrides.isEmpty && host.queries.isEmpty)
}
