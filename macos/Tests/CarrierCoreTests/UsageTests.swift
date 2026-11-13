import Foundation
import Testing
@testable import CarrierCore

// The `usage` reply (`src/usage/service.ts`) as the app decodes it, the requests it sends, and the store that holds the page's state.

private let golden = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/chat-usage.json")

private func decode(_ json: String) throws -> UsageSnapshot { try JSONDecoder().decode(UsageSnapshot.self, from: Data(json.utf8)) }

private let none = #"{"tokens":{"input":0,"cachedInput":0,"cacheWrite":0,"output":0,"reasoning":0},"costUsd":0,"turns":0}"#

@Test func theGoldenReplyDecodesWithEveryPartOfIt() throws {
    let snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: Data(contentsOf: golden))
    #expect(snapshot.quotas.map(\.account) == ["claude", "claude-work", "codex", "agy", "local"])
    let claude = snapshot.quotas[0]
    #expect(claude.status == .ok && claude.windows.count == 3 && claude.windows[2].group == "model_scoped")
    #expect(claude.extraUsage?.usedCreditsUsd == 12.4 && claude.planType == "max")
    #expect(snapshot.quotas[3].windows.count == 6 && snapshot.quotas[3].aiCreditsNotice != nil)
    #expect(snapshot.quotas[4].servers.map(\.kind) == ["lmstudio", "ollama"] && snapshot.quotas[4].servers[1].models.count == 2)
    #expect(snapshot.summary.turns == 318 && snapshot.summary.tokens.cachedInput == 21_400_000)
    #expect(snapshot.daily.count == 7 && snapshot.daily[0].date == "2026-11-07" && snapshot.daily[0].row.costUsd == 3.1)
    #expect(snapshot.byWorkspace.map(\.source) == ["epic", "chat", "external"])
    #expect(snapshot.catalogModels.contains("gpt-5-codex"))
}

@Test func aSignedOutAccountHasNoWindowsAndSaysWhy() throws {
    let work = try JSONDecoder().decode(UsageSnapshot.self, from: Data(contentsOf: golden)).quotas[1]
    #expect(work.status == .signedOut && work.windows.isEmpty && work.message != nil && work.displayName == "Work")
}

@Test func aRateLimitedAccountKeepsItsLastWindowsAndIsStale() throws {
    let codex = try JSONDecoder().decode(UsageSnapshot.self, from: Data(contentsOf: golden)).quotas[2]
    #expect(codex.status == .rateLimited && codex.stale && codex.windows.count == 3)
    #expect(codex.windows[2].resetsAt == nil && codex.windows[2].resetLabel == "in 3 hours")
    #expect(codex.credits?.balance == "12.50" && codex.credits?.unlimited == false)
}

@Test func anUnpricedModelIsNotAFreeOne() throws {
    let models = try JSONDecoder().decode(UsageSnapshot.self, from: Data(contentsOf: golden)).byModel
    #expect(models.map(\.costStatus) == [.priced, .priced, .unpriced, .local])
    #expect(models[2].row.costUsd == 0 && models[3].isLocal)
}

