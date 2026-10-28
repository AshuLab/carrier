import AppKit
import Observation
import CarrierCore
import SwiftUI

/// What the window shows: nil until the first answer from Carrier.
@Observable final class PanelModel {
    var state: ConnectionState?
    let shell = WindowShell(open: SidebarStore().open)
    let epics = EpicStore()
    var groupBy = SidebarStore().groupBy
    var sessionSort = SidebarStore().sessionSort
    var collapse = SidebarCollapse()
    /// The chat host's sessions (`ChatSessionsPoller`); the + follows the host (`ChatMonitor`).
    var sessions = Sessions()
}

private extension ShortcutModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var modifiers: ShortcutModifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        self = modifiers
    }
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
final class WindowController: NSObject, NSWindowDelegate {
    static let shared = WindowController()

    /// The smallest the window can be resized to. The hosting controller does not enforce it (see `makeWindow`), the delegate does.
    static let minContent = NSSize(width: 1100, height: 600)

    private let model = PanelModel()
    private var window: NSWindow?
    private var stop: StopFlag?

    /// Adds the "Open window" item at the end of the menu.
    func addMenuItem(to menu: NSMenu) {
        let item = menu.addItem(withTitle: "Open window", action: #selector(openFromMenu), keyEquivalent: "o")
        item.target = self
        showIcon("macwindow", on: item)
    }

    /// Adds the "About Carrier" item: it opens the window if it was closed, then shows the About sheet over it.
    func addAboutItem(to menu: NSMenu) {
        let item = menu.addItem(withTitle: "About Carrier", action: #selector(aboutFromMenu), keyEquivalent: "")
        item.target = self
        showIcon("info.circle", on: item)
    }

    @objc private func openFromMenu() { open() }

    /// For the self-test: Escape on the About sheet, so the next choice of the item starts from no sheet.
    func dismissAbout() { model.shell.aboutInput(.escape) }

    @objc private func aboutFromMenu() {
        open()
        model.shell.showAbout()
    }

    func open(selecting epic: EpicMenuItem? = nil) { open(epic: epic.map { EpicRef(repo: $0.repo, issue: $0.issue) }) }

    func open(epic: EpicRef?) {
        let window = window ?? makeWindow()
        self.window = window
        if stop == nil { startMonitor() }
        if let epic { model.shell.selection = .epic(repo: epic.repo, issue: epic.issue) }
        // regular while the window is open, so the app shows in Cmd+Tab and the Dock; a menu bar app again once it closes
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() { window?.close() }

    /// For the self-test: whether the window is on screen and whether its monitor runs.
    var status: String { "visible \(window?.isVisible == true), monitor \(stop != nil)" }

    /// For the self-test: `status` plus whether the About sheet is shown.
    var aboutStatus: String { "\(status), about sheet \(model.shell.aboutShown ? "shown" : "hidden")" }

    /// For `--smoke-window`: selects the first epic Carrier reports (running, queued, then finished), so its view is on screen.
    func selectFirstEpic() {
        guard case .running(let snapshot)? = model.state else { return }
        let first = snapshot.epics.first.map { ($0.repo, $0.issue) } ?? snapshot.queue.first.map { ($0.repo, $0.issue) }
            ?? snapshot.done.first.map { ($0.repo, $0.issue) }
        if let (repo, issue) = first { model.shell.selection = .epic(repo: repo, issue: issue) }
    }

    /// For `--smoke-window`: selects the first session the chat host lists, so its conversation is on screen.
    func selectFirstSession() {
        if let first = model.sessions.rows.first(where: { $0.archived == false }) { model.shell.selection = .session(id: first.id) }
    }

    /// For `--smoke-window`, after `selectFirstSession`: how the conversation is laid out (read from the constants the view uses) and
    /// what the model makes of the first session's events, which it asks the chat host for as the view does.
    @MainActor func chatStructure() async -> String {
        var lines = ["chat transcript: \(ConversationView.layout)"]
        if case .session(let id) = model.shell.selection {
            let conversation = ConversationModel(host: SocketChatHost(), sessionId: id)
            let start = Date()
            await conversation.poll()
            let took = Int(Date().timeIntervalSince(start) * 1000)
            let groups = conversation.rows.filter { if case .tools = $0 { true } else { false } }.count
            lines.append("chat feed: \(conversation.rows.count) rows (\(groups) of tool calls) from \(conversation.cursor) events in \(took) ms\(conversation.failure.map { ", failed: \($0)" } ?? "")")
        } else {
            lines.append("chat feed: no session to select")
        }
        return lines.joined(separator: "\n")
    }

    /// For `--smoke-window`: what the open window looks like, one line each: the minimum content size, the width of each
    /// column of the split view, the scroll pockets (the system's blur under a bar over a scroll view: the epic's pipeline
    /// makes one in the centre column), the toolbar's items, how the transcript is laid out and the time to merge 5,000 events.
    var structure: String {
        guard let window else { return "no window" }
        var lines = ["min content size: \(Int(Self.minContent.width)) x \(Int(Self.minContent.height))"]
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
        lines.append("sessions +: \(model.sessions.cannotStartReason ?? "enabled")")
        lines.append("sessions: \(model.sessions.rows.count) rows, \(archivedCount(model.sessions.rows)) archived, groups \(sessionGroups(model.sessions.rows).map(\.title))")
        let home = sessionsPage(model.sessions.rows, by: model.sessionSort)
        lines.append("sessions home: \(home.subtitle.isEmpty ? "no count" : home.subtitle), \(home.emptyState?.title ?? "listed")")
        lines.append("transcript: \(SessionSectionsView.layout)")
        let events = longTranscriptEvents(rounds: 556)
        var transcript = Transcript()
        let start = Date()
        transcript.apply(EventsReply(events: events, next: events.count, running: true, structured: true))
        lines.append("transcript merge: \(events.count) events in \(Int(Date().timeIntervalSince(start) * 1000)) ms, \(transcript.work) processed")
        return lines.joined(separator: "\n")
    }

    private func makeWindow() -> NSWindow {
        let host = NSHostingController(rootView: PanelView(model: model))
        // the split view's title and toolbar (the sidebar toggle) go to the window
        host.sceneBridgingOptions = .all
        // the content does not size the window: following its minimum size loops in layout when the inspector comes and goes
        host.sizingOptions = []
        let window = NSWindow(contentViewController: host)
        window.title = "Carrier"
        // full size content: the sidebar runs up behind the title bar, as Liquid Glass sidebars do
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        window.delegate = self
        // the shortcuts belong to the window, not to the menu bar item's menu: only a key pressed while it is the key window counts
        // lives as long as the window, which is kept for the life of the app
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak window] event in
            guard let self, let window, window.isKeyWindow, event.window === window,
                let action = shortcutAction(key: event.charactersIgnoringModifiers ?? "", modifiers: .init(event.modifierFlags))
            else { return event }
            self.model.shell.perform(action)
            return nil
        }
        window.setContentSize(NSSize(width: 1100, height: 700))
        window.center()
        NotificationCenter.default.addObserver(self, selector: #selector(windowClosed), name: NSWindow.willCloseNotification, object: window)
        return window
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let least = sender.frameRect(forContentRect: NSRect(origin: .zero, size: Self.minContent)).size
        return NSSize(width: max(frameSize.width, least.width), height: max(frameSize.height, least.height))
    }

    @objc private func windowClosed() {
        NSApp.setActivationPolicy(.accessory)
        stop?.set()
        stop = nil
        model.state = nil
        model.sessions = Sessions()
        model.shell.reset(open: SidebarStore().open)
    }

    private func startMonitor() {
        let stop = StopFlag()
        self.stop = stop
        let model = model
        let poller = model.epics.poller!
        // sleeps in short steps so closing the window ends the thread within a tenth of a second
        let sleep: (TimeInterval) -> Bool = { seconds in
            let end = Date().addingTimeInterval(seconds)
            while Date() < end && stop.isSet == false { Thread.sleep(forTimeInterval: 0.1) }
            return stop.isSet == false
        }
        let monitor = ControlMonitor(
            socketPath: { controlSocketPath() },
            wait: sleep,
            tick: { try poller.poll($0) },
            onChange: { state in
                DispatchQueue.main.async { if stop.isSet == false { model.state = state } }
            }
        )
        Thread.detachNewThread { monitor.run() }
        let chat = ChatMonitor(wait: sleep) { host in
            DispatchQueue.main.async { if stop.isSet == false { model.sessions.cannotStartReason = cannotStartReason(host: host) } }
        }
        Thread.detachNewThread { chat.run() }
        let sessions = ChatSessionsPoller(host: SocketChatHost()) { rows in
            DispatchQueue.main.async { if stop.isSet == false { model.sessions.rows = rows } }
        }
        Task.detached {
            repeat {
                await sessions.poll()
                try? await Task.sleep(for: .seconds(1))
            } while stop.isSet == false
        }
    }
}
