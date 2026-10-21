import AppKit
import Observation
import CarrierCore
import SwiftUI

/// What the window shows: nil until the first answer from Carrier.
@Observable final class PanelModel {
    var state: ConnectionState?
}

/// Set from the main thread, read from the monitor's.
private final class StopFlag {
    private let lock = NSLock()
    private var stopped = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    func set() { lock.lock(); stopped = true; lock.unlock() }
}

/// The window: a plain NSWindow kept for the life of the app, with the SwiftUI panel inside. It has its own monitor of
/// Carrier, started when the window opens and stopped when it closes, so a closed window costs nothing.
final class WindowController: NSObject {
    static let shared = WindowController()

    private let model = PanelModel()
    private var window: NSWindow?
    private var stop: StopFlag?

    /// Adds the "Open window" item at the end of the menu.
    func addMenuItem(to menu: NSMenu) {
        let item = menu.addItem(withTitle: "Open window", action: #selector(openFromMenu), keyEquivalent: "")
        item.target = self
    }

    @objc private func openFromMenu() { open() }

    func open() {
        let window = window ?? makeWindow()
        self.window = window
        if stop == nil { startMonitor() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() { window?.close() }

    /// For the self-test: whether the window is on screen and whether its monitor runs.
    var status: String { "visible \(window?.isVisible == true), monitor \(stop != nil)" }

    private func makeWindow() -> NSWindow {
        let host = NSHostingController(rootView: PanelView(model: model))
        // the split view's title and toolbar (the sidebar toggle) go to the window
        host.sceneBridgingOptions = .all
        let window = NSWindow(contentViewController: host)
        window.title = "Carrier"
        // full size content: the sidebar runs up behind the title bar, as Liquid Glass sidebars do
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 900, height: 640))
        window.center()
        NotificationCenter.default.addObserver(self, selector: #selector(windowClosed), name: NSWindow.willCloseNotification, object: window)
        return window
    }

    @objc private func windowClosed() {
        stop?.set()
        stop = nil
        model.state = nil
    }

    private func startMonitor() {
        let stop = StopFlag()
        self.stop = stop
        let model = model
        let monitor = ControlMonitor(
            socketPath: controlSocketPath(),
            // sleeps in short steps so closing the window ends the thread within a tenth of a second
            wait: { seconds in
                let end = Date().addingTimeInterval(seconds)
                while Date() < end && stop.isSet == false { Thread.sleep(forTimeInterval: 0.1) }
                return stop.isSet == false
            },
            onChange: { state in
                DispatchQueue.main.async { if stop.isSet == false { model.state = state } }
            }
        )
        Thread.detachNewThread { monitor.run() }
    }
}
