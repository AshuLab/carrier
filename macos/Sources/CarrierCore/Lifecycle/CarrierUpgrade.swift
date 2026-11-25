import Foundation

// What the app does about an installed `carrier` older than the app: upgrade it through Homebrew, once, without asking (the person
// accepted the app update), and say why when that fails. The run itself (spawn, log) is the shell's; here is the decision and the sequence.

/// The one `brew` the app runs: the one of the Homebrew prefix of this build's architecture.
public let brewPath = homebrewBin + "/brew"

/// The arguments and the extra environment of one `brew` run.
public struct BrewCommand: Equatable {
    public let arguments: [String]
    public let environment: [String: String]
}

public let brewUpdateCommand = BrewCommand(arguments: ["update"], environment: [:])
/// The qualified name, because the bare one is also the cask's; `HOMEBREW_NO_ASK` so a prompt never waits in a job with no terminal.
public let carrierUpgradeCommand = BrewCommand(
    arguments: ["upgrade", "--formula", "ashulab/tap/carrier"], environment: ["HOMEBREW_NO_ASK": "1"]
)

/// How one `brew` run ended; `failed` carries the last lines of its log.
public enum BrewOutcome: Equatable {
    case done, failed(String), brewMissing
}

public enum CarrierUpgrade: Equatable {
    case notNeeded, upgraded
    case failed(ChatHostNotice)
}

public func carrierUpgradeFailedTitle(bundle: Bundle? = nil, locale: Locale = .current) -> String { Copy.lifecycleUpgradeFailedTitle(bundle: bundle, locale: locale) }

/// A version that cannot be read, on either side, is never older. `1.2` and `1.2.0` are the same.
public func carrierIsOlder(installed: String, app: String) -> Bool {
    hostReplacement(running: installed, installed: app, working: false) != .keep
}

/// Runs `brew update` and then the upgrade when the installed `carrier` is older than the app, one after the other; a failed
/// update does not go on to the upgrade. Nothing is retried.
public func upgradeCarrier(installed: String, app: String, brew: (BrewCommand) -> BrewOutcome, bundle: Bundle? = nil, locale: Locale = .current) -> CarrierUpgrade {
    guard carrierIsOlder(installed: installed, app: app) else { return .notNeeded }
    for (name, command) in [("brew update", brewUpdateCommand), ("brew upgrade", carrierUpgradeCommand)] {
        switch brew(command) {
        case .done: continue
        case .brewMissing:
            return .failed(ChatHostNotice(title: carrierUpgradeFailedTitle(bundle: bundle, locale: locale), line: Copy.lifecycleUpgradeBrewMissing(path: brewPath, bundle: bundle, locale: locale)))
        case .failed(let tail):
            return .failed(ChatHostNotice(title: carrierUpgradeFailedTitle(bundle: bundle, locale: locale), line: Copy.lifecycleUpgradeBrewFailed(command: name, tail: tail, bundle: bundle, locale: locale)))
        }
    }
    return .upgraded
}

/// Where the engine's own update stands, for the Updates page: only a Homebrew `carrier` older than the app is upgraded, so anything else
/// stays `unknown`. A failure carries the notice this page shows, and the page also lets a person try again.
public enum EngineUpdateState: Equatable {
    case unknown, running, upToDate, updated
    case failed(ChatHostNotice)

    public func line(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        switch self {
        case .unknown: Copy.lifecycleEngineUpdateUnknown(bundle: bundle, locale: locale)
        case .running: Copy.lifecycleEngineUpdateRunning(bundle: bundle, locale: locale)
        case .upToDate: Copy.lifecycleEngineUpToDate(bundle: bundle, locale: locale)
        case .updated: Copy.lifecycleEngineUpdated(bundle: bundle, locale: locale)
        case .failed: Copy.lifecycleEngineUpdateFailed(bundle: bundle, locale: locale)
        }
    }

    public var notice: ChatHostNotice? { if case .failed(let notice) = self { notice } else { nil } }
    public var canRetry: Bool { notice != nil }
}
