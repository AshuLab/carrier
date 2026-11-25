import AppKit
import CarrierCore
import Sparkle

/// Sparkle's updater with a user driver of our own: no Sparkle window, the sidebar's pill is the whole interface (the version, the
/// download's percent, Restart, Retry). Its preferences are Sparkle's own: with the plist's `SUEnableAutomaticChecks` it checks by itself.
/// A check the person asked for (Settings, the menu item) that finds nothing or fails says so in an alert.
/// The checks and installs by itself and the last check are read from Sparkle's own preferences (they are KVO-compliant) and written back to them.
@MainActor @Observable
final class AppUpdater: Updater {
    static let shared = AppUpdater()

    @ObservationIgnored private var driver: UpdateDriver?
    /// Sparkle holds its delegate weakly.
    @ObservationIgnored private var delay: UpdateDelay?
    @ObservationIgnored private var watching: [NSKeyValueObservation] = []
    private var sparkle: SPUUpdater?
    private let model = UpdateModel()
    private var checks = false
    private var installs = false
    private(set) var canCheck = false
    private(set) var lastCheck: Date?

    /// The menu item's target; nil while the updater is not started.
    static var menuTarget: AnyObject? { shared.driver }

    var isRunning: Bool { sparkle != nil }
    /// What the pill draws and what its click does.
    var flow: UpdateFlow { model.flow }
    func press() { model.press() }
    var checksAutomatically: Bool {
        get { checks }
        set { sparkle?.automaticallyChecksForUpdates = newValue }
    }
    var installsAutomatically: Bool {
        get { installs }
        set { sparkle?.automaticallyDownloadsUpdates = newValue }
    }
    func checkNow() { sparkle?.checkForUpdates() }

    /// Starts the updater and asks for a check in the background, because Sparkle alone checks at start only when the last check is
    /// older than its interval. Nothing starts under `--fixture` or `--selftest`, nor from a build whose bundle has no feed (`swift run`).
    /// `--fixture-update` plays the pill's whole course with a made-up version, so it can be looked at.
    func start(arguments: [String] = CommandLine.arguments, bundle: Bundle = .main) {
        if arguments.contains("--fixture-update") { playFixture() }
        guard bundle.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        guard arguments.contains("--fixture") == false, arguments.contains("--selftest") == false else { return }
        let driver = UpdateDriver(model: model)
        let delay = UpdateDelay()
        let updater = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: driver, delegate: delay)
        do {
            try updater.start()
        } catch {
            NSLog("Carrier: the updater did not start: %@", String(describing: error))
            return
        }
        driver.updater = updater
        model.press = { driver.press() }
        updater.checkForUpdatesInBackground()
        self.driver = driver
        self.delay = delay
        sparkle = updater
        refresh()
        watching = [
            updater.observe(\.automaticallyChecksForUpdates) { [weak self] _, _ in Task { @MainActor in self?.refresh() } },
            updater.observe(\.automaticallyDownloadsUpdates) { [weak self] _, _ in Task { @MainActor in self?.refresh() } },
            updater.observe(\.canCheckForUpdates) { [weak self] _, _ in Task { @MainActor in self?.refresh() } },
            updater.observe(\.lastUpdateCheckDate) { [weak self] _, _ in Task { @MainActor in self?.refresh() } },
        ]
    }

    private func refresh() {
        guard let sparkle else { return }
        checks = sparkle.automaticallyChecksForUpdates
        installs = sparkle.automaticallyDownloadsUpdates
        canCheck = sparkle.canCheckForUpdates
        lastCheck = sparkle.lastUpdateCheckDate
    }

    /// The fixture's course: available, a click downloads in a few seconds, a click restarts and the pill goes.
    private func playFixture() {
        let model = model
        model.flow.found(version: "9.9.9", downloaded: false)
        model.press = {
            switch model.flow.phase {
            case .available:
                Task {
                    model.flow.downloadStarted()
                    model.flow.expect(100)
                    for _ in 0..<20 {
                        try? await Task.sleep(for: .milliseconds(200))
                        model.flow.receive(5)
                    }
                    model.flow.readyToInstall()
                }
            case .ready:
                Task {
                    model.flow.installing()
                    try? await Task.sleep(for: .seconds(2))
                    model.flow.dismissed()
                }
            default: break
            }
        }
    }
}

