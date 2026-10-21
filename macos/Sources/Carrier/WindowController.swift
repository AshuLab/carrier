import AppKit
import Observation
import CarrierCore
import SwiftUI

/// What the window shows: nil until the first answer from Carrier.
@Observable final class PanelModel {
    var state: ConnectionState?
    let shell = WindowShell()
    let epics = EpicStore()
    var groupBy = SidebarStore().groupBy
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

    func open(selecting epic: EpicMenuItem? = nil) {
        let window = window ?? makeWindow()
        self.window = window
        if stop == nil { startMonitor() }
        if let epic { model.shell.selection = .epic(repo: epic.repo, issue: epic.issue) }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() { window?.close() }

    /// For the self-test: whether the window is on screen and whether its monitor runs.
    var status: String { "visible \(window?.isVisible == true), monitor \(stop != nil)" }

    /// For `--smoke-window`: selects the first epic Carrier reports (running, queued, then finished), so its view is on screen.
    func selectFirstEpic() {
        guard case .running(let snapshot)? = model.state else { return }
        let first = snapshot.epics.first.map { ($0.repo, $0.issue) } ?? snapshot.queue.first.map { ($0.repo, $0.issue) }
            ?? snapshot.done.first.map { ($0.repo, $0.issue) }
        if let (repo, issue) = first { model.shell.selection = .epic(repo: repo, issue: issue) }
    }

    /// For `--smoke-window`: what the open window looks like, one line each: the minimum content size, the width of each
    /// column of the split view, the scroll pockets (the system's blur under a bar over a scroll view: the epic's pipeline
    /// makes one in the centre column) and the toolbar's items.
    var structure: String {
        guard let window else { return "no window" }
        var lines = ["min content size: \(Int(window.contentMinSize.width)) x \(Int(window.contentMinSize.height))"]
        func walk(_ view: NSView) {
            if let split = view as? NSSplitView {
                // the sidebar and the detail, then the detail and the inspector: the inspector is a split of its own inside the detail
                for column in split.arrangedSubviews where column.frame.width > 0 {
                    lines.append("column: x \(Int(column.frame.minX.rounded())) width \(Int(column.frame.width.rounded()))")
                }
            }
            if String(describing: type(of: view)) == "NSScrollPocket" {
                let frame = view.convert(view.bounds, to: nil)
                lines.append("scroll pocket: x \(Int(frame.minX.rounded())) width \(Int(frame.width.rounded())) height \(Int(frame.height.rounded()))")
            }
            view.subviews.forEach(walk)
        }
        if let content = window.contentView { walk(content) }
        for item in window.toolbar?.items ?? [] { lines.append("toolbar item: \(item.label.isEmpty ? item.itemIdentifier.rawValue : item.label)") }
        return lines.joined(separator: "\n")
    }

    private func makeWindow() -> NSWindow {
        let host = NSHostingController(rootView: PanelView(model: model))
        // the split view's title and toolbar (the sidebar toggle) go to the window
        host.sceneBridgingOptions = .all
        let window = NSWindow(contentViewController: host)
        window.title = "Carrier"
        // full size content: the sidebar runs up behind the title bar, as Liquid Glass sidebars do
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 1100, height: 700))
        window.center()
        NotificationCenter.default.addObserver(self, selector: #selector(windowClosed), name: NSWindow.willCloseNotification, object: window)
        return window
    }

    @objc private func windowClosed() {
        stop?.set()
        stop = nil
        model.state = nil
        model.shell.reset()
    }

    private func startMonitor() {
        let stop = StopFlag()
        self.stop = stop
        let model = model
        let poller = model.epics.poller!
        let monitor = ControlMonitor(
            socketPath: controlSocketPath(),
            // sleeps in short steps so closing the window ends the thread within a tenth of a second
            wait: { seconds in
                let end = Date().addingTimeInterval(seconds)
                while Date() < end && stop.isSet == false { Thread.sleep(forTimeInterval: 0.1) }
                return stop.isSet == false
            },
            tick: { try poller.poll($0) },
            onChange: { state in
                DispatchQueue.main.async { if stop.isSet == false { model.state = state } }
            }
        )
        Thread.detachNewThread { monitor.run() }
    }
}
