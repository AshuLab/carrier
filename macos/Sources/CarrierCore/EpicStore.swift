import Foundation
import Observation

/// What the epic view reads: the latest replies per epic (set on the main thread, from the poller's updates) and what the user
/// folded. The poller is fed by the window's monitor, once per snapshot.
@Observable public final class EpicStore {
    public internal(set) var data: [EpicRef: EpicData] = [:]
    public var folds = SessionFolds()
    @ObservationIgnored public private(set) var poller: EpicPoller!

    public init() {
        poller = EpicPoller { [weak self] key, value in DispatchQueue.main.async { self?.data[key] = value } }
    }
}
