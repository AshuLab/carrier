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
    var archiveSort = SidebarStore().archiveSort
    /// Archive, restore and delete; `startMonitor` makes the lists read again after each.
    let actions = SessionActions(host: SocketChatHost())
    var collapse = SidebarCollapse()
    /// The chat host's sessions (`ChatSessionsPoller`).
    var sessions = Sessions()
    /// The draft of a new session; it starts the chat host when it is not running (#503) before it opens the session.
    // built on the main thread, where the app creates its window
    let newSession = MainActor.assumeIsolated {
        NewSessionModel(host: SocketChatHost(), health: AppHealth.store) {
            await withCheckedContinuation { continuation in ChatHostStarter.shared.ensureRunning { continuation.resume(returning: $0) } }
        }
    }
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

    @objc private func aboutFromMenu() { showAbout() }

    func showAbout() {
        open()
        model.shell.showAbout()
    }

    // For the main menu: each opens the window (or brings it forward) first.

    func show(_ selection: Selection) {
        open()
        model.shell.selection = selection
    }

    func search() {
        open()
        model.shell.perform(.search)
    }

    func toggleSidebar() { model.shell.toggleSidebar() }

    func toggleInspector() { model.shell.toggleInspector() }

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

    /// For `--smoke-window`: selects the Archive page.
    func selectArchive() { model.shell.selection = .archive }

    /// For `--smoke-window`, with the Archive selected: what the page lists and says, then the window's layout as it is with it on screen.
    var archiveStructure: String {
        let page = archivePage(model.sessions.rows, by: model.archiveSort)
        let line = "archive: \(page.subtitle.isEmpty ? "no count" : page.subtitle), groups \(page.groups.map(\.title)), \(page.emptyState?.title ?? "listed"), clear \(page.canClear ? "enabled" : "disabled")"
        return line + "\n" + structure
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
            lines.append("chat feed: \(conversation.rows.count) rows (\(groups) of tool calls) from \(conversation.cursor) events in \(took) ms, options: \(optionsPill(conversation.options) ?? "none")\(conversation.failure.map { ", failed: \($0)" } ?? "")")
        } else {
            lines.append("chat feed: no session to select")
        }
        return lines.joined(separator: "\n")
    }

    /// For `--smoke-window`: shows the draft of a new session and says what it offers, as the view reads it from the chat host.
    @MainActor func newSessionStructure() async -> String {
        model.shell.selection = .newSession
        await model.newSession.load()
        let draft = model.newSession
        var lines = ["new session: \"\(draft.sentence)\", agents \(draft.agents.map { choice in choice.note.map { "\(choice.name) (\($0))" } ?? choice.name }), agent \(draft.agent ?? "none"), recent \(draft.recent.map(\.name))"]
        // the worktree half, for the first recent folder: what the host says it is, then the sentence in a new worktree
        if let folder = draft.recent.first?.path {
            await draft.choose(folder: folder)
            lines.append("new session folder: \"\(draft.sentence)\", warning \(draft.warning ?? "none"), worktree \(draft.offersWorktree ? "offered" : "not offered")")
            await draft.useWorktree(true)
            if draft.worktree {
                let picker = draft.picker(query: "")
                lines.append("new session worktree: \"\(draft.sentence)\", name \(draft.nameState), branches \(picker?.local.count ?? 0) local and \(picker?.remote.count ?? 0) remote, \(picker?.fetched ?? "no picker")")
                await draft.useWorktree(false)
            }
        }
        // the workspace popover: what it lists, and the GitHub URL step against the host (a repository it lists, then one it does not)
        draft.openPicker()
        lines.append("new session picker: recent \(draft.recent.map(\.name)), projects \(draft.projects.map(\.name)), sources \(draft.sources.map(\.rawValue)), footer \(draft.projectsPath)")
        draft.show(.url)
        for text in ["https://github.com/AshuLab/web", "AshuLab/nope"] {
            draft.urlText = text
            let worked = await draft.cloneAndUse()
            lines.append("new session clone \(text): \(draft.cloneButton), \(worked ? "used" : "refused: \(draft.cloneProblem ?? "no reason")"), \"\(draft.sentence)\"")
        }
        // My GitHub repositories against the host: page 1 with the login, Load more, and a repository chosen from the list
        await draft.showRepos()
        lines.append("new session repos: login \(draft.login ?? "none"), \(draft.repoRows().count) loaded, more \(draft.repoList.hasMore), watched \(draft.repoRows().filter(\.watched).map(\.name))")
        await draft.loadRepos()
        lines.append("new session repos page 2: \(draft.repoRows().count) loaded, more \(draft.repoList.hasMore), reason \(draft.reposReason ?? "none")")
        draft.watch = false  // a smoke pass never writes the config
        if let first = draft.repoRows().first {
            let worked = await draft.cloneAndUse(repo: first.name)
            lines.append("new session repo \(first.name): \(worked ? "used" : "refused: \(draft.cloneProblem ?? "no reason")"), \"\(draft.sentence)\"")
        }
        // New project against the host: a name it makes (and the draft then offers no worktree), then one it refuses as taken
        draft.show(.project)
        for name in ["my-idea", "web"] {
            draft.projectName = name
            let worked = await draft.createAndUse()
            lines.append("new session project \(name): \(worked ? "used" : "refused: \(draft.createProblem ?? draft.projectNameWarning ?? "no reason")"), \"\(draft.sentence)\", worktree \(draft.offersWorktree ? "offered" : "not offered")")
        }
        return lines.joined(separator: "\n")
    }

    /// For `--smoke-window`: what the open window looks like, one line each: the minimum content size, the width of each
    /// column of the split view, the scroll pockets (the system's blur under a bar over a scroll view: the epic's pipeline
    /// makes one in the centre column), the toolbar's items, how the transcript is laid out and the time to merge 5,000 events.
    var structure: String {
        guard let window else { return "no window" }
        var lines = ["min content size: \(Int(Self.minContent.width)) x \(Int(Self.minContent.height))"]
        lines.append("app: \(NSApp.activationPolicy() == .regular ? "in the Dock" : "no Dock icon"), menus \(NSApp.mainMenu?.items.map(\.title) ?? [])")
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
        for item in window.toolbar?.items ?? [] {
            // where each one sits in the window, left edge and width: an item that is not where it belongs shows here
            let frame = item.view.map { $0.convert($0.bounds, to: nil) }
            lines.append("toolbar item: \(item.label.isEmpty ? item.itemIdentifier.rawValue : item.label)\(frame.map { " at x \(Int($0.minX)) width \(Int($0.width))" } ?? "")")
        }
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

    /// For `--smoke-window`: the window at its smallest, one line per page with how tall the split view lays out. A page that asks for
    /// more than the window has (its title bar's 26 points apart) shows the sidebar and the bottom of the page pushed out of the window.
    @MainActor func minimumSizeReport() async -> String {
        guard let window else { return "no window" }
        window.setContentSize(Self.minContent)
        var lines = ["at the smallest size (\(Int(Self.minContent.width)) x \(Int(Self.minContent.height))), split view height per page:"]
        func splitHeight() -> Int {
            var found = 0
            func walk(_ view: NSView) {
                if found == 0, let split = view as? NSSplitView, let first = split.arrangedSubviews.first { found = Int(first.frame.height) }
                view.subviews.forEach(walk)
            }
            if let content = window.contentView { walk(content) }
            return found
        }
        let pages: [(String, () -> Void)] = [
            ("home", { self.model.shell.selection = .home }), ("sessions", { self.model.shell.selection = .sessions }),
            ("new session", { self.model.shell.selection = .newSession }), ("archive", { self.model.shell.selection = .archive }),
            ("settings", { self.model.shell.selection = .settings }), ("carrier", { self.model.shell.selection = .carrier }),
            ("first session", { self.selectFirstSession() }),
        ]
        for (name, select) in pages {
            select()
            try? await Task.sleep(for: .milliseconds(700))
            let height = splitHeight()
            lines.append("  \(name): \(height)\(height > Int(Self.minContent.height) + 40 ? "  <- taller than the window" : "")")
        }
        // the last page is a session: where its toolbar's items sit, left edge and width (the header on the left, the Open menu on the right)
        let items = (window.toolbar?.items ?? []).compactMap { item in
            item.view.map { "\(item.label.isEmpty ? String(item.itemIdentifier.rawValue.prefix(8)) : item.label) x \(Int($0.convert($0.bounds, to: nil).minX)) w \(Int($0.bounds.width))" }
        }
        lines.append("  toolbar with a session open: \(items.joined(separator: ", "))")
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
        // where it was and how big, as a Mac app keeps its window; the smoke check starts from the default so it measures the same every time
        let restored = CommandLine.arguments.contains("--smoke-window") == false && window.setFrameAutosaveName("CarrierMainWindow")
        // a kept frame that is smaller than the window may be, or on no screen any more (a display that went away), is not used: the window
        // would be there and nobody could see it
        let kept = window.contentRect(forFrameRect: window.frame).size
        let usable = kept.width >= Self.minContent.width && kept.height >= Self.minContent.height
            && NSScreen.screens.contains { $0.visibleFrame.intersects(window.frame) }
        if restored == false || usable == false {
            window.setContentSize(NSSize(width: 1100, height: 700))
            window.center()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(windowClosed), name: NSWindow.willCloseNotification, object: window)
        return window
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let least = sender.frameRect(forContentRect: NSRect(origin: .zero, size: Self.minContent)).size
        return NSSize(width: max(frameSize.width, least.width), height: max(frameSize.height, least.height))
    }

    @objc private func windowClosed() {
        // the app stays in the Dock and the menu bar: a closed window is a closed window, and the Dock icon opens it again
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
        let sessions = ChatSessionsPoller(host: SocketChatHost()) { rows in
            DispatchQueue.main.async { if stop.isSet == false { model.sessions.rows = rows } }
        }
        DispatchQueue.main.async { model.actions.changed = { sessions.invalidateArchived() } }
        Task.detached {
            repeat {
                await sessions.poll()
                try? await Task.sleep(for: .seconds(1))
            } while stop.isSet == false
        }
    }
}
