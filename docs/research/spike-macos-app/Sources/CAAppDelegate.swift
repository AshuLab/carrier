import AppKit
import SwiftUI

let sharedNotifier = Notifier()

final class CAAppDelegate: NSObject, NSApplicationDelegate {
    var controller: CAStatusController?
    var window: NSWindow?

    func applicationDidFinishLaunching(_ n: Notification) {
        Store.shared.openWindowHook = { [weak self] in self?.openMain() }
        controller = CAStatusController()
        if let f = ProcessInfo.processInfo.environment["SPIKE_SELFTEST"] {
            try? FileManager.default.removeItem(atPath: f)
            controller?.selfTest(logPath: f)
        }
    }

    // A menu bar app keeps running with no windows.
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { false }

    func openMain() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: RootView(store: Store.shared, notifier: sharedNotifier)))
            w.title = "Carrier spike"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
            sharedNotifier.setup()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
