import Foundation
import Testing
@testable import CarrierCore

// The first screen of the Providers page: which accounts need someone, what a provider says of its accounts, the usage of each account and the
// filter, from the golden `providers` and `usage` replies and a clock inside the fixture's day.

private let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
private let now = 1_794_700_800_000

private func page() throws -> ProvidersPage {
    let reply = try JSONDecoder().decode(HostProviders.self, from: Data(contentsOf: fixtures.appendingPathComponent("chat-providers.json")))
    return providersPage(reply, config: nil, chat: nil)
}

private func quotas() throws -> [UsageQuota] {
    try JSONDecoder().decode(UsageSnapshot.self, from: Data(contentsOf: fixtures.appendingPathComponent("chat-usage.json"))).quotas
}

private func quota(_ account: String, five: Double, provider: String = "claude") -> UsageQuota {
    let json = #"{"account":"\#(account)","provider":"\#(provider)","status":"ok","windows":[{"id":"a","label":"5h","usedPercent":\#(five)},{"id":"b","label":"Weekly","usedPercent":10}]}"#
    return try! JSONDecoder().decode(UsageQuota.self, from: Data(json.utf8))
}

@Test func anAccountsUsageIsItsOwnFiveHourAndWeeklyWindowsAndWhenTheyReset() throws {
    let quotas = try quotas()
    let claude = try #require(accountUsage("claude", in: quotas, now: now))
    #expect(claude.five?.used == 0.42 && claude.weekly?.used == 0.615 && claude.reset == "Resets in 3h 00m" && claude.stale == false)
    // Codex's own pool (Spark) is not its 5h window, and a refused probe leaves the last numbers marked
    let codex = try #require(accountUsage("codex", in: quotas, now: now))
    #expect(codex.five?.used == 0.87 && codex.stale && codex.nearLimit == false)
    // nothing for a signed-out account or one the host does not know
    #expect(accountUsage("claude-work", in: quotas, now: now) == nil && accountUsage("nobody", in: quotas, now: now) == nil)
}

@Test func aCodexFreeAccountHasOnlyAMonthlyWindowAndItIsMetered() throws {
    let json = #"{"account":"codex-free","provider":"codex","status":"ok","windows":[{"id":"codex:primary","label":"30d","usedPercent":100,"resetsAt":\#(now + 3_600_000)}]}"#
    let free = try JSONDecoder().decode(UsageQuota.self, from: Data(json.utf8))
    let usage = try #require(accountUsage("codex-free", in: [free], now: now))
    #expect(usage.five == nil && usage.weekly == nil && usage.monthly?.used == 1 && usage.reset == "Resets in 1h 00m")
}

@Test func anAccountNeedsSomeoneWhenItIsSignedOutOrNearTheEndOfItsFiveHours() throws {
    let accounts = try page().tools.flatMap(\.accounts)
    let work = try #require(accounts.first { $0.name == "claude-work" }), claude = try #require(accounts.first { $0.name == "claude" })
    #expect(attentionReason(work, usage: nil) == .signedOut)
    #expect(attentionReason(claude, usage: accountUsage("claude", in: try quotas(), now: now)) == nil)
    let high = accountUsage("claude", in: [quota("claude", five: 94)], now: now)
    #expect(attentionReason(claude, usage: high) == .nearLimit)
    // exactly 90 % counts, as the Usage page's bar turns orange there
    #expect(attentionReason(claude, usage: accountUsage("claude", in: [quota("claude", five: 90)], now: now)) == .nearLimit)
}

@Test func theListNamesTheAccountsThatNeedSomeoneAndEachProviderSaysHowManyItHas() throws {
    let directory = providersDirectory(try page(), quotas: try quotas(), now: now)
    #expect(directory.attention.map(\.id) == ["claude/claude-work"] && directory.attention.first?.reason == .signedOut)
    #expect(directory.attention.first?.toolTitle == "Claude Code")
    let byId = Dictionary(uniqueKeysWithValues: directory.providers.map { ($0.id, $0) })
    #expect(byId["claude"]?.accounts == 2 && byId["claude"]?.summary == "1 account needs attention" && byId["claude"]?.mark == .attention)
    // a provider whose account could not be checked says so; one with no account says what it found
    #expect(byId["codex"]?.summary == "Could not check" && byId["codex"]?.mark == .off)
    #expect(byId["agy"]?.accounts == 0 && byId["agy"]?.summary == "Found, not added")
    #expect(directory.servers.map(\.id) == ["lmstudio", "ollama"])
}

