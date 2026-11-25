import Testing
@testable import CarrierCore

@Test func aDownloadGoesFromTheVersionToItsPercentToRestart() {
    var flow = UpdateFlow()
    flow.found(version: "0.5.1", downloaded: false)
    #expect(flow.phase == .available(version: "0.5.1"))
    flow.downloadStarted()
    flow.expect(200)
    flow.receive(50)
    #expect(flow.phase == .downloading(version: "0.5.1", percent: 25))
    flow.receive(150)
    #expect(flow.phase == .downloading(version: "0.5.1", percent: 99))
    flow.readyToInstall()
    #expect(flow.phase == .ready(version: "0.5.1"))
    flow.installing()
    flow.dismissed()
    #expect(flow.phase == .none)
}

@Test func aDownloadThatStartsOverCountsFromZero() {
    var flow = UpdateFlow()
    flow.found(version: "1.0.0", downloaded: false)
    flow.downloadStarted()
    flow.receive(10)
    #expect(flow.phase == .downloading(version: "1.0.0", percent: 0))
    flow.expect(100)
    flow.receive(40)
    flow.expect(100)
    flow.receive(10)
    #expect(flow.phase == .downloading(version: "1.0.0", percent: 10))
}

@Test func anErrorOnTheWayLeavesRetryAndAFailedCheckLeavesNothing() {
    var flow = UpdateFlow()
    flow.found(version: "0.5.1", downloaded: false)
    flow.downloadStarted()
    flow.failed()
    flow.dismissed()
    #expect(flow.phase == .failed(version: "0.5.1"))
    flow.failed()
    #expect(flow.phase == .failed(version: "0.5.1"))

    var check = UpdateFlow()
    check.failed()
    #expect(check.phase == .none)
}

@Test func anUpdateAlreadyDownloadedOnlyNeedsARestart() {
    var flow = UpdateFlow()
    flow.found(version: "0.6.0", downloaded: true)
    #expect(flow.phase == .ready(version: "0.6.0"))
}

@Test func settingsSaysWhereTheUpdateIsAndOffersTheNextClick() {
    let version = "0.9.0"
    func detail(_ phase: UpdatePhase) -> String? { phase.settingsDetail(bundle: english.bundle, locale: english.locale) }
    #expect(detail(.none) == nil)
    #expect(UpdatePhase.none.settingsAction(bundle: english.bundle, locale: english.locale) == nil)
    #expect(detail(.available(version: version)) == "Carrier 0.9.0 is available")
    #expect(detail(.downloading(version: version, percent: 42)) == "Downloading Carrier 0.9.0, 42%")
    #expect(detail(.ready(version: version)) == "Carrier 0.9.0 is downloaded and waits for a restart")
    #expect(detail(.installing) == "Restarting…")
    #expect(detail(.failed(version: version)) == "Carrier 0.9.0 could not be updated")
}

@Test func theSettingsButtonKeepsItsWordsWhileItsStepRuns() {
    func action(_ phase: UpdatePhase) -> UpdateAction? { phase.settingsAction(bundle: english.bundle, locale: english.locale) }
    #expect(action(.available(version: "0.9.0")) == UpdateAction(title: "Update", symbol: .downloadTray, working: false))
    #expect(action(.downloading(version: "0.9.0", percent: 5)) == UpdateAction(title: "Update", symbol: .downloadTray, working: true))
    #expect(action(.ready(version: "0.9.0")) == UpdateAction(title: "Restart", symbol: .refresh, working: false))
    #expect(action(.installing) == UpdateAction(title: "Restart", symbol: .refresh, working: true))
    #expect(action(.failed(version: "0.9.0")) == UpdateAction(title: "Retry", symbol: .refresh, working: false))
}

