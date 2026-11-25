import Foundation

// The consumption section of the Usage page (docs/specs/usage-and-limits.md): the four KPI cards, the stacked daily chart with its tooltip, the
// two tables and the price override form's checks. The host filters the history (days, provider, source, search); everything the view draws
// from its answer, and what is checked before an override is sent, is decided here so it can be tested.

public func usageTokenTotal(_ tokens: UsageTokens) -> Int { tokens.input + tokens.cachedInput + tokens.cacheWrite + tokens.output }

/// `1.8M`, `702K`, `85`: a count of tokens short enough for a card or a table cell, with the decimal mark of the locale.
public func usageCount(_ count: Int, bundle: Bundle? = nil, locale: Locale = .current) -> String {
    let units: [(Double, Copy.UsageCountUnit)] = [(1e9, .billion), (1e6, .million), (1e3, .thousand)]
    guard let (size, unit) = units.first(where: { Double(count) >= $0.0 }) else { return String(count) }
    var number = String(format: "%.1f", locale: locale, Double(count) / size)
    let whole = (locale.decimalSeparator ?? ".") + "0"
    if number.hasSuffix(whole) { number.removeLast(whole.count) }
    return number + Copy.usageCountUnit(which: unit, bundle: bundle, locale: locale)
}

/// A whole number with the thousands separators of the locale: `1,234`.
public func usageGrouped(_ count: Int, locale: Locale = .current) -> String { count.formatted(.number.locale(locale)) }

/// `$31.20`, `$1,234.50`, `<$0.01` for what is more than nothing and less than a cent.
public func usageMoney(_ amount: Double, locale: Locale = .current) -> String {
    func dollars(_ amount: Double) -> String { "$" + amount.formatted(.number.precision(.fractionLength(2)).locale(locale)) }
    return amount > 0 && amount < 0.005 ? "<" + dollars(0.01) : dollars(amount)
}

public let usageChartProviders = ["claude", "codex", "agy", "local"]

/// A provider's name: the brands are the same in every language, `Local` is told in the app's. An id this app does not know is its own name.
public func usageProviderTitle(_ id: String, bundle: Bundle? = nil, locale: Locale = .current) -> String {
    switch id {
    case "claude": Copy.usageProviderName(which: .claude, bundle: bundle, locale: locale)
    case "codex": Copy.usageProviderName(which: .codex, bundle: bundle, locale: locale)
    case "agy": Copy.usageProviderName(which: .agy, bundle: bundle, locale: locale)
    case "local": Copy.usageProviderName(which: .local, bundle: bundle, locale: locale)
    default: id
    }
}

/// `Epic`, `Chat` or `External` in the app's language; a source this app does not know is its own name, capitalized.
private func usageSourceTitle(_ source: String, bundle: Bundle?, locale: Locale) -> String {
    switch source {
    case "epic": Copy.usageSourceName(which: .epic, bundle: bundle, locale: locale)
    case "chat": Copy.usageSourceName(which: .chat, bundle: bundle, locale: locale)
    case "external": Copy.usageSourceName(which: .external, bundle: bundle, locale: locale)
    default: capitalizingFirst(source)
    }
}

// MARK: KPIs

public struct UsageKpi: Equatable {
    public var title: String
    public var value: String
    public var footnote: String?
    /// The footnote says that the number is missing something (the unpriced models of the cost): it is drawn in orange.
    public var warns = false
}

/// Est. API Cost (with a footnote while models are unpriced: their cost is missing, not zero), Total Tokens, Local Compute and the repos and
/// folders that had epic or chat work (`—` with none).
public func usageKpis(_ snapshot: UsageSnapshot, bundle: Bundle? = nil, locale: Locale = .current) -> [UsageKpi] {
    let unpriced = snapshot.byModel.filter { $0.costStatus == .unpriced }.count
    let localTurns = snapshot.byModel.filter(\.isLocal).map(\.row.turns).reduce(0, +)
    let epics = snapshot.byWorkspace.filter { $0.source == "epic" }.count
    let chats = snapshot.byWorkspace.filter { $0.source == "chat" }.count
    return [
        UsageKpi(
            title: Copy.usageKpiCost(bundle: bundle, locale: locale), value: usageMoney(snapshot.summary.costUsd, locale: locale),
            footnote: unpriced > 0 ? Copy.usageKpiUnpriced(count: unpriced, bundle: bundle, locale: locale) : nil, warns: unpriced > 0
        ),
        UsageKpi(
            title: Copy.usageKpiTokens(bundle: bundle, locale: locale), value: usageCount(usageTokenTotal(snapshot.summary.tokens), bundle: bundle, locale: locale),
            footnote: Copy.usageTurns(count: snapshot.summary.turns, bundle: bundle, locale: locale)
        ),
        UsageKpi(
            title: Copy.usageKpiLocal(bundle: bundle, locale: locale), value: usageMoney(0, locale: locale),
            footnote: localTurns > 0 ? Copy.usageLocalTurns(count: localTurns, bundle: bundle, locale: locale) : Copy.usageNoLocalModels(bundle: bundle, locale: locale)
        ),
        UsageKpi(
            title: Copy.usageKpiActive(bundle: bundle, locale: locale), value: epics + chats == 0 ? "—" : "\(epics) / \(chats)",
            footnote: Copy.usageKpiWork(bundle: bundle, locale: locale)
        ),
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
    /// `Nov 7`, in the person's language.
    public var label: String
    public var segments: [UsageSegment]
    public var total: Double
    /// A Saturday or a Sunday: the chart tints its column.
    public var weekend = false
    public var id: String { date }
}

private let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    return calendar
}()

