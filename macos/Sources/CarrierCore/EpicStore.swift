import Foundation
import Observation

/// What the epic view reads: the latest replies per epic (set on the main thread, from the poller's updates) and what the user
/// folded. The poller is fed by the window's monitor, once per snapshot.
@Observable public final class EpicStore {
    public internal(set) var data: [EpicRef: EpicData] = [:]
    public var folds = SessionFolds()
    /// Whether the engine's hello lists `resumeEpic`.
    public internal(set) var canResume = false
    /// Whether the engine's hello lists `fileDiff`: without it the file rows do not open.
    public internal(set) var canOpenFiles = false
    /// The file rows opened in each epic's Files changed tab.
    public var openFiles: [EpicRef: Set<OpenFile>] = [:]
    /// Whether the Files changed tab is the one on screen: the open rows are asked for their fragments only then.
    public var filesTabShown = false
    /// The epics whose Resume was confirmed and has not ended: kept here and not in the card's view, which is rebuilt when another
    /// epic is selected. An answered request ends it at once when it was refused; when it succeeded, the snapshot ending the stuck
    /// state does (`settleResuming`).
    public internal(set) var resuming: Set<EpicRef> = []
    /// When the engine said each resumed epic had started (ms since epoch). A snapshot generated after that which still shows the
    /// epic stopped means it stopped again, so the Resume is over.
    private var resumedAt: [EpicRef: Int] = [:]
    /// What the engine last refused per epic, in the app's words, until the epic is resumed again or leaves needs-human.
    public internal(set) var resumeRefusals: [EpicRef: String] = [:]
    @ObservationIgnored public private(set) var poller: EpicPoller!

    public init() {
        poller = EpicPoller(
            onCapabilities: { [weak self] capabilities in
                DispatchQueue.main.async {
                    self?.canResume = capabilities.contains(.resumeEpic)
                    self?.canOpenFiles = capabilities.contains(.fileDiff)
                }
            },
            onUpdate: { [weak self] key, value in DispatchQueue.main.async { self?.data[key] = value } }
        )
    }

    public func startResuming(_ epic: EpicRef) {
        resuming.insert(epic)
        resumeRefusals[epic] = nil
    }

    /// The engine answered: `refusal` is its words when it did not resume the epic. A resumed epic stays in `resuming` until the
    /// snapshot shows it out of needs-human, or shows it stopped again after this answer.
    public func answeredResume(_ epic: EpicRef, refusal: String?, at now: Int = Int(Date().timeIntervalSince1970 * 1000)) {
        guard let refusal else {
            resumedAt[epic] = now
            return
        }
        resuming.remove(epic)
        resumeRefusals[epic] = refusal
    }

    /// Drops what no longer applies: an epic that is not in needs-human any more has been resumed, one that is gone is no one's, and
    /// one a snapshot newer than the engine's answer still shows stopped has stopped again.
    public func settleResuming(_ snapshot: PanelSnapshot) {
        let stopped = Set(snapshot.epics.filter { $0.status == .needsHuman }.map { EpicRef(repo: $0.repo, issue: $0.issue) })
        let stoppedAgain = Set(resumedAt.filter { stopped.contains($0.key) && $0.value < snapshot.now }.keys)
        resuming.formIntersection(stopped.subtracting(stoppedAgain))
        resumedAt = resumedAt.filter { resuming.contains($0.key) }
        resumeRefusals = resumeRefusals.filter { stopped.contains($0.key) }
    }
}
