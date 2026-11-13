import Foundation

// The live quota list of the Usage page (docs/specs/usage-and-limits.md): the host's quotas pooled by provider, each with its meters, its
// earliest reset and the rows of its drawer. Everything the view draws is decided here, from the quotas and a clock, so it can be tested.

public enum QuotaKind: String, Equatable { case fiveHour = "5h", weekly = "Weekly" }

/// Which of the two rolling windows a window is. The providers name them differently (`5h` and `7d`, `Five Hour Limit Remaining`); a window of
/// neither (Claude's `7d Opus`) is nil.
public func quotaKind(_ window: UsageWindow) -> QuotaKind? {
    let text = window.label.lowercased()
    if text.hasSuffix("5h") || text.contains("five hour") { return .fiveHour }
    if text.hasSuffix("7d") || text.contains("week") { return .weekly }
    return nil
}

/// A meter's track as shares of its width: `solid` is the use that stays after the next reset, `hatched` the use that the earliest reset gives
/// back (the preview of the refill). Both are in [0, 1] and together never pass 1.
public struct MeterShape: Equatable {
    public var solid: Double
    public var hatched: Double
    public var used: Double { solid + hatched }

    public init(solid: Double = 0, hatched: Double = 0) {
        self.solid = min(max(solid, 0), 1)
        self.hatched = min(max(hatched, 0), 1 - self.solid)
    }
}

/// The meter of one or more windows pooled: the mean use, and as hatched the share of it that belongs to the windows that reset first.
/// A window with no time (only the provider's words) never counts as refilling.
public func meterShape(_ windows: [UsageWindow]) -> MeterShape {
    guard windows.isEmpty == false else { return MeterShape() }
    func share(_ window: UsageWindow) -> Double { min(max(window.usedPercent / 100, 0), 1) / Double(windows.count) }
    let used = windows.map(share).reduce(0, +)
    let refilling = windows.compactMap(\.resetsAt).min().map { next in windows.filter { $0.resetsAt == next }.map(share).reduce(0, +) } ?? 0
    return MeterShape(solid: used - refilling, hatched: refilling)
}

public enum UsageMark: Equatable { case ok, warning, failure }

/// A row of a drawer. A heading only has a title; a text row has a value and perhaps a detail; a meter row has a shape and a reset.
public struct UsageLine: Equatable {
    public var title: String
    public var value: String?
    public var detail: String?
    public var shape: MeterShape?
    public var reset: String?
    public var heading = false
}

/// The rows of a drawer between two headings: the heading's title (none for rows before the first one) and what is under it.
public struct UsageLineGroup: Equatable {
    public var title: String?
    public var lines: [UsageLine]
}

public func usageLineGroups(_ lines: [UsageLine]) -> [UsageLineGroup] {
    var groups: [UsageLineGroup] = []
    for line in lines {
        if line.heading { groups.append(UsageLineGroup(title: line.title, lines: [])) } else if groups.isEmpty {
            groups.append(UsageLineGroup(title: nil, lines: [line]))
        } else {
            groups[groups.count - 1].lines.append(line)
        }
    }
    return groups
}

public struct UsageAccountRow: Equatable, Identifiable {
    public var id: String
    public var title: String
    /// `Max plan`, `Signed out`, `Rate limited`...
    public var status: String
    public var mark: UsageMark
    public var stale: Bool
    /// Why the status is not ok, in the host's words.
    public var note: String?
    public var canSignIn: Bool
    public var lines: [UsageLine]
}

public struct UsageMeter: Equatable {
    public var kind: QuotaKind
    public var shape: MeterShape
}

public struct UsageProviderRow: Equatable, Identifiable {
    /// The provider's name for the filter: `claude`, `codex`, `agy` or `local`.
    public var id: String
    public var title: String
    public var subtitle: String
    public var mark: UsageMark
    public var stale: Bool
    /// The pooled `5h` and `Weekly` meters; none for the local servers or an account with no windows.
    public var meters: [UsageMeter]
    /// The earliest known reset still ahead, as `Resets in 2h 14m`.
    public var earliestReset: String?
    public var accounts: [UsageAccountRow]
}

