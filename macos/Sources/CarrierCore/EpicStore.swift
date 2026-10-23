import Foundation
import Observation

/// What the epic view reads: the latest replies per epic (set on the main thread, from the poller's updates) and what the user
/// folded. The poller is fed by the window's monitor, once per snapshot.
@Observable public final class EpicStore {
    public internal(set) var data: [EpicRef: EpicData] = [:]
    public var folds = SessionFolds()
    /// Whether the engine's hello lists `resumeEpic`.
    public internal(set) var canResume = false
    @ObservationIgnored public private(set) var poller: EpicPoller!

    public init() {
        poller = EpicPoller(
            onCapabilities: { [weak self] capabilities in DispatchQueue.main.async { self?.canResume = capabilities.contains(.resumeEpic) } },
            onUpdate: { [weak self] key, value in DispatchQueue.main.async { self?.data[key] = value } }
        )
    }
}