/// The host's `YYYY-MM-DD` as its day in UTC, where the host counted it.
private func day(_ date: String) -> Date? {
    let parts = date.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    return utcCalendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
}

/// 1 is Sunday and 7 Saturday; the date is the host's `YYYY-MM-DD`.
private func weekday(_ date: String) -> Int? { day(date).map { utcCalendar.component(.weekday, from: $0) } }

/// A formatter of `template` ("MMMd", "EEEE") for the days of `day(_:)`, in `locale`.
private func dayFormatter(_ template: String, locale: Locale) -> DateFormatter {
    let formatter = DateFormatter()
    (formatter.locale, formatter.calendar, formatter.timeZone) = (locale, utcCalendar, utcCalendar.timeZone)
    formatter.setLocalizedDateFormatFromTemplate(template)
    return formatter
}

private func isWeekend(_ date: String) -> Bool { [1, 7].contains(weekday(date) ?? 0) }

public func usageValue(_ row: UsageRow, _ metric: UsageMetric) -> Double {
    metric == .cost ? row.costUsd : Double(usageTokenTotal(row.tokens))
}

public func usageFormat(_ value: Double, _ metric: UsageMetric, bundle: Bundle? = nil, locale: Locale = .current) -> String {
    metric == .cost ? usageMoney(value, locale: locale) : usageCount(Int(value.rounded()), bundle: bundle, locale: locale)
}

public func usageBars(_ snapshot: UsageSnapshot, metric: UsageMetric, locale: Locale = .current) -> [UsageBar] {
    let dayLabel = dayFormatter("MMMd", locale: locale)
    return snapshot.daily.map { daily in
        let segments = usageChartProviders.compactMap { provider -> UsageSegment? in
            guard let row = daily.providers[provider], row.turns > 0 else { return nil }
            return UsageSegment(provider: provider, value: usageValue(row, metric), turns: row.turns)
        }
        let label = day(daily.date).map(dayLabel.string(from:)) ?? daily.date
        return UsageBar(date: daily.date, label: label, segments: segments, total: segments.map(\.value).reduce(0, +), weekend: isWeekend(daily.date))
    }
}