private let providerTitles = [("claude", "Claude"), ("codex", "Codex"), ("agy", "Antigravity"), ("local", "Local Servers")]
private let serverTitles = ["lmstudio": ("LM Studio", "localhost:1234"), "ollama": ("Ollama", "localhost:11434")]

/// `Resets in 2h 14m`, the provider's own words when it gave no time, nil when the time has passed or there is none.
public func resetText(resetsAt: Int?, label: String?, now: Int) -> String? {
    if let resetsAt { return resetsAt > now ? "Resets in \(formatDuration(resetsAt - now))" : nil }
    return label
}

private func mark(_ quota: UsageQuota) -> UsageMark {
    switch quota.status {
    case .signedOut, .error: .failure
    case .missing, .unavailable, .rateLimited: .warning
    case .ok: quota.stale ? .warning : .ok
    }
}

private func statusWords(_ quota: UsageQuota) -> String {
    switch quota.status {
    case .ok: quota.planType.map { "\($0.prefix(1).uppercased() + $0.dropFirst()) plan" } ?? (quota.stale ? "Last known numbers" : "Ready")
    case .signedOut: "Signed out"
    case .missing: "Not set up"
    case .unavailable: "Unavailable"
    case .rateLimited: "Rate limited"
    case .error: "Check failed"
    }
}

private func dollars(_ amount: Double) -> String { String(format: "$%.2f", amount) }

private func meterLine(_ title: String, _ windows: [UsageWindow], now: Int) -> UsageLine {
    let shape = meterShape(windows)
    let percent = min(max(windows.map(\.usedPercent).reduce(0, +) / Double(max(windows.count, 1)), 0), 100)
    let first = windows.compactMap(\.resetsAt).min()
    return UsageLine(
        title: title, value: "\(Int(percent.rounded()))%", shape: shape,
        reset: resetText(resetsAt: first, label: first == nil ? windows.compactMap(\.resetLabel).first : nil, now: now)
    )
}

private func lines(_ quota: UsageQuota, now: Int) -> [UsageLine] {
    var rows: [UsageLine] = []
    func titled(_ window: UsageWindow) -> String { quotaKind(window)?.rawValue ?? window.label }
    func add(_ windows: [UsageWindow], title: (UsageWindow) -> String) {
        windows.forEach { rows.append(meterLine(title($0), [$0], now: now)) }
    }
    switch quota.provider {
    case "claude", "codex":
        let main = quota.windows.filter { $0.group == nil && quotaKind($0) != nil }
        let rest = quota.windows.filter { main.contains($0) == false }
        add(main, title: titled)
        // Claude's model-scoped windows, Codex's `rateLimitsByLimitId`: each under its own name, never in the main meters
        if rest.isEmpty == false {
            rows.append(UsageLine(title: quota.provider == "claude" ? "By model" : "Other limits", heading: true))
            add(rest) { $0.label }
        }
        if let extra = quota.extraUsage {
            let spend = extra.isEnabled
                ? [extra.usedCreditsUsd.map(dollars), extra.monthlyLimitUsd.map { "of \(dollars($0)) a month" }].compactMap { $0 }.joined(separator: " ")
                : "Off"
            rows.append(UsageLine(title: "Extra usage", value: spend.isEmpty ? "On" : spend))
        }
        if let credits = quota.credits {
            rows.append(UsageLine(title: "Credits", value: credits.unlimited ? "Unlimited" : credits.balance ?? (credits.hasCredits ? "Available" : "None")))
        }
        if let reset = quota.rateLimitResetCredits { rows.append(UsageLine(title: "Reset credits", value: "\(reset.availableCount) available")) }
    case "agy":
        var groups: [String] = []
        for window in quota.windows where groups.contains(window.group ?? "") == false { groups.append(window.group ?? "") }
        for group in groups {
            if group.isEmpty == false { rows.append(UsageLine(title: group, heading: true)) }
            add(quota.windows.filter { ($0.group ?? "") == group }) { quotaKind($0)?.rawValue ?? $0.label.replacingOccurrences(of: "\(group) · ", with: "") }
        }
        if let notice = quota.aiCreditsNotice { rows.append(UsageLine(title: notice)) }
    default:
        for server in quota.servers {
            let (title, address) = serverTitles[server.kind] ?? (server.kind, "")
            let models = server.models.isEmpty ? "No model loaded" : "Loaded: " + server.models.joined(separator: ", ")
            rows.append(UsageLine(title: title, value: server.running ? "Ready" : "Not running", detail: server.running ? "\(address) · \(models)" : address))
        }
        rows.append(UsageLine(title: "$0 local compute"))
    }
    return rows
}