@Test func anEmptyHistoryDecodesToZeroes() throws {
    let snapshot = try decode(#"{"checkedAt":5,"quotas":[],"summary":\#(none),"daily":[],"byModel":[],"byWorkspace":[],"catalogModels":[]}"#)
    #expect(snapshot.quotas.isEmpty && snapshot.daily.isEmpty && snapshot.byModel.isEmpty)
    #expect(snapshot.summary.turns == 0 && snapshot.summary.costUsd == 0)
}

@Test func fieldsTheHostLeavesOutAreTheirDefaults() throws {
    let snapshot = try decode(#"{"summary":{},"quotas":[{"account":"x","provider":"claude","status":"ok","windows":[{"id":"five_hour","usedPercent":10}]}]}"#)
    #expect(snapshot.checkedAt == 0 && snapshot.daily.isEmpty && snapshot.catalogModels.isEmpty)
    #expect(snapshot.summary.tokens == UsageTokens() && snapshot.summary.turns == 0)
    let quota = snapshot.quotas[0]
    #expect(quota.stale == false && quota.servers.isEmpty && quota.extraUsage == nil && quota.checkedAt == 0)
    #expect(quota.windows[0].label == "five_hour" && quota.windows[0].resetsAt == nil)
}

@Test func aNewerHostsUnknownFieldsAndValuesDoNotBreakTheDecode() throws {
    let snapshot = try decode(
        #"{"summary":\#(none),"future":1,"quotas":[{"account":"x","provider":"claude","status":"on_fire","windows":[],"novel":{}}],"byModel":[{"model":"m","costStatus":"free-ish"}]}"#
    )
    #expect(snapshot.quotas[0].status == .unavailable)
    #expect(snapshot.byModel[0].costStatus == .priced)
}

@Test func theQueryLeavesOutWhatTheHostDefaultsTo() {
    #expect(UsageQuery().wire == "")
    let query = UsageQuery(refresh: true, days: 7, provider: .codex, source: .chat, search: " web ", account: "claude-work")
    #expect(query.wire == #",\#("\"refresh\":true"),"days":7,"provider":"codex","source":"chat","search":"web","account":"claude-work""#)
    #expect(UsageQuery(search: "   ").wire == "")
}

@Test func anOverrideIsSentAsTheHostsSchemaHasIt() {
    #expect(UsageOverride(model: "qwen3:8b", action: .local).wire == #","model":"qwen3:8b","action":"local""#)
    #expect(UsageOverride(model: "m", action: .clear).wire == #","model":"m","action":"clear""#)
    #expect(UsageOverride(model: "m", action: .alias("gpt-5-codex")).wire == #","model":"m","action":"alias","aliasTo":"gpt-5-codex""#)
    let custom = UsageOverride(model: "m", action: .rates(input: 1.5, cachedInput: 0.5, cacheWrite: nil, output: 6)).wire
    #expect(custom == #","model":"m","action":"custom","inputPerMillionUsd":1.5,"outputPerMillionUsd":6.0,"cachedInputPerMillionUsd":0.5"#)
    #expect(UsageOverride(model: "a\"b", action: .local).wire.contains(#""model":"a\"b""#))
}

// MARK: the store, through a fake host

final class UsageHost: ChatHost, @unchecked Sendable {
    var capabilitiesAnswer: Set<ControlClient.Capability> = [.usage, .usageOverride]
    var snapshot: UsageSnapshot
    var failure: Error?
    var queries: [UsageQuery] = []
    var overrides: [UsageOverride] = []

    init(_ snapshot: UsageSnapshot) { self.snapshot = snapshot }

    func capabilities() async throws -> Set<ControlClient.Capability> { capabilitiesAnswer }
    func usage(_ query: UsageQuery) async throws -> UsageSnapshot {
        queries.append(query)
        if let failure { throw failure }
        return snapshot
    }
    func usageOverride(_ override: UsageOverride) async throws { overrides.append(override) }

    func agents() async throws -> [ChatAgent] { [] }
    func open(plan: SessionPlan) async throws -> String { "" }
    func workspace(_ folder: String) async throws -> WorkspaceInfo { WorkspaceInfo(folder: folder, git: false) }
    func fetch(_ folder: String) async throws -> WorkspaceInfo { WorkspaceInfo(folder: folder, git: false) }
    func suggestName(_ folder: String) async throws -> String { "" }
    func checkName(_ folder: String, _ name: String) async throws -> NameCheck { NameCheck(valid: true, free: true) }
    func list(archived: Bool) async throws -> [ChatSession] { [] }
    func resume(_ id: String) async throws {}
    func send(_ id: String, _ text: String) async throws {}
    func send(_ id: String, _ text: String, command: String?) async throws {}
    func interrupt(_ id: String) async throws {}
    func archive(_ id: String, _ archived: Bool) async throws {}
    func delete(_ id: String) async throws {}
    func cloneRepo(_ repo: String) async throws -> ClonedRepo { throw ControlError.closed }
    func createProject(_ name: String) async throws -> String { throw ControlError.closed }
    func githubRepos(page: Int) async throws -> GithubReposPage { throw ControlError.closed }
    func deletePreview(_ ids: [String]) async throws -> [SessionDeletePreview] { [] }
    func answer(_ id: String, approval: String, choice: String, answers: [String: String]?) async throws {}
    func events(_ id: String, after: Int, limit: Int) async throws -> ChatEvents { ChatEvents(events: [], cursor: after, options: [], commands: []) }
    func setOption(_ id: String, option: String, value: String) async throws {}
}

func host() throws -> UsageHost { UsageHost(try JSONDecoder().decode(UsageSnapshot.self, from: Data(contentsOf: golden))) }

@MainActor @Test func loadingAsksWithTheFiltersAndKeepsTheSnapshot() async throws {
    let host = try host()
    let store = UsageStore(host: host)
    #expect(store.snapshot == nil && store.isLoading == false && store.error == nil)
    store.days = 7
    store.providerFilter = .claude
    store.sourceFilter = .epic
    store.searchText = "web"
    await store.load(refresh: true)
    // the quotas of every provider are asked apart, with the refresh; the filtered ask then reads what that left in the host's cache
    #expect(host.queries == [UsageQuery(refresh: true, days: 7), UsageQuery(refresh: false, days: 7, provider: .claude, source: .epic, search: "web")])
    #expect(store.snapshot == host.snapshot && store.isLoading == false && store.isRefreshing == false && store.error == nil)
}

@MainActor @Test func aFailedAskKeepsTheLastSnapshotAndSaysWhy() async throws {
    let host = try host()
    let store = UsageStore(host: host)
    await store.load()
    host.failure = ControlError.timeout
    await store.load()
    #expect(store.snapshot != nil && store.error == "The chat host took too long to answer" && store.isRefreshing == false)
    host.failure = nil
    await store.load()
    #expect(store.error == nil)
}

@MainActor @Test func anOlderHostIsToldWhatToDoAndIsNeverAsked() async throws {
    let host = try host()
    host.capabilitiesAnswer = [.providers]
    let store = UsageStore(host: host)
    await store.load()
    #expect(store.error == usageNeedsNewerHost && store.snapshot == nil && host.queries.isEmpty && store.isLoading == false)
    #expect(await store.override(UsageOverride(model: "m", action: .local)) == usageNeedsNewerHost)
    #expect(host.overrides.isEmpty)
}

@MainActor @Test func aHostThatDoesNotAnswerIsNotTheOlderHost() async throws {
    let host = try host()
    host.failure = ControlError.closed
    host.capabilitiesAnswer = [.usage]
    let store = UsageStore(host: host)
    await store.load()
    #expect(store.error == "The chat host is not answering")
}

@MainActor @Test func anOverrideIsSentAndTheNumbersAreAskedAgain() async throws {
    let host = try host()
    let store = UsageStore(host: host)
    let refusal = await store.override(UsageOverride(model: "gemini-4-argon", action: .alias("gemini-2-5-pro")))
    #expect(refusal == nil && host.overrides.count == 1 && host.queries.count == 1 && store.snapshot != nil)
}

@MainActor @Test func providersUnfoldOneByOne() throws {
    let store = UsageStore(host: try host())
    store.toggleProvider("claude")
    store.toggleProvider("codex")
    store.toggleProvider("claude")
    #expect(store.expandedProviders == ["codex"])
}