@Test func moreThanOneAccountOfAProviderCountsAndAHealthyProviderIsAllSignedIn() throws {
    // both accounts of Claude sign in and one is at 94 %: the provider says one, and the list names that account
    let text = try String(contentsOf: fixtures.appendingPathComponent("chat-providers.json"), encoding: .utf8).replacingOccurrences(of: "\"signedOut\"", with: "\"ready\"")
    let reply = try JSONDecoder().decode(HostProviders.self, from: Data(text.utf8))
    let directory = providersDirectory(providersPage(reply, config: nil, chat: nil), quotas: [quota("claude", five: 94), quota("claude-work", five: 12)], now: now)
    #expect(directory.attention.map(\.id) == ["claude/claude"] && directory.attention.first?.reason == .nearLimit)
    #expect(directory.providers.first { $0.id == "claude" }?.summary == "1 account needs attention")
    let calm = providersDirectory(providersPage(reply, config: nil, chat: nil), quotas: [quota("claude", five: 10), quota("claude-work", five: 12)], now: now)
    #expect(calm.attention.isEmpty && calm.providers.first { $0.id == "claude" }?.summary == "All signed in" && calm.providers.first { $0.id == "claude" }?.mark == .ok)
}

@Test func theFilterKeepsWhatHasTheWordInAProviderAnAccountOrAServer() throws {
    let all = try providersDirectory(page(), quotas: quotas(), now: now)
    #expect(providersDirectory(try page(), quotas: try quotas(), filter: "  ", now: now) == all)
    // an account's name finds its provider, and the account on the list of those that need someone
    let work = providersDirectory(try page(), quotas: try quotas(), filter: "WORK", now: now)
    #expect(work.providers.map(\.id) == ["claude"] && work.attention.map(\.id) == ["claude/claude-work"] && work.servers.isEmpty)
    #expect(providersDirectory(try page(), quotas: try quotas(), filter: "ollama", now: now).servers.map(\.id) == ["ollama"])
    #expect(providersDirectory(try page(), quotas: try quotas(), filter: "zzz", now: now).isEmpty)
}

@Test func theSearchCanOpenEveryProviderAccountAndServerOfThisMac() throws {
    let entries = providersSearchEntries(try page())
    let account = try #require(entries.first { $0.title == "Work" })
    #expect(account.page == .providers && account.path == ["claude", "claude-work"] && account.detail == "Account of Claude Code · claude-work")
    #expect(entries.first { $0.title == "Ollama" }?.path == ["ollama"] && entries.first { $0.title == "Claude Code" }?.path == ["claude"])
    #expect(settingsResults("work", in: entries).first?.path == ["claude", "claude-work"])
}

@Test func aProviderNotOnThisMacSaysSoEvenWithAccountsInTheFile() throws {
    // the file names accounts, the host finds no binary: the list says what the provider's own screen says
    let text = try String(contentsOf: fixtures.appendingPathComponent("chat-providers.json"), encoding: .utf8).replacingOccurrences(of: "\"found\": true", with: "\"found\": false")
    let missing = providersPage(try JSONDecoder().decode(HostProviders.self, from: Data(text.utf8)), config: nil, chat: nil)
    let directory = providersDirectory(missing, quotas: [], now: now)
    let claude = try #require(directory.providers.first { $0.id == "claude" })
    #expect(claude.accounts == 2 && claude.summary == "Not installed" && claude.mark == .off)
    // its accounts are not asked for either (there is nothing to sign in to), and the search says what the list says
    #expect(directory.attention.isEmpty)
    #expect(providersSearchEntries(missing).first { $0.title == "Claude Code" }?.detail == "Not installed")
}

@Test func theNextResetIsTheSoonestOneStillAheadAndTheSearchPoolsNothingByProvider() throws {
    // two pools of one Antigravity account: one reset has passed, the other is an hour away
    let json = #"{"account":"agy","provider":"agy","status":"ok","windows":[{"id":"a","label":"5h","group":"G1","usedPercent":20,"resetsAt":\#(now - 1000)},{"id":"b","label":"5h","group":"G2","usedPercent":40,"resetsAt":\#(now + 3_600_000)}]}"#
    let mixed = try JSONDecoder().decode(UsageQuota.self, from: Data(json.utf8))
    #expect(accountUsage("agy", in: [mixed], now: now)?.reset == "Resets in 1h 00m")
    // the provider's own state is only its state when it has no account; with accounts it says how many, and a renamed account is found by its key too
    let entries = providersSearchEntries(try page())
    #expect(entries.first { $0.title == "Claude Code" }?.detail == "2 accounts" && entries.first { $0.title == "Antigravity" }?.detail == "Found, not added")
    #expect(settingsResults("claude-work", in: entries).first?.path == ["claude", "claude-work"])
}

@Test func twoAccountsThatShareATitleAreTwoEntriesOfTheList() {
    let one = SettingsEntry(page: .providers, group: "Claude Code", title: "Work", path: ["claude", "work-1"])
    let two = SettingsEntry(page: .providers, group: "Claude Code", title: "Work", path: ["claude", "work-2"])
    #expect(one.id != two.id)
    // a row of the page keeps its anchor, and a path does not change what the page scrolls to
    #expect(SettingsEntry(page: .general, group: "Display", title: "Clock").id == "general.display.clock")
}
