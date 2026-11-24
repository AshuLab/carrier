import AppKit
import CarrierCore

/// What waits for the window's first frame: it runs once Core Animation has committed it, never before.
/// The app's launch is two phases: what the first frame needs, built in `applicationDidFinishLaunching`, and what can wait, queued here.
@MainActor final class LaunchPhases {
    static let shared = LaunchPhases()

    private var pending: [@MainActor () -> Void] = []
    private(set) var drawn = false

    /// Runs `work` after the first frame; at once when it has been drawn already, in the order queued otherwise.
    func afterFirstFrame(_ work: @escaping @MainActor () -> Void) {
        if drawn { return work() }
        pending.append(work)
    }

    /// Called after the first `makeKeyAndOrderFront`: the next pass of the run loop commits the frame, and this observer runs after that commit.
    func windowOrdered() {
        guard drawn == false else { return }
        // Core Animation commits at order 2_000_000 of beforeWaiting; one after it sees the frame committed
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false, 2_000_001) { _, _ in
            MainActor.assumeIsolated { self.fire() }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    /// Runs what was queued, once: the observer calls it, and so does the timer of a launch with no window (a self-test).
    func fire() {
        guard drawn == false else { return }
        drawn = true
        Signposts.launch.emitEvent("first frame")
        let work = pending
        pending = []
        work.forEach { $0() }
    }
}