public struct UsageTooltipLine: Equatable {
    /// The provider's name in the app's language.
    public var provider: String
    /// The host's own name of the provider (`claude`, `codex`, `agy`, `local`), which is what the view draws its color by.
    public var providerId: String
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
public func usageTooltip(_ bar: UsageBar, metric: UsageMetric, bundle: Bundle? = nil, locale: Locale = .current) -> UsageTooltip {
    let weekdayName = dayFormatter("EEEE", locale: locale)
    return UsageTooltip(
        title: bar.label, weekday: day(bar.date).map(weekdayName.string(from:)) ?? "",
        lines: bar.segments.map {
            UsageTooltipLine(provider: usageProviderTitle($0.provider, bundle: bundle, locale: locale), providerId: $0.provider, value: usageFormat($0.value, metric, bundle: bundle, locale: locale))
        },
        total: usageFormat(bar.total, metric, bundle: bundle, locale: locale)
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

private func tokenDetail(_ tokens: UsageTokens, bundle: Bundle?, locale: Locale) -> String {
    Copy.usageTokenDetail(
        input: usageCount(tokens.input, bundle: bundle, locale: locale), cache: usageCount(tokens.cachedInput + tokens.cacheWrite, bundle: bundle, locale: locale),
        output: usageCount(tokens.output, bundle: bundle, locale: locale), bundle: bundle, locale: locale)
}

public func usageModelRows(_ snapshot: UsageSnapshot, bundle: Bundle? = nil, locale: Locale = .current) -> [UsageModelRow] {
    snapshot.byModel.map { model in
        let cost: String?
        switch model.costStatus {
        case .unpriced: cost = nil
        case .local: cost = Copy.usageCostLocal(cost: usageMoney(0, locale: locale), bundle: bundle, locale: locale)
        case .priced: cost = usageMoney(model.row.costUsd, locale: locale)
        }
        return UsageModelRow(
            id: "\(model.provider)/\(model.model)", model: model.model, provider: usageProviderTitle(model.provider, bundle: bundle, locale: locale),
            detail: tokenDetail(model.row.tokens, bundle: bundle, locale: locale), cost: cost, unpriced: model.costStatus == .unpriced, overridden: model.overridden
        )
    }
}

public struct UsageWorkspaceRow: Equatable, Identifiable {
    public var id: String
    /// A repository as `owner/repo`, a folder as its last two parts.
    public var name: String
    public var path: String
    /// `Epic`, `Chat` or `External`, in the app's language.
    public var source: String
    /// The host's own name of the source (`epic`, `chat`, `external`), which is what the view draws its symbol by.
    public var sourceKind: String
    public var detail: String
    public var cost: String
}

/// How many workspaces the table lists: the ones that spent the most tokens.
public let usageWorkspaceLimit = 10

public func usageWorkspaceRows(_ snapshot: UsageSnapshot, limit: Int = usageWorkspaceLimit, bundle: Bundle? = nil, locale: Locale = .current) -> [UsageWorkspaceRow] {
    snapshot.byWorkspace.sorted { (usageTokenTotal($0.row.tokens), $0.row.costUsd) > (usageTokenTotal($1.row.tokens), $1.row.costUsd) }.prefix(limit).map { workspace in
        let parts = workspace.workspace.split(separator: "/", omittingEmptySubsequences: true)
        let name = workspace.workspace.hasPrefix("/") ? parts.suffix(2).joined(separator: "/") : workspace.workspace
        return UsageWorkspaceRow(
            id: "\(workspace.source)/\(workspace.workspace)", name: name.isEmpty ? Copy.usageUnknown(bundle: bundle, locale: locale) : name, path: workspace.workspace,
            source: usageSourceTitle(workspace.source, bundle: bundle, locale: locale), sourceKind: workspace.source,
            detail: Copy.usageTokensTurns(
                tokens: usageCount(usageTokenTotal(workspace.row.tokens), bundle: bundle, locale: locale), turns: workspace.row.turns, bundle: bundle, locale: locale),
            cost: usageMoney(workspace.row.costUsd, locale: locale)
        )
    }
}

/// The foot of the model table: the whole range's tokens and cost, and what the cost leaves out.
public func usageModelTotal(_ snapshot: UsageSnapshot, bundle: Bundle? = nil, locale: Locale = .current) -> UsageModelRow {
    let count = snapshot.byModel.count
    let unpriced = snapshot.byModel.filter { $0.costStatus == .unpriced }.count
    let title = unpriced > 0
        ? Copy.usageTotalModelsUnpriced(count: count, unpriced: unpriced, bundle: bundle, locale: locale) : Copy.usageTotalModels(count: count, bundle: bundle, locale: locale)
    return UsageModelRow(
        id: "total", model: title, provider: "", detail: tokenDetail(snapshot.summary.tokens, bundle: bundle, locale: locale),
        cost: usageMoney(snapshot.summary.costUsd, locale: locale), unpriced: false, overridden: false
    )
}

/// The foot of the workspace table: the whole range's numbers, not only the rows listed, and how many workspaces there were.
public func usageWorkspaceTotal(_ snapshot: UsageSnapshot, limit: Int = usageWorkspaceLimit, bundle: Bundle? = nil, locale: Locale = .current) -> UsageWorkspaceRow {
    let count = snapshot.byWorkspace.count
    let title = count > limit
        ? Copy.usageTotalWorkspacesTop(count: count, limit: limit, bundle: bundle, locale: locale) : Copy.usageTotalWorkspaces(count: count, bundle: bundle, locale: locale)
    return UsageWorkspaceRow(
        id: "total", name: title, path: "", source: "", sourceKind: "",
        detail: Copy.usageTokensTurns(
            tokens: usageCount(usageTokenTotal(snapshot.summary.tokens), bundle: bundle, locale: locale), turns: snapshot.summary.turns, bundle: bundle, locale: locale),
        cost: usageMoney(snapshot.summary.costUsd, locale: locale)
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

    /// The override to send, or why each field cannot be, in the words of `bundle` and `locale`.
    public func check(model: String, catalog: [String], bundle: Bundle? = nil, locale: Locale = .current) -> UsageOverrideCheck {
        var errors: [Field: String] = [:]
        func rate(_ text: String, _ field: Field, required: Bool) -> Double? {
            let text = text.trimmingCharacters(in: .whitespaces)
            if text.isEmpty {
                if required { errors[field] = Copy.usageErrorRequired(bundle: bundle, locale: locale) }
                return nil
            }
            guard let value = Double(text), value.isFinite else { errors[field] = Copy.usageErrorNumber(bundle: bundle, locale: locale); return nil }
            guard value >= 0 else { errors[field] = Copy.usageErrorNegative(bundle: bundle, locale: locale); return nil }
            guard value <= Self.maxRate else { errors[field] = Copy.usageErrorMax(max: Int(Self.maxRate), bundle: bundle, locale: locale); return nil }
            return value
        }
        let action: UsageOverride.Action?
        switch mode {
        case .local: action = .local
        case .clear: action = .clear
        case .alias:
            let name = alias.trimmingCharacters(in: .whitespaces)
            if catalog.contains(name) { action = .alias(name) } else {
                errors[.alias] = name.isEmpty ? Copy.usageErrorChoose(bundle: bundle, locale: locale) : Copy.usageErrorNotCatalog(bundle: bundle, locale: locale)
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