/// Holds back a release the person chose to wait for (Settings > About > Update delay): a check Sparkle makes by itself that finds one younger than
/// the delay ends as "no update", which the driver takes as a quiet nothing, not as a failure. A check the person asks for and a critical update go through.
final class UpdateDelay: NSObject, SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate updateItem: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
        guard updateCheck == .updatesInBackground, updateItem.isCriticalUpdate == false else { return }
        let days = AppPreferences().updateDelayDays
        guard updateIsOldEnough(published: updateItem.date, now: Date(), delayDays: days) == false else { return }
        throw NSError(domain: SUSparkleErrorDomain, code: Int(SUError.noUpdateError.rawValue), userInfo: [NSLocalizedDescriptionKey: "Version \(updateItem.displayVersionString) is under \(days) days old"])
    }
}

@MainActor @Observable final class UpdateModel {
    var flow = UpdateFlow()
    @ObservationIgnored var press: () -> Void = {}
}

/// Tells the pill what Sparkle is doing and answers Sparkle when the pill is clicked. Sparkle calls it on the main thread.
@MainActor
final class UpdateDriver: NSObject, SPUUserDriver, NSMenuItemValidation {
    private let model: UpdateModel
    weak var updater: SPUUpdater?
    /// Sparkle's question that waits for the click: install the update found, or restart into the one downloaded.
    private var choice: ((SPUUserUpdateChoice) -> Void)?
    /// The person clicked Restart on an update Sparkle had downloaded before: the next "ready to relaunch" needs no second click.
    private var restartChosen = false
    /// Retry checks again and downloads what it finds without waiting for a click.
    private var installOnFind = false
    private var userInitiated = false
    /// Sparkle's way to send the quit again, given while the app has not closed: a quit the app cancelled or delayed (a terminal asking before it closes) leaves the update waiting, and the click on Restarting… tries again.
    private var retryQuit: (() -> Void)?

    init(model: UpdateModel) { self.model = model }

    func press() {
        switch model.flow.phase {
        case .available:
            answer(.install)
        case .ready:
            restartChosen = true
            answer(.install)
        case .failed:
            installOnFind = true
            updater?.checkForUpdates()
        case .installing:
            retryQuit?()
        case .none, .downloading:
            break
        }
    }

    private func answer(_ reply: SPUUserUpdateChoice) {
        let waiting = choice
        choice = nil
        waiting?(reply)
    }

    @objc func checkForUpdates(_ sender: Any?) { updater?.checkForUpdates() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { updater?.canCheckForUpdates ?? false }

    // MARK: SPUUserDriver

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) { userInitiated = true }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        userInitiated = false
        choice = reply
        model.flow.found(version: appcastItem.displayVersionString, downloaded: state.stage != .notDownloaded)
        if installOnFind {
            installOnFind = false
            press()
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        if userInitiated { NSAlert(error: error).runModal() }
        userInitiated = false
        acknowledgement()
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        NSLog("Carrier: the update failed: %@", String(describing: error))
        installOnFind = false
        model.flow.failed()
        // an error on the way shows as Retry on the pill; one of a check the person asked for, as an alert
        if userInitiated, model.flow.phase == .none { NSAlert(error: error).runModal() }
        userInitiated = false
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) { model.flow.downloadStarted() }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) { model.flow.expect(expectedContentLength) }

    func showDownloadDidReceiveData(ofLength length: UInt64) { model.flow.receive(length) }

    func showDownloadDidStartExtractingUpdate() {}

    func showExtractionReceivedProgress(_ progress: Double) {}

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        choice = reply
        if restartChosen { answer(.install) } else { model.flow.readyToInstall() }
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        // the app not having closed yet is normal for a moment; a pill still saying Restarting… after that is what the log is for
        NSLog("Carrier: installing the update, application terminated: %@", applicationTerminated ? "yes" : "no")
        retryQuit = applicationTerminated ? nil : retryTerminatingApplication
        model.flow.installing()
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { acknowledgement() }

    func dismissUpdateInstallation() {
        choice = nil
        retryQuit = nil
        restartChosen = false
        model.flow.dismissed()
    }
}
