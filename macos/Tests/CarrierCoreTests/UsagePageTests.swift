import Foundation
import Testing
@testable import CarrierCore

// The pooled quota list of the Usage page: meter geometry, the rows of every drawer, the provider filter, the limit detection and the refresh triggers.

private let golden = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/chat-usage.json")
private func snapshot() throws -> UsageSnapshot { try JSONDecoder().decode(UsageSnapshot.self, from: Data(contentsOf: golden)) }

/// Inside the fixture's day: the Claude 5h resets 10 800 s later.
private let now = 1_794_700_800_000

private func window(_ used: Double, resetsAt: Int? = nil, label: String = "5h", group: String? = nil) -> UsageWindow {
    var json = #"{"id":"w","label":"\#(label)","usedPercent":\#(used)"#
    if let resetsAt { json += #","resetsAt":\#(resetsAt)"# }
    if let group { json += #","group":"\#(group)""# }
    return try! JSONDecoder().decode(UsageWindow.self, from: Data((json + "}").utf8))
}

// MARK: geometry

@Test func aMeterIsClampedToItsTrack() throws {
    #expect(meterShape([window(150)]) == MeterShape(solid: 1))
    #expect(meterShape([window(-20)]) == MeterShape())
    #expect(meterShape([]) == MeterShape())
    let over = MeterShape(solid: 0.7, hatched: 0.9)
    #expect(over.solid == 0.7 && abs(over.hatched - 0.3) < 1e-9 && over.used <= 1)
}

@Test func theHatchedBandIsTheUseThatTheEarliestResetGivesBack() throws {
    // two accounts at 40 % and 80 %: the first resets sooner, so a fifth of the track is its use, hatched; the rest stays
    let shape = meterShape([window(40, resetsAt: now + 1000), window(80, resetsAt: now + 9000)])
    #expect(abs(shape.hatched - 0.2) < 1e-9 && abs(shape.solid - 0.4) < 1e-9)
    // no time known (only the provider's words): nothing refills in the preview
    #expect(meterShape([window(50)]) == MeterShape(solid: 0.5))
    // one window with a time: all of its use is the preview
    #expect(meterShape([window(42, resetsAt: now + 1)]) == MeterShape(hatched: 0.42))
}

@Test func windowsAreToldApartByTheirWords() throws {
    #expect(quotaKind(window(0, label: "5h")) == .fiveHour && quotaKind(window(0, label: "Gemini Models · Five Hour Limit Remaining")) == .fiveHour)
    #expect(quotaKind(window(0, label: "7d")) == .weekly && quotaKind(window(0, label: "Weekly Limit Remaining")) == .weekly)
    #expect(quotaKind(window(0, label: "7d Opus")) == nil)
}

@Test func aResetIsCountedDownOrSaidInTheProvidersWords() {
    #expect(resetText(resetsAt: now + 8_040_000, label: nil, now: now) == "Resets in 2h 14m")
    #expect(resetText(resetsAt: now - 1, label: "in 3 hours", now: now) == nil)
    #expect(resetText(resetsAt: nil, label: "in 3 hours", now: now) == "in 3 hours")
}

// MARK: rows

@Test func theListHasTheFourProvidersInOrderAndPoolsTheirMeters() throws {
    let providers = usageProviders(try snapshot().quotas, now: now)
    #expect(providers.map(\.title) == ["Claude", "Codex", "Antigravity", "Local Servers"])
    let claude = providers[0]
    // the 5h and Weekly of the signed-in account only: the signed-out one has none, and the Opus window is a row of the drawer
    #expect(claude.meters.map(\.kind) == [.fiveHour, .weekly] && claude.meters[0].shape == MeterShape(hatched: 0.42))
    #expect(claude.earliestReset == "Resets in 3h 00m" && claude.accounts.count == 2 && claude.subtitle == "2 accounts · signed out")
    #expect(claude.mark == .failure && claude.stale == false)
    // all three Antigravity pools are pooled: 5h is (10 + 55 + 0) / 3
    let agy = providers[2]
    #expect(abs(agy.meters[0].shape.used - 65.0 / 300) < 1e-9 && agy.mark == .ok)
    #expect(providers[3].meters.isEmpty && providers[3].subtitle == "1 of 2 running")
}

@Test func aStaleProviderIsMarkedAndKeepsItsNumbers() throws {
    let codex = usageProviders(try snapshot().quotas, now: now)[1]
    #expect(codex.stale && codex.mark == .warning && codex.subtitle == "Rate limited")
    // the Spark window has its own row: the main 5h is the primary one only
    #expect(codex.meters[0].shape.used == 0.87)
    #expect(codex.accounts[0].note == "Codex is rate limiting the check; these are the last known numbers.")
}

@Test func claudesDrawerHasEveryWindowItsSpendAndASignInForASignedOutAccount() throws {
    let accounts = usageProviders(try snapshot().quotas, now: now)[0].accounts
    let personal = accounts[0]
    #expect(personal.title == "Personal" && personal.status == "Max plan" && personal.note == nil && personal.canSignIn == false)
    #expect(personal.lines.map(\.title) == ["5h", "Weekly", "By model", "Opus weekly", "Extra usage"])
    #expect(personal.lines[1].value == "62%" && personal.lines[4].value == "$12.40 of $50.00 a month")
    let work = accounts[1]
    #expect(work.status == "Signed out" && work.mark == .failure && work.canSignIn && work.lines.isEmpty && work.note == "Not signed in. Run claude and sign in.")
}

@Test func codexDrawerHasItsLimitsCreditsAndResetCredits() throws {
    let codex = usageProviders(try snapshot().quotas, now: now)[1].accounts[0]
    #expect(codex.status == "Rate limited")
    #expect(codex.lines.map(\.title) == ["5h", "Weekly", "Other limits", "Spark 5h", "Credits", "Reset credits"])
    #expect(codex.lines[3].reset == "in 3 hours" && codex.lines[4].value == "12.50" && codex.lines[5].value == "1 available")
}

@Test func antigravityDrawerHasAllItsPoolsAndTheCreditsNotice() throws {
    let lines = usageProviders(try snapshot().quotas, now: now)[2].accounts[0].lines
    #expect(lines.filter(\.heading).map(\.title) == ["Gemini Models", "Claude and GPT models", "Gemini 4 Argon"])
    #expect(lines.filter { $0.shape != nil }.count == 6 && lines.last?.title == "AI credits: Unavailable via native CLI")
}

@Test func localDrawerHasTheServersTheirModelsAndTheCost() throws {
    let lines = usageProviders(try snapshot().quotas, now: now)[3].accounts[0].lines
    #expect(lines.map(\.title) == ["LM Studio", "Ollama", "$0 local compute"])
    #expect(lines[0].value == "Not running" && lines[1].value == "Ready" && lines[1].detail == "localhost:11434 · Loaded: qwen3:8b, llama3.2:3b")
}

@Test func anUnknownProviderAndAHostWithNoQuotasGiveNoRows() throws {
    #expect(usageProviders([], now: now).isEmpty)
    let odd = try JSONDecoder().decode(UsageSnapshot.self, from: Data(#"{"summary":{},"quotas":[{"account":"x","provider":"newcomer","status":"ok"}]}"#.utf8))
    #expect(usageProviders(odd.quotas, now: now).isEmpty)
}

// MARK: filter

@MainActor @Test func aClickOnAProviderFiltersByItAndAnotherClickClearsIt() throws {
    let store = UsageStore(host: try host())
    store.toggleFilter(.codex)
    #expect(store.providerFilter == .codex)
    store.toggleFilter(.claude)
    #expect(store.providerFilter == .claude)
    store.toggleFilter(.claude)
    #expect(store.providerFilter == .all)
}

@MainActor @Test func theListKeepsEveryProviderWhileTheFilterNarrowsTheHistory() async throws {
    let host = try host()
    let store = UsageStore(host: host)
    store.toggleFilter(.codex)
    await store.load()
    #expect(store.quotas.count == 5 && host.queries.map(\.provider) == [.all, .codex])
}

// MARK: limit detection

private func state(_ kind: String?, status: String = "needs_human", issue: Int = 7) throws -> ConnectionState {
    let json = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/snapshot.json"), encoding: .utf8)
    var snapshot = try decodeSnapshot(Data(json.utf8))
    snapshot.epics = Array(snapshot.epics.prefix(1))
    snapshot.epics[0].issue = issue
    snapshot.epics[0].status = PanelEpic.Status(rawValue: status)!
    snapshot.epics[0].needsHumanKind = kind
    return .running(snapshot)
}

@Test func anEpicEnteringTheUsageLimitIsDetectedOnceAndOnlyAsAnEntry() throws {
    let running = try state(nil, status: "running")
    let limited = try state("usage_limit")
    #expect(usageLimitEntered(from: running, to: limited))
    #expect(usageLimitEntered(from: limited, to: limited) == false)
    #expect(usageLimitEntered(from: nil, to: limited) == false)
    #expect(usageLimitEntered(from: .stopped, to: limited) == false)
    #expect(usageLimitEntered(from: running, to: try state("review_limit")) == false)
    #expect(usageLimitEntered(from: limited, to: try state("usage_limit", issue: 8)))
}

@Test func aQuotaErrorOfAChatTurnIsOnlyOneThatAppearedAfterTheLoad() {
    let before: [FeedRow] = [.user(id: "e1", text: "hi")]
    let after = before + [.error(id: "e2", text: "You've hit your session limit · resets 12:40pm")]
    #expect(quotaErrorAppeared(from: before, to: after))
    #expect(quotaErrorAppeared(from: [], to: after) == false)
    #expect(quotaErrorAppeared(from: after, to: after) == false)
    #expect(quotaErrorAppeared(from: before, to: before + [.error(id: "e2", text: "The Claude process ended")]) == false)
}

// MARK: triggers

/// Waits for what a task that nobody holds is to do.
@MainActor private func until(_ done: () -> Bool) async {
    for _ in 0..<400 where done() == false { try? await Task.sleep(for: .milliseconds(5)) }
}

private final class Ticks: @unchecked Sendable {
    var count = 0
    var open = 2
}

@MainActor @Test func appearingAsksOnceAndStartsTheTimerThatDisappearingCancels() async throws {
    let host = try host()
    let ticks = Ticks()
    let refresher = UsageRefresher(store: UsageStore(host: host)) { _ in
        ticks.count += 1
        // two minutes pass, then the third never does
        if ticks.count > ticks.open { try await Task.sleep(for: .seconds(3600)) }
    }
    #expect(refresher.isTimerRunning == false)
    refresher.appear()
    #expect(refresher.isTimerRunning && refresher.visible)
    await until { host.queries.count == 3 }
    #expect(host.queries.count == 3 && host.queries.allSatisfy { $0.refresh == false })
    refresher.disappear()
    #expect(refresher.isTimerRunning == false && refresher.visible == false)
    let asked = host.queries.count
    try await Task.sleep(for: .milliseconds(50))
    #expect(host.queries.count == asked)
}

@MainActor @Test func becomingActiveAsksOnlyWhileThePageIsOpenAndCheckAgainSkipsTheCache() async throws {
    let host = try host()
    let refresher = UsageRefresher(store: UsageStore(host: host)) { _ in try await Task.sleep(for: .seconds(3600)) }
    #expect(refresher.appBecameActive() == nil && host.queries.isEmpty)
    refresher.appear()
    await refresher.appBecameActive()?.value
    await until { host.queries.count == 2 }
    #expect(host.queries.map(\.refresh) == [false, false])
    await refresher.checkAgain().value
    await refresher.limitHit().value
    #expect(host.queries.map(\.refresh) == [false, false, true, true])
    refresher.disappear()
}
