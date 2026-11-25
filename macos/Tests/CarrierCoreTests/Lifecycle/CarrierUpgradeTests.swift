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
    #expect(upgradeCarrier(installed: "0.1.0", app: "0.1.4", brew: brew.run, bundle: english.bundle, locale: english.locale) == .upgraded)
    #expect(brew.ran.map(\.arguments) == [["update"], ["upgrade", "--formula", "ashulab/tap/carrier"]])
    #expect(brew.ran.last?.environment == ["HOMEBREW_NO_ASK": "1"])
}

@Test func anEqualNewerOrUnreadableCarrierRunsNothingAndSaysNothing() {
    for installed in ["0.1.4", "0.2.0", "", "unknown"] {
        let brew = FakeBrew([])
        #expect(upgradeCarrier(installed: installed, app: "0.1.4", brew: brew.run, bundle: english.bundle, locale: english.locale) == .notNeeded)
        #expect(brew.ran.isEmpty)
    }
    let brew = FakeBrew([])
    #expect(upgradeCarrier(installed: "0.1.0", app: "unknown", brew: brew.run, bundle: english.bundle, locale: english.locale) == .notNeeded)
    #expect(brew.ran.isEmpty)
}

@Test func aFailedUpdateNeverRunsTheUpgradeAndSaysWhy() {
    let brew = FakeBrew([.failed("Error: Another `brew update` process is already running.")])
    guard case .failed(let notice) = upgradeCarrier(installed: "0.1.0", app: "0.1.4", brew: brew.run, bundle: english.bundle, locale: english.locale) else {
        Issue.record("expected a notice"); return
    }
    #expect(brew.ran.map(\.arguments) == [["update"]])
    #expect(notice.title == "Carrier could not be updated")
    #expect(notice.line.contains("brew update"))
    #expect(notice.line.contains("Another `brew update` process is already running."))
}

@Test func aFailedUpgradeSaysWhy() {
    let brew = FakeBrew([.done, .failed("Warning: carrier is pinned")])
    guard case .failed(let notice) = upgradeCarrier(installed: "0.1.0", app: "0.1.4", brew: brew.run, bundle: english.bundle, locale: english.locale) else {
        Issue.record("expected a notice"); return
    }
    #expect(brew.ran.count == 2)
    #expect(notice.line.contains("brew upgrade"))
    #expect(notice.line.contains("carrier is pinned"))
}

@Test func aMissingBrewSaysSoAndRunsNothingMore() {
    let brew = FakeBrew([.brewMissing])
    guard case .failed(let notice) = upgradeCarrier(installed: "0.1.0", app: "0.1.4", brew: brew.run, bundle: english.bundle, locale: english.locale) else {
        Issue.record("expected a notice"); return
    }
    #expect(brew.ran.count == 1)
    #expect(notice.line.contains(homebrewBin + "/brew"))
}

@Test func onlyAFailedEngineUpdateCanBeTriedAgainAndItCarriesItsNotice() {
    let notice = ChatHostNotice(title: "Carrier could not be updated", line: "`brew update` failed")
    #expect(EngineUpdateState.failed(notice).canRetry && EngineUpdateState.failed(notice).notice == notice)
    for state in [EngineUpdateState.unknown, .running, .upToDate, .updated] { #expect(state.canRetry == false && state.notice == nil) }
}

@Test func eachStateOfTheEngineUpdateHasItsOwnLine() {
    let lines = [EngineUpdateState.unknown, .running, .upToDate, .updated, .failed(ChatHostNotice(title: "t", line: "l"))].map { $0.line(bundle: english.bundle, locale: english.locale) }
    #expect(Set(lines).count == 5)
    #expect(EngineUpdateState.running.line(bundle: english.bundle, locale: english.locale) == "Updating Carrier…")
}

@Test func theUpgradeFailuresAndTheEngineUpdateLinesAreSaidInSpanish() {
    guard case .failed(let notice) = upgradeCarrier(installed: "0.1.0", app: "0.1.4", brew: FakeBrew([.done, .failed("pinned")]).run, bundle: spanish.bundle, locale: spanish.locale) else {
        Issue.record("expected a notice"); return
    }
    #expect(notice.title == "No se pudo actualizar Carrier")
    #expect(notice.line == "`brew upgrade` falló, así que la app conservó el Carrier que tiene:\npinned")
    guard case .failed(let missing) = upgradeCarrier(installed: "0.1.0", app: "0.1.4", brew: FakeBrew([.brewMissing]).run, bundle: spanish.bundle, locale: spanish.locale) else {
        Issue.record("expected a notice"); return
    }
    #expect(missing.line == "No se encontró Homebrew en \(brewPath). La app conservó el Carrier que tiene.")
    let lines = [EngineUpdateState.unknown, .running, .upToDate, .updated, .failed(notice)].map { $0.line(bundle: spanish.bundle, locale: spanish.locale) }
    #expect(lines == ["Se revisa al abrir la app, para un Carrier instalado con Homebrew", "Actualizando Carrier…", "Al día", "Actualizado", "No se pudo actualizar"])
}
