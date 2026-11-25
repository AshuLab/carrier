import AppKit
import Observation
import CarrierCore
import SwiftUI

/// The window: a plain NSWindow kept for the life of the app, with the SwiftUI panel inside. It has its own monitor of
/// Carrier, started when the window opens and stopped when it closes, so a closed window costs nothing.
final class WindowController: NSObject, NSWindowDelegate {
    static let shared = WindowController()

    /// The smallest the window can be resized to. The hosting controller does not enforce it (see `makeWindow`), the delegate does.
    static let minContent = NSSize(width: 1100, height: 600)

    let model = PanelModel()
    var window: NSWindow?
    private var stop: StopFlag?
    /// The window's list of sessions, followed while the window is open.
    private var sessionsTask: Task<Void, Never>?
    /// The engine's state, followed while the window is open.
    private var stateTask: Task<Void, Never>?

    /// Adds the "Open window" item at the end of the menu.
    func addMenuItem(to menu: NSMenu) {
        let item = menu.addItem(withTitle: "Open window", action: #selector(openFromMenu), keyEquivalent: "o")
        item.target = self
        showIcon("macwindow", on: item)
    }

    /// Adds the "About Carrier" item: it shows the About panel.
    func addAboutItem(to menu: NSMenu) {
        let item = menu.addItem(withTitle: "About Carrier", action: #selector(aboutFromMenu), keyEquivalent: "")
        item.target = self
        showIcon("info.circle", on: item)
    }

    /// Adds the "Settings…" item: it opens Settings in its window.
    func addSettingsItem(to menu: NSMenu) {
        let item = menu.addItem(withTitle: "Settings…", action: #selector(settingsFromMenu), keyEquivalent: ",")
        item.target = self
        showIcon("gearshape", on: item)
    }

    @objc private func openFromMenu() { open() }

    @objc private func settingsFromMenu() { showSettings() }

    /// Opens Settings on a page (the one it was left on when none is asked for). The main window opens too when it was closed: the pages read
    /// what Carrier answers to it (its state, its repos), and Settings is a window of its own over it that does not stop it being used.
    func showSettings(_ page: SettingsPage? = nil, place: SettingsPlace? = nil) {
        open()
        MainActor.assumeIsolated { SettingsWindowController.shared.show(page, place: place, model: model, over: window) }
    }

    /// For the self-test.
    func closeSettings() { MainActor.assumeIsolated { SettingsWindowController.shared.close() } }
    var settingsStatus: String { MainActor.assumeIsolated { "settings window \(SettingsWindowController.shared.isShown ? "shown" : "hidden")" } }

    @objc private func aboutFromMenu() { showAbout() }

    /// The system's About panel: the bundle gives the icon, name, version and copyright; the links go in its credits.
    func showAbout() {
        let centred = NSMutableParagraphStyle()
        centred.alignment = .center
        let credits = NSMutableAttributedString()
        for (index, link) in aboutLinks.enumerated() {
            if index > 0 { credits.append(NSAttributedString(string: "   ")) }
            credits.append(NSAttributedString(string: link.title, attributes: [.link: link.url]))
        }
        credits.addAttributes([.paragraphStyle: centred, .font: NSFont.systemFont(ofSize: 11)], range: NSRange(location: 0, length: credits.length))
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
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

    /// For the Conversation menu: acts only while a conversation is open.
    func conversation(_ action: ConversationAction) { model.shell.perform(.conversation(action)) }

    /// What a session's menu does in the window (`SessionContextMenu`).
    func setUnread(_ id: String, _ unread: Bool) { model.setUnread(id, unread) }
    @MainActor func startNewSession(in base: String, branch: String?) { model.startNewSession(in: base, branch: branch) }
    var viewingSession: String? { if case .session(let id) = model.shell.selection { id } else { nil } }

    /// What is in front, for the global dictation (`dictationFront`): Carrier's main window (or a sheet over it) or its Settings window must be the key window.
    @MainActor
    var dictationFront: DictationFront {
        let key = NSApp.keyWindow
        let shell = model.shell
        let settingsKey = key != nil && key === SettingsWindowController.shared.window
        var hasBox = false
        if case .session(let id) = shell.selection { hasBox = model.sessions.rows.first { $0.id == id }.map { $0.archived == false } ?? false }
        return CarrierCore.dictationFront(
            carrierIsFront: NSApp.isActive && key != nil && (key === window || key?.sheetParent === window || settingsKey),
            settingsShown: settingsKey, selection: shell.selection, sessionHasBox: hasBox)
    }

    /// The global shortcut in a session: the open conversation focuses its message box and starts its dictation, or stops it.
    func dictateInMessageBox() { model.shell.perform(.conversation(.dictate)) }

    /// Main application window when open.
    var mainWindow: NSWindow? { window }

    /// Opens the main window and creates a new standalone terminal rooted at the user's home folder.
    @MainActor
    func openNewTerminal() {
        open(epic: nil)
        let id = CarrierTerminalStore.shared.createStandaloneTerminal(workingDirectory: NSHomeDirectory())
        model.shell.selection = .terminal(id: id)
    }

    /// Returns drawer toggle state for the currently visible session or epic, without initializing the terminal store lazily.
    @MainActor
    func terminalDrawerToggleState() -> (isOpen: Bool, toggle: @MainActor () -> Void)? {
        guard window?.isVisible == true else { return nil }
        switch model.shell.selection {
        case .session(let id):
            guard let session = model.sessions.rows.first(where: { $0.id == id }) else { return nil }
            let owner = TerminalOwner.session(session.id)
            return (
                isOpen: model.shell.isTerminalDrawerOpen(for: owner),
                toggle: { [weak self] in
                    guard let self else { return }
                    if model.shell.isTerminalDrawerOpen(for: owner) {
                        model.shell.setTerminalDrawerOpen(false, for: owner)
                    } else {
                        if CarrierTerminalStore.shared.tabs(for: owner).isEmpty {
                            _ = CarrierTerminalStore.shared.openTab(for: owner, workingDirectory: session.folder)
                        }
                        model.shell.setTerminalDrawerOpen(true, for: owner)
                    }
                }
            )
        case .epic(let repo, let issue):
            let owner = TerminalOwner.epic(repo: repo, issue: issue)
            guard CarrierTerminalStore.sharedIfInitialized?.tabs(for: owner).isEmpty == false else { return nil }
            return (
                isOpen: model.shell.isTerminalDrawerOpen(for: owner),
                toggle: { [weak self] in
                    self?.model.shell.toggleTerminalDrawer(for: owner)
                }
            )
        default:
            return nil
        }
    }

    /// Active standalone or drawer terminal owner visible in the main window, if any.
    var preferredTerminalOwner: TerminalOwner? {
        guard window?.isVisible == true else { return nil }
        switch model.shell.selection {
        case .terminal(let id):
            return .terminal(id)
        case .session(let id):
            let owner = TerminalOwner.session(id)
            return model.shell.isTerminalDrawerOpen(for: owner) ? owner : nil
        case .epic(let repo, let issue):
            let owner = TerminalOwner.epic(repo: repo, issue: issue)
            return model.shell.isTerminalDrawerOpen(for: owner) ? owner : nil
        default:
            return nil
        }
    }

    /// A shortcut that reads the sessions, from the main menu.
    func perform(_ action: ShortcutAction) {
        open()
        run(action)
    }

    private func run(_ action: ShortcutAction) {
        model.shell.perform(action, sessions: model.sessions.rows, sort: SidebarStore().sessionSort, pinned: SidebarStore().pinned)
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
        MainActor.assumeIsolated { LaunchPhases.shared.windowOrdered() }
        refreshPace()
    }

    func open(session id: String) {
        open(epic: nil)
        model.shell.selection = .session(id: id)
    }

    /// Opens the Usage page of the main window (the history of tokens and cost, which Settings only points to).
    func showUsage() {
        open()
        model.shell.selection = .usage
    }

    func close() { window?.close() }

    /// For the self-test: whether the window is on screen and whether its monitor runs.
    var status: String { "visible \(window?.isVisible == true), monitor \(stop != nil)" }

    private func makeWindow() -> NSWindow {
        let signpost = Signposts.launch.beginInterval("make window")
        defer { Signposts.launch.endInterval("make window", signpost) }
        let host = NSHostingController(rootView: PanelView(model: model).environment(MainActor.assumeIsolated { Viewing.shared }))
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
                (window.firstResponder as? PillTextView)?.takesCommandDown(event) != true,
                let action = shortcutAction(key: event.charactersIgnoringModifiers ?? "", modifiers: .init(event.modifierFlags))
            else { return event }
            self.run(action)
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
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(windowShownOrHidden), name: name, object: window)
        }
        return window
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let least = sender.frameRect(forContentRect: NSRect(origin: .zero, size: Self.minContent)).size
        return NSSize(width: max(frameSize.width, least.width), height: max(frameSize.height, least.height))
    }

    @MainActor func followProjects() { model.followProjects() }

    /// Tells `Viewing` whether anyone is looking: the app is active and the window is on screen, or one of them, or the Mac sleeps. Then the host and
    /// the engine are asked often or not, and the Usage page's minute timer runs (it pauses while nobody looks and asks again when someone does).
    /// A window that is closing is still visible when it says so: the caller says it is not shown.
    func refreshPace(windowShown shown: Bool? = nil) {
        let wasLooking = PollPace.shared.looking
        defer {
            // the window's list is read at once when it comes back in sight, not at the end of the pause
            if wasLooking == false, PollPace.shared.looking { SocketChatHost().refreshSessions(archived: false) }
        }
        MainActor.assumeIsolated {
            Viewing.shared.update(
                appActive: NSApp.isActive, windowShown: shown ?? windowIsShown, asleep: sleepReasons.isEmpty == false,
                lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled
            )
            _ = AppUsage.refresher.setAttentive(Viewing.shared.state == .focused)
            IconController.shared?.reloadSettings()
        }
    }

    /// What the Mac is asleep for, by name: the screens, the system, or the user's session switched away. Any one is enough for nobody to look.
    private var sleepReasons: Set<String> = []

    func sleeping(_ reason: String, _ asleep: Bool) {
        if asleep { sleepReasons.insert(reason) } else { sleepReasons.remove(reason) }
        refreshPace()
    }

    private var windowIsShown: Bool {
        window.map { $0.isVisible && $0.isMiniaturized == false && $0.occlusionState.contains(.visible) } ?? false
    }

    @objc private func windowShownOrHidden() {
        refreshPace()
        // hiding the window (minimized, or no pixel of it on screen: another Space, a full-screen app over it) ends a message box's dictation as
        // closing it and leaving the app do: nothing listens and writes unseen. The widget's goes on: it is on screen over the other app.
        // A window that other windows only partly cover is still `.visible`, so it keeps listening.
        if windowIsShown == false { MainActor.assumeIsolated { DictationController.shared.stopBoxDictation() } }
    }

    @objc private func windowClosed() {
        // `willClose` comes while the window is still on screen
        refreshPace(windowShown: false)
        MainActor.assumeIsolated { DictationController.shared.stopBoxDictation() }
        // the app stays in the Dock and the menu bar: a closed window is a closed window, and the Dock icon opens it again
        stop?.set()
        stop = nil
        sessionsTask?.cancel()
        sessionsTask = nil
        stateTask?.cancel()
        stateTask = nil
        EngineLink.shared.setTick(nil)
        model.state = nil
        if case .session(let id) = model.shell.selection { model.leave(id) }
        model.sessions = Sessions()
        model.shell.reset(open: SidebarStore().open)
    }

    /// The check at open answered, so a host that was starting is up: the window's session list is read now and not at the next tick.
    func chatHostChecked() { SocketChatHost().refreshSessions(archived: false) }

    private func startMonitor() {
        let stop = StopFlag()
        self.stop = stop
        let model = model
        let poller = model.epics.poller!
        // the engine's state is the menu's too: one read for both. The epic on screen is read while someone can see the window, or when it was just
        // asked for (a window that is opening is not on screen yet at its first tick): a hidden one is read again at the next tick after it shows
        let link = EngineLink.shared
        link.setTick { client in if PollPace.shared.looking || poller.hasPendingFocus { try poller.poll(client) } }
        let states = link.states()
        // a window that opens shows the state of the moment, not the last one the menu read
        link.refresh()
        stateTask = Task { @MainActor in
            for await state in states {
                // an equal state is not assigned: the observer ignores it anyway, and the "panel state" signpost counts only what differs
                if stop.isSet == false, publishes(state, over: model.state) { model.state = state }
            }
        }
        let sessions = ChatSessionsPoller(
            host: SocketChatHost(),
            onAuthoritativeSessionIds: { knownIds in
                DispatchQueue.main.async {
                    if stop.isSet == false { model.reconcileKnownSessions(knownIds) }
                }
            },
            onChange: { rows in
                // only a change is published: an equal list at every poll would rebuild an open context menu under the pointer
                DispatchQueue.main.async { if stop.isSet == false { model.adopt(rows) } }
            }
        )
        // what changes the list is read at once: the wait is cut short, and the archived ones are read again
        let host = SocketChatHost()
        DispatchQueue.main.async {
            model.actions.changed = { host.refreshSessions(archived: true) }
            model.actions.archivingChanged = { DispatchQueue.main.async { model.refreshUnread() } }
        }
        sessionsTask = Task.detached { await sessions.run() }
    }
}