@Test func thePillTellsThePointerWhereTheUpdateIs() {
    func help(_ phase: UpdatePhase, justDownloaded: Bool = false) -> String { phase.pillHelp(justDownloaded: justDownloaded, bundle: english.bundle, locale: english.locale) }
    #expect(help(.none) == "")
    #expect(help(.available(version: "0.9.0")) == "Download Carrier 0.9.0")
    #expect(help(.downloading(version: "0.9.0", percent: 42)) == "Downloading Carrier 0.9.0, 42 percent")
    #expect(help(.ready(version: "0.9.0"), justDownloaded: true) == "Carrier 0.9.0 is downloaded")
    #expect(help(.ready(version: "0.9.0")) == "Restart to update to Carrier 0.9.0")
    #expect(help(.installing) == "Restarting. If Carrier does not close, click to ask it again")
    #expect(help(.failed(version: "0.9.0")) == "The download of Carrier 0.9.0 failed. Retry")
}

@Test func theUpdateSaysItsWordsInSpanish() {
    let version = "0.9.0"
    func detail(_ phase: UpdatePhase) -> String? { phase.settingsDetail(bundle: spanish.bundle, locale: spanish.locale) }
    func action(_ phase: UpdatePhase) -> String? { phase.settingsAction(bundle: spanish.bundle, locale: spanish.locale)?.title }
    func help(_ phase: UpdatePhase, justDownloaded: Bool = false) -> String { phase.pillHelp(justDownloaded: justDownloaded, bundle: spanish.bundle, locale: spanish.locale) }
    #expect(detail(.none) == nil)
    #expect(detail(.available(version: version)) == "Carrier 0.9.0 está disponible")
    #expect(detail(.downloading(version: version, percent: 42)) == "Descargando Carrier 0.9.0, 42 %")
    #expect(detail(.ready(version: version)) == "Carrier 0.9.0 está descargado y espera un reinicio")
    #expect(detail(.installing) == "Reiniciando…")
    #expect(detail(.failed(version: version)) == "No se pudo actualizar Carrier 0.9.0")
    #expect(action(.available(version: version)) == "Actualizar")
    #expect(action(.ready(version: version)) == "Reiniciar")
    #expect(action(.failed(version: version)) == "Reintentar")
    #expect(help(.available(version: version)) == "Descargar Carrier 0.9.0")
    #expect(help(.downloading(version: version, percent: 42)) == "Descargando Carrier 0.9.0, 42 por ciento")
    #expect(help(.ready(version: version), justDownloaded: true) == "Carrier 0.9.0 está descargado")
    #expect(help(.ready(version: version)) == "Reinicia para actualizar a Carrier 0.9.0")
    #expect(help(.installing) == "Reiniciando. Si Carrier no se cierra, haz clic para pedírselo de nuevo")
    #expect(help(.failed(version: version)) == "La descarga de Carrier 0.9.0 falló. Reintenta")
}

@Test func theUpdateDelayReadsAsDaysInBothLanguages() {
    #expect(updateDelayChoices.map { Copy.updatesDelay(days: $0, bundle: english.bundle, locale: english.locale) } == ["None", "1 day", "3 days", "7 days", "14 days", "30 days"])
    #expect(updateDelayChoices.map { Copy.updatesDelay(days: $0, bundle: spanish.bundle, locale: spanish.locale) } == ["Ninguno", "1 día", "3 días", "7 días", "14 días", "30 días"])
}

@Test func aPercentGroupsForTheLocaleAndSpanishSpacesItsSign() {
    #expect(Copy.updatesPillPercent(percent: 42, bundle: english.bundle, locale: english.locale) == "42%")
    #expect(Copy.updatesPillPercent(percent: 42, bundle: spanish.bundle, locale: spanish.locale) == "42 %")
    #expect(Copy.lifecycleProgressPercent(percent: 100, bundle: english.bundle, locale: english.locale) == "100%")
    #expect(Copy.lifecycleProgressPercent(percent: 100, bundle: spanish.bundle, locale: spanish.locale) == "100 %")
}
