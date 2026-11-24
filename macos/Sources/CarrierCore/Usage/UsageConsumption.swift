import Foundation

// The consumption section of the Usage page (docs/specs/usage-and-limits.md): the four KPI cards, the stacked daily chart with its tooltip, the
// two tables and the price override form's checks. The host filters the history (days, provider, source, search); everything the view draws
// from its answer, and what is checked before an override is sent, is decided here so it can be tested.

public func usageTokenTotal(_ tokens: UsageTokens) -> Int { tokens.input + tokens.cachedInput + tokens.cacheWrite + tokens.output }

/// `1.8M`, `702K`, `85`: a count of tokens short enough for a card or a table cell.
public func usageCount(_ count: Int) -> String {
    let units: [(Double, String)] = [(1e9, "B"), (1e6, "M"), (1e3, "K")]
    guard let (size, suffix) = units.first(where: { Double(count) >= $0.0 }) else { return String(count) }
    return String(format: "%.1f", Double(count) / size).replacingOccurrences(of: ".0", with: "") + suffix
}

private let english = Locale(identifier: "en_US")

/// A whole number with thousands separators: `1,234`.
public func usageGrouped(_ count: Int) -> String { count.formatted(.number.locale(english)) }

public func usageMoney(_ amount: Double) -> String {
    amount > 0 && amount < 0.005 ? "<$0.01" : "$" + amount.formatted(.number.precision(.fractionLength(2)).locale(english))
}

public let usageChartProviders = ["claude", "codex", "agy", "local"]

public func usageProviderTitle(_ id: String) -> String {
    ["claude": "Claude", "codex": "Codex", "agy": "Antigravity", "local": "Local"][id] ?? id
}

private func usageSourceTitle(_ source: String) -> String { source.prefix(1).uppercased() + source.dropFirst() }

// MARK: KPIs

public struct UsageKpi: Equatable {
    public var title: String
    public var value: String
    public var footnote: String?
}

/// Est. API Cost (with a footnote while models are unpriced: their cost is missing, not zero), Total Tokens, Local Compute and the repos and
/// folders that had epic or chat work (`—` with none).
public func usageKpis(_ snapshot: UsageSnapshot) -> [UsageKpi] {
    let unpriced = snapshot.byModel.filter { $0.costStatus == .unpriced }.count
    let localTurns = snapshot.byModel.filter(\.isLocal).map(\.row.turns).reduce(0, +)
    let epics = snapshot.byWorkspace.filter { $0.source == "epic" }.count
    let chats = snapshot.byWorkspace.filter { $0.source == "chat" }.count
    return [
        UsageKpi(
            title: "Est. API Cost", value: usageMoney(snapshot.summary.costUsd),
            footnote: unpriced > 0 ? "\(unpriced) unpriced \(unpriced == 1 ? "model is" : "models are") not counted" : nil
        ),
        UsageKpi(title: "Total Tokens", value: usageCount(usageTokenTotal(snapshot.summary.tokens)), footnote: "\(usageGrouped(snapshot.summary.turns)) turns"),
        UsageKpi(title: "Local Compute", value: "$0.00", footnote: localTurns > 0 ? "\(usageGrouped(localTurns)) local turns" : "No local models used"),
        UsageKpi(title: "Active Epics / Chats", value: epics + chats == 0 ? "—" : "\(epics) / \(chats)", footnote: "Repos and folders with work"),
    ]
}

// MARK: Chart

public struct UsageSegment: Equatable, Identifiable {
    public var provider: String
    public var value: Double
    public var turns: Int
    public var id: String { provider }
}

/// One day of the chart: the providers that ran that day stacked in the order of `usageChartProviders`, in the metric of the page.
public struct UsageBar: Equatable, Identifiable {
    /// `YYYY-MM-DD`.
    public var date: String
    /// `Nov 7`.
    public var label: String
    public var segments: [UsageSegment]
    public var total: Double
    /// A Saturday or a Sunday: the chart tints its column.
    public var weekend = false
    public var id: String { date }
}

/// 1 is Sunday and 7 Saturday; the date is the host's `YYYY-MM-DD`.
private func weekday(_ date: String) -> Int? {
    let parts = date.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    guard let day = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return nil }
    return calendar.component(.weekday, from: day)
}

private func isWeekend(_ date: String) -> Bool { [1, 7].contains(weekday(date) ?? 0) }

