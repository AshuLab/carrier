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
    #expect(UpdatePhase.none.settingsDetail == nil)
    #expect(UpdatePhase.none.settingsAction == nil)
    #expect(UpdatePhase.available(version: version).settingsDetail == "Carrier 0.9.0 is available")
    #expect(UpdatePhase.downloading(version: version, percent: 42).settingsDetail == "Downloading Carrier 0.9.0, 42%")
    #expect(UpdatePhase.ready(version: version).settingsDetail == "Carrier 0.9.0 is downloaded and waits for a restart")
    #expect(UpdatePhase.installing.settingsDetail == "Restarting…")
    #expect(UpdatePhase.failed(version: version).settingsDetail == "Carrier 0.9.0 could not be updated")
}

@Test func theSettingsButtonKeepsItsWordsWhileItsStepRuns() {
    let available = UpdatePhase.available(version: "0.9.0").settingsAction
    #expect(available == UpdateAction(title: "Update", symbol: .downloadTray, working: false))
    #expect(UpdatePhase.downloading(version: "0.9.0", percent: 5).settingsAction == UpdateAction(title: "Update", symbol: .downloadTray, working: true))
    #expect(UpdatePhase.ready(version: "0.9.0").settingsAction == UpdateAction(title: "Restart", symbol: .refresh, working: false))
    #expect(UpdatePhase.installing.settingsAction == UpdateAction(title: "Restart", symbol: .refresh, working: true))
    #expect(UpdatePhase.failed(version: "0.9.0").settingsAction == UpdateAction(title: "Retry", symbol: .refresh, working: false))
}
