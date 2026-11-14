import Foundation
import Sparkle

/// Sparkle's standard updater. Its preferences are Sparkle's own: with the plist's `SUEnableAutomaticChecks` it checks by itself and,
/// until the person says otherwise, asks before it installs. A check the person asked for (Settings, the menu item, the sidebar's pill)
/// shows Sparkle's window; a scheduled one that finds an update shows nothing but the sidebar's pill (Sparkle's gentle reminders).
@MainActor
enum AppUpdater {
    private static var controller: SPUStandardUpdaterController?
    private static let reminder = UpdateReminder()

    /// What the Updates page reads and writes, and the menu item's target; nil while the updater is not started.
    static var updater: SPUUpdater? { controller?.updater }
    static var menuTarget: AnyObject? { controller }
    /// The version a scheduled check found and the person has not looked at yet; the sidebar's pill shows it.
    static var available: UpdateAvailable { reminder.available }

    /// Starts the updater and asks for a check in the background, because Sparkle alone checks at start only when the last check is
    /// older than its interval. Nothing starts under `--fixture` or `--selftest`, nor from a build whose bundle has no feed (`swift run`).
    /// `--fixture-update` shows the pill with a made-up version, so it can be looked at.
    static func start(arguments: [String] = CommandLine.arguments, bundle: Bundle = .main) {
        if arguments.contains("--fixture-update") { reminder.available.version = "9.9.9" }
        guard bundle.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        guard arguments.contains("--fixture") == false, arguments.contains("--selftest") == false else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: reminder)
        controller.updater.checkForUpdatesInBackground()
        self.controller = controller
    }

    /// The pill's action: Sparkle's window for the update it found, which brings the update into focus.
    static func showUpdate() {
        guard let updater else { return }
        updater.checkForUpdates()
    }
}

@MainActor @Observable final class UpdateAvailable {
    var version: String?
}

/// Takes the scheduled check's update away from Sparkle's window and gives it to the pill; Sparkle calls it on the main thread.
private final class UpdateReminder: NSObject, SPUStandardUserDriverDelegate {
    @MainActor let available = UpdateAvailable()

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool { false }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard handleShowingUpdate == false else { return }
        MainActor.assumeIsolated { available.version = update.displayVersionString }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated { available.version = nil }
    }

    func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { available.version = nil }
    }
}