public func usageValue(_ row: UsageRow, _ metric: UsageMetric) -> Double {
    metric == .cost ? row.costUsd : Double(usageTokenTotal(row.tokens))
}

public func usageFormat(_ value: Double, _ metric: UsageMetric) -> String { metric == .cost ? usageMoney(value) : usageCount(Int(value.rounded())) }

private func dayLabel(_ date: String) -> String {
    let parts = date.split(separator: "-")
    let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    guard parts.count == 3, let month = Int(parts[1]), months.indices.contains(month - 1), let day = Int(parts[2]) else { return date }
    return "\(months[month - 1]) \(day)"
}

public func usageBars(_ snapshot: UsageSnapshot, metric: UsageMetric) -> [UsageBar] {
    snapshot.daily.map { day in
        let segments = usageChartProviders.compactMap { provider -> UsageSegment? in
            guard let row = day.providers[provider], row.turns > 0 else { return nil }
            return UsageSegment(provider: provider, value: usageValue(row, metric), turns: row.turns)
        }
        return UsageBar(date: day.date, label: dayLabel(day.date), segments: segments, total: segments.map(\.value).reduce(0, +), weekend: isWeekend(day.date))
    }
}

public struct UsageTooltipLine: Equatable {
    public var provider: String
    public var value: String
}

public struct UsageTooltip: Equatable {
    public var title: String
    /// `Saturday`.
    public var weekday: String
    public var lines: [UsageTooltipLine]
    public var total: String
}

/// What the tooltip of a day says: its providers and their share in the metric, and the total; a day with no work says so in `lines`.
public func usageTooltip(_ bar: UsageBar, metric: UsageMetric) -> UsageTooltip {
    UsageTooltip(
        title: bar.label, weekday: weekday(bar.date).map { ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][$0 - 1] } ?? "",
        lines: bar.segments.map { UsageTooltipLine(provider: usageProviderTitle($0.provider), value: usageFormat($0.value, metric)) },
        total: usageFormat(bar.total, metric)
    )
}

/// Nothing was used in the period (with these filters, if any).
public func usageIsEmpty(_ snapshot: UsageSnapshot) -> Bool { snapshot.summary.turns == 0 }

// MARK: Tables

public struct UsageModelRow: Equatable, Identifiable {
    public var id: String
    public var model: String
    public var provider: String
    /// `1.2M in · 12M cache · 380K out`.
    public var detail: String
    /// `$31.20` or `$0.00 · Local`; nil for an unpriced model, which has no cost to show.
    public var cost: String?
    public var unpriced: Bool
    public var overridden: Bool
}

private func tokenDetail(_ tokens: UsageTokens) -> String {
    "\(usageCount(tokens.input)) in · \(usageCount(tokens.cachedInput + tokens.cacheWrite)) cache · \(usageCount(tokens.output)) out"
}

public func usageModelRows(_ snapshot: UsageSnapshot) -> [UsageModelRow] {
    snapshot.byModel.map { model in
        UsageModelRow(
            id: "\(model.provider)/\(model.model)", model: model.model, provider: usageProviderTitle(model.provider), detail: tokenDetail(model.row.tokens),
            cost: model.costStatus == .unpriced ? nil : model.costStatus == .local ? "$0.00 · Local" : usageMoney(model.row.costUsd),
            unpriced: model.costStatus == .unpriced, overridden: model.overridden
        )
    }
}

public struct UsageWorkspaceRow: Equatable, Identifiable {
    public var id: String
    /// A repository as `owner/repo`, a folder as its last two parts.
    public var name: String
    public var path: String
    /// `Epic`, `Chat` or `External`.
    public var source: String
    public var detail: String
    public var cost: String
}

/// How many workspaces the table lists: the ones that spent the most tokens.
public let usageWorkspaceLimit = 10

public func usageWorkspaceRows(_ snapshot: UsageSnapshot, limit: Int = usageWorkspaceLimit) -> [UsageWorkspaceRow] {
    snapshot.byWorkspace.sorted { (usageTokenTotal($0.row.tokens), $0.row.costUsd) > (usageTokenTotal($1.row.tokens), $1.row.costUsd) }.prefix(limit).map { workspace in
        let parts = workspace.workspace.split(separator: "/", omittingEmptySubsequences: true)
        let name = workspace.workspace.hasPrefix("/") ? parts.suffix(2).joined(separator: "/") : workspace.workspace
        return UsageWorkspaceRow(
            id: "\(workspace.source)/\(workspace.workspace)", name: name.isEmpty ? "Unknown" : name, path: workspace.workspace, source: usageSourceTitle(workspace.source),
            detail: "\(usageCount(usageTokenTotal(workspace.row.tokens))) tokens · \(usageGrouped(workspace.row.turns)) turns", cost: usageMoney(workspace.row.costUsd)
        )
    }
}

