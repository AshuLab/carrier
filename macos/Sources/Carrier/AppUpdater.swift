import Foundation
import Sparkle

/// Sparkle's standard updater. Its preferences are Sparkle's own: with the plist's `SUEnableAutomaticChecks` it checks by itself and,
/// until the person says otherwise, asks before it installs. Its windows are Sparkle's own; ours are the Updates page of Settings and the menu item.
@MainActor
enum AppUpdater {
    private static var controller: SPUStandardUpdaterController?

    /// What the Updates page reads and writes, and the menu item's target; nil while the updater is not started.
    static var updater: SPUUpdater? { controller?.updater }
    static var menuTarget: AnyObject? { controller }

    /// Starts the updater and asks for a check in the background, because Sparkle alone checks at start only when the last check is
    /// older than its interval. Nothing starts under `--fixture` or `--selftest`, nor from a build whose bundle has no feed (`swift run`).
    static func start(arguments: [String] = CommandLine.arguments, bundle: Bundle = .main) {
        guard bundle.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        guard arguments.contains("--fixture") == false, arguments.contains("--selftest") == false else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        controller.updater.checkForUpdatesInBackground()
        self.controller = controller
    }
}
