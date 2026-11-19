import Foundation

// What the first screen of the Providers page lists: the accounts that need someone, the providers (each with how many accounts it has) and the
// local servers, narrowed by what the person typed. Usage and sign-in belong to an account, never to its provider: a provider only counts its
// accounts, so nothing here pools a number. Everything the view says is decided here, from the page, the quotas and a clock, so it can be tested.

/// The share of the 5h window from which an account counts as near its limit (the Usage page's orange).
public let nearLimitShare = 0.9

/// What the quotas say of one account.
public struct AccountUsage: Equatable {
    public var five: MeterShape?
    public var weekly: MeterShape?
    /// `Resets in 2h 14m`, or the provider's own words; nil when the time has passed or there is none.
    public var reset: String?
    /// The numbers are the last known ones: a later probe was refused.
    public var stale: Bool

    public var nearLimit: Bool { (five?.used ?? 0) >= nearLimitShare }
}

/// The 5h and Weekly meters of the account named `account` in `providers.json`, from the host's quotas (`now` in milliseconds). Nil when the
/// quotas have nothing for it: signed out, not checked, or a provider with no such window. A window that is neither (Claude's `7d Opus`) is left
/// to the Usage page.
public func accountUsage(_ account: String, in quotas: [UsageQuota], now: Int) -> AccountUsage? {
    guard let quota = quotas.first(where: { $0.account == account }), quota.status == .ok || quota.stale else { return nil }
    // the windows the Usage page pools: a model's or a limit's own window (Claude's `7d Opus`, Codex's Spark) is not one, and Antigravity's pools all are
    let main = quota.windows.filter { ($0.group == nil || quota.provider == "agy") && $0.group != "model_scoped" }
    let fives = main.filter { quotaKind($0) == .fiveHour }
    let weeks = main.filter { quotaKind($0) == .weekly }
    guard fives.isEmpty == false || weeks.isEmpty == false else { return nil }
    let timed = fives.isEmpty ? weeks : fives
    let soonest = timed.filter { $0.resetsAt != nil }.min { ($0.resetsAt ?? 0) < ($1.resetsAt ?? 0) } ?? timed.first
    return AccountUsage(
        five: fives.isEmpty ? nil : meterShape(fives), weekly: weeks.isEmpty ? nil : meterShape(weeks),
        reset: soonest.flatMap { resetText(resetsAt: $0.resetsAt, label: $0.resetLabel, now: now) }, stale: quota.stale
    )
}

/// Why an account is on the list of those that need someone.
public enum AttentionReason: Equatable { case signedOut, nearLimit }

public func attentionReason(_ account: ProviderAccount, usage: AccountUsage?) -> AttentionReason? {
    if account.state == .signedOut { return .signedOut }
    if usage?.nearLimit == true { return .nearLimit }
    return nil
}

/// An account that needs someone, with the provider it is of.
public struct DirectoryAccount: Equatable, Identifiable {
    public let tool: String
    public let toolTitle: String
    public let icon: String
    public let account: ProviderAccount
    public let usage: AccountUsage?
    public let reason: AttentionReason
    public var id: String { tool + "/" + account.name }
}

/// A provider as its row says it: how many accounts it has and whether any needs someone.
public struct DirectoryProvider: Equatable, Identifiable {
    public enum Mark: Equatable { case ok, attention, off }

    public let tool: ProviderTool
    public let summary: String
    public let mark: Mark
    public var id: String { tool.id }
    public var accounts: Int { tool.accounts.count }
}

public struct ProvidersDirectory: Equatable {
    public let attention: [DirectoryAccount]
    public let providers: [DirectoryProvider]
    public let servers: [ProviderServer]

    public var isEmpty: Bool { attention.isEmpty && providers.isEmpty && servers.isEmpty }
}

/// `1 account needs attention`, `All signed in`, or the provider's own state when it has no account.
private func providerSummary(_ tool: ProviderTool, attention: Int) -> (String, DirectoryProvider.Mark) {
    guard tool.accounts.isEmpty == false else { return (tool.status.text, .off) }
    if attention > 0 { return ("\(attention) \(attention == 1 ? "account needs" : "accounts need") attention", .attention) }
    if tool.accounts.allSatisfy({ $0.state == .ready }) { return ("All signed in", .ok) }
    return ("Could not check", .off)
}

/// The first screen of the page. `filter` keeps a provider, an account or a server whose name has it (case ignored); the accounts that need
/// someone come first, in the order of their providers.
public func providersDirectory(_ page: ProvidersPage, quotas: [UsageQuota], filter: String = "", now: Int) -> ProvidersDirectory {
    let text = filter.trimmingCharacters(in: .whitespaces).lowercased()
    func matches(_ words: [String]) -> Bool { text.isEmpty || words.contains { $0.lowercased().contains(text) } }
    var attention: [DirectoryAccount] = []
    var providers: [DirectoryProvider] = []
    for tool in page.tools {
        let usages = tool.accounts.map { ($0, accountUsage($0.name, in: quotas, now: now)) }
        let needing = usages.compactMap { account, usage in attentionReason(account, usage: usage).map { (account, usage, $0) } }
        let toolMatches = matches([tool.title, tool.id])
        for (account, usage, reason) in needing where toolMatches || matches([account.name, account.title]) {
            attention.append(DirectoryAccount(tool: tool.id, toolTitle: tool.title, icon: tool.icon, account: account, usage: usage, reason: reason))
        }
        if toolMatches || tool.accounts.contains(where: { matches([$0.name, $0.title]) }) {
            let (summary, mark) = providerSummary(tool, attention: needing.count)
            providers.append(DirectoryProvider(tool: tool, summary: summary, mark: mark))
        }
    }
    return ProvidersDirectory(attention: attention, providers: providers, servers: page.servers.filter { matches([$0.title, $0.id]) })
}

/// Every provider, account and server of this Mac as a place the Settings search can open (the static index cannot know them).
public func providersSearchEntries(_ page: ProvidersPage) -> [SettingsEntry] {
    page.tools.flatMap { tool in
        [SettingsEntry(page: .providers, group: "AI providers", title: tool.title, detail: tool.status.text, path: [tool.id])]
            + tool.accounts.map { SettingsEntry(page: .providers, group: tool.title, title: $0.title, detail: "Account of \(tool.title)", path: [tool.id, $0.name]) }
    } + page.servers.map { SettingsEntry(page: .providers, group: "Local servers", title: $0.title, detail: $0.status, path: [$0.id]) }
}
