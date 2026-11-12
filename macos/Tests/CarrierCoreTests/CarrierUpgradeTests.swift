import Testing
@testable import CarrierCore

@Test func carrierIsOlderOnlyWhenBothVersionsReadAndTheInstalledOneIsLower() {
    #expect(carrierIsOlder(installed: "0.1.0", app: "0.1.4"))
    #expect(carrierIsOlder(installed: "0.9.0", app: "0.10.0"))
    #expect(carrierIsOlder(installed: "0.1.4", app: "0.1.4") == false)
    #expect(carrierIsOlder(installed: "0.2.0", app: "0.1.4") == false)
    #expect(carrierIsOlder(installed: "", app: "0.1.4") == false)
    #expect(carrierIsOlder(installed: "unknown", app: "0.1.4") == false)
    #expect(carrierIsOlder(installed: "0.1.0", app: "") == false)
    #expect(carrierIsOlder(installed: "1.2", app: "1.2.0") == false)
}

/// A fake `brew`: each command gets the next outcome, and the commands it was asked to run are kept.
private final class FakeBrew {
    var outcomes: [BrewOutcome]
    var ran: [BrewCommand] = []
    init(_ outcomes: [BrewOutcome]) { self.outcomes = outcomes }
    func run(_ command: BrewCommand) -> BrewOutcome {
        ran.append(command)
        return outcomes.isEmpty ? .done : outcomes.removeFirst()
    }
}

@Test func anOlderCarrierRunsTheUpdateThenTheUpgradeWithNoAsk() {
    let brew = FakeBrew([.done, .done])
    #expect(upgradeCarrier(installed: "0.1.0", app: "0.1.4", brew: brew.run) == .upgraded)
    #expect(brew.ran.map(\.arguments) == [["update"], ["upgrade", "--formula", "ashulab/tap/carrier"]])
    #expect(brew.ran.last?.environment == ["HOMEBREW_NO_ASK": "1"])
}

@Test func anEqualNewerOrUnreadableCarrierRunsNothingAndSaysNothing() {
    for installed in ["0.1.4", "0.2.0", "", "unknown"] {
        let brew = FakeBrew([])
        #expect(upgradeCarrier(installed: installed, app: "0.1.4", brew: brew.run) == .notNeeded)
        #expect(brew.ran.isEmpty)
    }
    let brew = FakeBrew([])
    #expect(upgradeCarrier(installed: "0.1.0", app: "unknown", brew: brew.run) == .notNeeded)
    #expect(brew.ran.isEmpty)
}

@Test func aFailedUpdateNeverRunsTheUpgradeAndSaysWhy() {
    let brew = FakeBrew([.failed("Error: Another `brew update` process is already running.")])
    guard case .failed(let notice) = upgradeCarrier(installed: "0.1.0", app: "0.1.4", brew: brew.run) else {
        Issue.record("expected a notice"); return
    }
    #expect(brew.ran.map(\.arguments) == [["update"]])
    #expect(notice.title == carrierUpgradeFailedTitle)
    #expect(notice.line.contains("brew update"))
    #expect(notice.line.contains("Another `brew update` process is already running."))
}

@Test func aFailedUpgradeSaysWhy() {
    let brew = FakeBrew([.done, .failed("Warning: carrier is pinned")])
    guard case .failed(let notice) = upgradeCarrier(installed: "0.1.0", app: "0.1.4", brew: brew.run) else {
        Issue.record("expected a notice"); return
    }
    #expect(brew.ran.count == 2)
    #expect(notice.line.contains("brew upgrade"))
    #expect(notice.line.contains("carrier is pinned"))
}

@Test func aMissingBrewSaysSoAndRunsNothingMore() {
    let brew = FakeBrew([.brewMissing])
    guard case .failed(let notice) = upgradeCarrier(installed: "0.1.0", app: "0.1.4", brew: brew.run) else {
        Issue.record("expected a notice"); return
    }
    #expect(brew.ran.count == 1)
    #expect(notice.line.contains("/opt/homebrew/bin/brew"))
}

@Test func onlyAFailedEngineUpdateCanBeTriedAgainAndItCarriesItsNotice() {
    let notice = ChatHostNotice(title: carrierUpgradeFailedTitle, line: "`brew update` failed")
    #expect(EngineUpdateState.failed(notice).canRetry && EngineUpdateState.failed(notice).notice == notice)
    for state in [EngineUpdateState.unknown, .running, .upToDate, .updated] { #expect(state.canRetry == false && state.notice == nil) }
}

@Test func eachStateOfTheEngineUpdateHasItsOwnLine() {
    let lines = [EngineUpdateState.unknown, .running, .upToDate, .updated, .failed(ChatHostNotice(title: "t", line: "l"))].map(\.line)
    #expect(Set(lines).count == 5)
    #expect(EngineUpdateState.running.line == "Updating Carrier…")
}
