import Foundation

/// What the sidebar's update pill shows. Sparkle's user driver (`AppUpdater`) moves it; the pill only draws it.
public enum UpdatePhase: Equatable, Sendable {
    case none
    case available(version: String)
    case downloading(version: String, percent: Int)
    case ready(version: String)
    case installing
    case failed(version: String)
}

/// The button of Settings > Updates > This Carrier while an update is on its way: the pill's own step, drawn as a button.
public struct UpdateAction: Equatable, Sendable {
    public let title: String
    public let symbol: AppIcon
    /// The step is running (a download, a restart): the button keeps its words, is dimmed and shows a spinner beside it.
    public let working: Bool
}

extension UpdatePhase {
    /// What Settings > Updates says about this Carrier while an update is on its way, in place of the time of the last check; nil with nothing new.
    public func settingsDetail(bundle: Bundle? = nil, locale: Locale = .current) -> String? {
        switch self {
        case .none: nil
        case .available(let version): Copy.updatesAvailable(version: version, bundle: bundle, locale: locale)
        case .downloading(let version, let percent): Copy.updatesDownloading(version: version, percent: percent, bundle: bundle, locale: locale)
        case .ready(let version): Copy.updatesDownloaded(version: version, bundle: bundle, locale: locale)
        case .installing: Copy.updatesRestarting(bundle: bundle, locale: locale)
        case .failed(let version): Copy.updatesFailed(version: version, bundle: bundle, locale: locale)
        }
    }

    /// What the sidebar's pill says to the pointer and to VoiceOver; `justDownloaded` is the moment after the download ends, before Restart shows. Empty with nothing new.
    public func pillHelp(justDownloaded: Bool, bundle: Bundle? = nil, locale: Locale = .current) -> String {
        switch self {
        case .none: ""
        case .available(let version): Copy.updatesHelpAvailable(version: version, bundle: bundle, locale: locale)
        case .downloading(let version, let percent): Copy.updatesHelpDownloading(version: version, percent: percent, bundle: bundle, locale: locale)
        case .ready(let version): justDownloaded ? Copy.updatesHelpDownloaded(version: version, bundle: bundle, locale: locale) : Copy.updatesHelpRestart(version: version, bundle: bundle, locale: locale)
        case .installing: Copy.updatesHelpRestarting(bundle: bundle, locale: locale)
        case .failed(let version): Copy.updatesHelpFailed(version: version, bundle: bundle, locale: locale)
        }
    }

    /// The button that moves the update one step, the same click as the sidebar's pill; nil when there is no update.
    public func settingsAction(bundle: Bundle? = nil, locale: Locale = .current) -> UpdateAction? {
        switch self {
        case .none: nil
        case .available: UpdateAction(title: Copy.updatesActionUpdate(bundle: bundle, locale: locale), symbol: .downloadTray, working: false)
        case .downloading: UpdateAction(title: Copy.updatesActionUpdate(bundle: bundle, locale: locale), symbol: .downloadTray, working: true)
        case .ready: UpdateAction(title: Copy.updatesActionRestart(bundle: bundle, locale: locale), symbol: .refresh, working: false)
        case .installing: UpdateAction(title: Copy.updatesActionRestart(bundle: bundle, locale: locale), symbol: .refresh, working: true)
        case .failed: UpdateAction(title: Copy.updatesActionRetry(bundle: bundle, locale: locale), symbol: .refresh, working: false)
        }
    }
}

/// The phase and the bytes of the download behind it, moved by what Sparkle tells the app, one call a step.
public struct UpdateFlow: Equatable, Sendable {
    public private(set) var phase = UpdatePhase.none
    private var version = ""
    private var expected: UInt64 = 0
    private var received: UInt64 = 0

    public init() {}

    /// A check found `version`; Sparkle may have downloaded it already (it then only needs a restart).
    public mutating func found(version: String, downloaded: Bool) {
        self.version = version
        phase = downloaded ? .ready(version: version) : .available(version: version)
    }

    public mutating func downloadStarted() {
        expected = 0
        received = 0
        phase = .downloading(version: version, percent: 0)
    }

    /// Sparkle sends the length again when a download starts over.
    public mutating func expect(_ length: UInt64) {
        expected = length
        received = 0
    }

    /// The percent stays under 100 until the update is ready to install, so the pill never says 100% while it still extracts.
    public mutating func receive(_ length: UInt64) {
        received += length
        let percent = expected > 0 ? min(99, Int(received * 100 / expected)) : 0
        phase = .downloading(version: version, percent: percent)
    }

    public mutating func readyToInstall() { phase = .ready(version: version) }

    public mutating func installing() { phase = .installing }

    /// An error while an update was on its way (or while retrying one) leaves Retry; an error of a check with nothing found leaves nothing.
    public mutating func failed() {
        switch phase {
        case .downloading, .ready, .installing, .failed: phase = .failed(version: version)
        case .none, .available: phase = .none
        }
    }

    /// Sparkle closed the update session: the pill goes, unless it is offering to retry.
    public mutating func dismissed() {
        if case .failed = phase { return }
        phase = .none
    }
}