/// The foot of the model table: the whole range's tokens and cost, and what the cost leaves out.
public func usageModelTotal(_ snapshot: UsageSnapshot) -> UsageModelRow {
    let count = snapshot.byModel.count
    let unpriced = snapshot.byModel.filter { $0.costStatus == .unpriced }.count
    let title = "Total · \(count) \(count == 1 ? "model" : "models")" + (unpriced > 0 ? ", \(unpriced) unpriced not counted" : "")
    return UsageModelRow(
        id: "total", model: title, provider: "", detail: tokenDetail(snapshot.summary.tokens), cost: usageMoney(snapshot.summary.costUsd), unpriced: false, overridden: false
    )
}

/// The foot of the workspace table: the whole range's numbers, not only the rows listed, and how many workspaces there were.
public func usageWorkspaceTotal(_ snapshot: UsageSnapshot, limit: Int = usageWorkspaceLimit) -> UsageWorkspaceRow {
    let count = snapshot.byWorkspace.count
    let noun = count == 1 ? "workspace" : "workspaces"
    let title = count > limit ? "Total · \(count) workspaces, top \(limit) by tokens" : "Total · \(count) \(noun)"
    return UsageWorkspaceRow(
        id: "total", name: title, path: "", source: "",
        detail: "\(usageCount(usageTokenTotal(snapshot.summary.tokens))) tokens · \(usageGrouped(snapshot.summary.turns)) turns", cost: usageMoney(snapshot.summary.costUsd)
    )
}

// MARK: Price override

/// The form of `Unpriced · Map`, before it is sent: `local` is `$0.00`, `alias` borrows a catalog model's rates, `custom` gives its own,
/// `clear` goes back to the table. The host refuses what this refuses, but a person is told next to the field and keeps what was typed.
public struct UsageOverrideDraft: Equatable {
    public enum Mode: String, CaseIterable { case local, alias, custom, clear }
    public enum Field: Hashable { case alias, input, cachedInput, cacheWrite, output }

    /// The most the host accepts for a rate, in US dollars per million tokens.
    public static let maxRate = 10_000.0

    public var mode: Mode
    public var alias = ""
    public var input = ""
    public var cachedInput = ""
    public var cacheWrite = ""
    public var output = ""

    public init(mode: Mode = .local) { self.mode = mode }

    /// The override to send, or why each field cannot be.
    public func check(model: String, catalog: [String]) -> UsageOverrideCheck {
        var errors: [Field: String] = [:]
        func rate(_ text: String, _ field: Field, required: Bool) -> Double? {
            let text = text.trimmingCharacters(in: .whitespaces)
            if text.isEmpty {
                if required { errors[field] = "Required" }
                return nil
            }
            guard let value = Double(text), value.isFinite else { errors[field] = "Enter a number, like 1.25"; return nil }
            guard value >= 0 else { errors[field] = "Cannot be negative"; return nil }
            guard value <= Self.maxRate else { errors[field] = "At most 10,000"; return nil }
            return value
        }
        let action: UsageOverride.Action?
        switch mode {
        case .local: action = .local
        case .clear: action = .clear
        case .alias:
            let name = alias.trimmingCharacters(in: .whitespaces)
            if catalog.contains(name) { action = .alias(name) } else {
                errors[.alias] = name.isEmpty ? "Choose a model" : "Not a model of the price table"
                action = nil
            }
        case .custom:
            let rates = (rate(input, .input, required: true), rate(cachedInput, .cachedInput, required: false), rate(cacheWrite, .cacheWrite, required: false), rate(output, .output, required: true))
            if errors.isEmpty, let input = rates.0, let output = rates.3 {
                action = .rates(input: input, cachedInput: rates.1, cacheWrite: rates.2, output: output)
            } else { action = nil }
        }
        guard errors.isEmpty, let action else { return UsageOverrideCheck(override: nil, errors: errors) }
        return UsageOverrideCheck(override: UsageOverride(model: model, action: action), errors: [:])
    }
}

public struct UsageOverrideCheck: Equatable {
    public var override: UsageOverride?
    public var errors: [UsageOverrideDraft.Field: String]
}