/// The providers of the list, in the order Claude, Codex, Antigravity, Local Servers; one with no quota is not in it.
public func usageProviders(_ quotas: [UsageQuota], now: Int) -> [UsageProviderRow] {
    providerTitles.compactMap { id, title in
        let own = quotas.filter { $0.provider == id }
        guard own.isEmpty == false else { return nil }
        let accounts = own.map { quota in
            UsageAccountRow(
                id: quota.account, title: quota.displayName ?? (id == "local" ? "Local servers" : quota.account), status: statusWords(quota), mark: mark(quota),
                stale: quota.stale, note: quota.status == .ok && quota.stale == false ? nil : quota.message,
                canSignIn: quota.status == .signedOut && id != "local", lines: lines(quota, now: now)
            )
        }
        // the 5h and Weekly of every account (every pool, for Antigravity) pooled; a window of a model or a limit id has its own row below
        let pooled = own.flatMap(\.windows).filter { ($0.group == nil || id == "agy") && $0.group != "model_scoped" }
        let meters = [QuotaKind.fiveHour, .weekly].compactMap { kind -> UsageMeter? in
            let windows = pooled.filter { quotaKind($0) == kind }
            return windows.isEmpty ? nil : UsageMeter(kind: kind, shape: meterShape(windows))
        }
        let next = own.flatMap(\.windows).compactMap(\.resetsAt).filter { $0 > now }.min()
        let running = own.flatMap(\.servers).filter(\.running).count
        let problem = accounts.first { $0.mark != .ok }
        let subtitle = id == "local" ? "\(running) of \(own.flatMap(\.servers).count) running"
            : accounts.count == 1 ? accounts[0].status : "\(accounts.count) accounts" + (problem.map { " · \($0.status.lowercased())" } ?? "")
        return UsageProviderRow(
            id: id, title: title, subtitle: subtitle, mark: accounts.contains { $0.mark == .failure } ? .failure : problem == nil ? .ok : .warning,
            stale: accounts.contains(where: \.stale), meters: meters, earliestReset: resetText(resetsAt: next, label: nil, now: now), accounts: accounts
        )
    }
}

extension UsageProviderFilter {
    /// A click on a provider's row: its filter, or all again when it already is.
    public func toggled(_ provider: UsageProviderFilter) -> UsageProviderFilter { self == provider ? .all : provider }
}

/// Whether an epic entered the usage-limit stop between two snapshots. The first snapshot after a connect is a state, not an entry.
public func usageLimitEntered(from old: ConnectionState?, to new: ConnectionState?) -> Bool {
    guard case .running(let before)? = old, case .running(let after)? = new else { return false }
    func stopped(_ snapshot: PanelSnapshot) -> Set<String> {
        Set(snapshot.epics.filter { $0.status == .needsHuman && $0.needsHumanKind == "usage_limit" }.map { "\($0.repo)#\($0.issue)" })
    }
    return stopped(after).isSubset(of: stopped(before)) == false
}

/// Whether a failed turn of a chat session says a quota ran out: the host passes the provider's words on, with no kind of their own.
public func isQuotaError(_ text: String) -> Bool {
    let text = text.lowercased()
    return ["usage limit", "rate limit", "session limit", "quota", "limit reached", "hit your limit"].contains { text.contains($0) }
}

/// Whether the rows hold a quota error that the rows before did not. A conversation that was empty is only being loaded, not failing.
public func quotaErrorAppeared(from old: [FeedRow], to new: [FeedRow]) -> Bool {
    guard old.isEmpty == false else { return false }
    let known = Set(old.map(\.id))
    return new.contains { row in
        if case .error(let id, let text) = row { return known.contains(id) == false && isQuotaError(text) }
        return false
    }
}
