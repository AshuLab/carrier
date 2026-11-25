import AppKit
import CarrierCore

// The menu bar of the app: what a Mac app has (its own menu, File, Edit, View, Window, Help), so the keys every text field expects work
// (the Edit menu is what makes ⌘C and ⌘V reach a field) and the window is driven from the top of the screen as well as from its sidebar.
// The menu bar item at the right of the screen (the status item) is another thing and stays as it was.
extension AppDelegate {
    /// Puts the main menu in place, built from the shortcut table; it is built again when a combination changes.
    func installMainMenu() {
        let table = ShortcutTable()
        shortcutsInMenu = table.combos
        let main = makeMainMenu(shortcuts: table)
        NSApp.mainMenu = main
        setSystemMenus(of: main)
    }

    /// Hands macOS the three menus it asks the app for by role (the Services, Window and Help menus): each is found by its identifier, so a
    /// title that is changed or translated does not lose it.
    func setSystemMenus(of main: NSMenu) {
        func menu(_ role: NSUserInterfaceItemIdentifier) -> NSMenu? {
            (main.items + (main.items.first?.submenu?.items ?? [])).first { $0.identifier == role }?.submenu
        }
        NSApp.servicesMenu = menu(.servicesMenu)
        NSApp.windowsMenu = menu(.windowMenu)
        NSApp.helpMenu = menu(.helpMenu)
    }

    /// Builds it again when a combination of the table is not the one the menu carries.
    func rebuildMainMenuIfShortcutsChanged() {
        if ShortcutTable().combos != shortcutsInMenu { installMainMenu() }
    }

    func makeMainMenu(
        shortcuts: ShortcutTable,
        controls: MenuControls = .shared,
        terminalControls: TerminalMenuControls = .shared
    ) -> NSMenu {
        let main = NSMenu()

        // Carrier
        let app = submenu(of: main, title: "Carrier")
        item(app, "About Carrier", #selector(showAbout), target: self)
        // the update driver validates the item itself; with no updater (a fixture, `swift run`) nothing answers it and it stays dimmed
        item(app, "Check for Updates…", #selector(UpdateDriver.checkForUpdates(_:)), target: MainActor.assumeIsolated { AppUpdater.menuTarget })
        app.addItem(.separator())
        item(app, "Settings…", #selector(openSettings), key: ",", target: self)
        app.addItem(.separator())
        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        services.identifier = .servicesMenu
        services.submenu = NSMenu(title: "Services")
        app.addItem(services)
        app.addItem(.separator())
        item(app, "Hide Carrier", #selector(NSApplication.hide(_:)), key: "h")
        item(app, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), key: "h", modifiers: [.command, .option])
        item(app, "Show All", #selector(NSApplication.unhideAllApplications(_:)))
        app.addItem(.separator())
        item(app, "Quit Carrier", #selector(NSApplication.terminate(_:)), key: "q")

        // File
        let file = submenu(of: main, title: "File")
        item(file, "New Session", #selector(newSession), shortcut: .newSession, in: shortcuts, target: self)
        item(file, "Next Session", #selector(nextSession), shortcut: .nextSession, in: shortcuts, target: self)
        item(file, "Previous Session", #selector(previousSession), shortcut: .previousSession, in: shortcuts, target: self)
        item(file, "Archive Session", #selector(archiveSession), shortcut: .archiveSession, in: shortcuts, target: self)
        file.addItem(.separator())
        item(file, "Close Window", #selector(NSWindow.performClose(_:)), key: "w")

        // Edit: the responder chain does the work; without these a text field has no ⌘C, ⌘V, ⌘Z
        let edit = submenu(of: main, title: "Edit")
        item(edit, "Undo", Selector(("undo:")), key: "z")
        item(edit, "Redo", Selector(("redo:")), key: "z", modifiers: [.command, .shift])
        edit.addItem(.separator())
        item(edit, "Cut", #selector(NSText.cut(_:)), key: "x")
        item(edit, "Copy", #selector(NSText.copy(_:)), key: "c")
        item(edit, "Paste", #selector(NSText.paste(_:)), key: "v")
        item(edit, "Select All", #selector(NSText.selectAll(_:)), key: "a")
        edit.addItem(.separator())
        item(edit, "Find…", #selector(findInSection), shortcut: .search, in: shortcuts, target: self)

        // View
        let view = submenu(of: main, title: "View")
        item(view, "Home", #selector(showHome), shortcut: .home, in: shortcuts, target: self)
        item(view, "Sessions", #selector(showSessions), shortcut: .sessions, in: shortcuts, target: self)
        item(view, "Carrier", #selector(showCarrier), shortcut: .carrier, in: shortcuts, target: self)
        item(view, "Archive", #selector(showArchive), shortcut: .archive, in: shortcuts, target: self)
        view.addItem(.separator())
        item(view, "Back", #selector(goBack), shortcut: .back, in: shortcuts, target: self)
        item(view, "Forward", #selector(goForward), shortcut: .forward, in: shortcuts, target: self)
        view.addItem(.separator())
        item(view, "Show or Hide Sidebar", #selector(toggleSidebar), key: "s", modifiers: [.command, .control], target: self)
        item(view, "Show or Hide Inspector", #selector(toggleInspector), key: "i", modifiers: [.command, .option], target: self)
        view.addItem(.separator())
        item(view, "Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), key: "f", modifiers: [.command, .control])

        // Conversation
        let conversation = submenu(of: main, title: "Conversation")
        item(conversation, "Focus the Message Box", #selector(focusMessageBox), shortcut: .focusBox, in: shortcuts, target: self)
        item(conversation, "Stop the Agent", #selector(stopAgent), shortcut: .stopAgent, in: shortcuts, target: self)
        item(conversation, "Jump to the Latest Message", #selector(jumpToLatestMessage), shortcut: .latestMessage, in: shortcuts, target: self)
        item(conversation, "Fold or Unfold the Tool Calls", #selector(toggleToolFolds), shortcut: .foldTools, in: shortcuts, target: self)
        item(conversation, "Copy the Last Answer", #selector(copyLastAnswer), shortcut: .copyAnswer, in: shortcuts, target: self)

        // Engine: the controls of the menu bar item, with a shortcut when the person gives one
        let engine = submenu(of: main, title: "Engine")
        item(engine, ShortcutCommand.startOrStop.title, #selector(MenuControls.startOrStop), shortcut: .startOrStop, in: shortcuts, target: controls)
        item(engine, ShortcutCommand.pauseOrResume.title, #selector(MenuControls.pauseOrResume), shortcut: .pauseOrResume, in: shortcuts, target: controls)
        item(engine, ShortcutCommand.checkNow.title, #selector(MenuControls.checkNow), shortcut: .checkNow, in: shortcuts, target: controls)

        // Terminal: global creation, drawer toggle, tab, split, focus, zoom, equalize, detach and close controls for keyboard-only and VoiceOver access
        let terminal = submenu(of: main, title: "Terminal")
        item(terminal, "New Terminal", #selector(TerminalMenuControls.newTerminal), key: "t", modifiers: [.command, .option], target: terminalControls)
        item(terminal, "New Tab", #selector(TerminalMenuControls.newTab), key: "t", target: terminalControls)
        item(terminal, "Show or Hide Terminal", #selector(TerminalMenuControls.toggleTerminalDrawer), key: "t", modifiers: [.command, .control], target: terminalControls)
        terminal.addItem(.separator())
        item(terminal, "Split Right", #selector(TerminalMenuControls.splitRight), key: "d", target: terminalControls)
        item(terminal, "Split Down", #selector(TerminalMenuControls.splitDown), key: "d", modifiers: [.command, .shift], target: terminalControls)
        item(terminal, "Zoom Pane", #selector(TerminalMenuControls.toggleZoomPane), key: "\r", modifiers: [.command, .shift], target: terminalControls)
        item(terminal, "Equalize Splits", #selector(TerminalMenuControls.equalizeSplits), target: terminalControls)
        item(terminal, "Move Pane to New Tab", #selector(TerminalMenuControls.movePaneToNewTab), target: terminalControls)
        item(terminal, "Focus Previous Pane", #selector(TerminalMenuControls.focusPreviousPane), key: "[", modifiers: [.command, .option], target: terminalControls)
        item(terminal, "Focus Next Pane", #selector(TerminalMenuControls.focusNextPane), key: "]", modifiers: [.command, .option], target: terminalControls)
        terminal.addItem(.separator())
        item(terminal, "Select Previous Tab", #selector(TerminalMenuControls.selectPreviousTab), key: "[", modifiers: [.command, .shift], target: terminalControls)
        item(terminal, "Select Next Tab", #selector(TerminalMenuControls.selectNextTab), key: "]", modifiers: [.command, .shift], target: terminalControls)
        item(terminal, "Move Tab Left", #selector(TerminalMenuControls.moveTabLeft), target: terminalControls)
        item(terminal, "Move Tab Right", #selector(TerminalMenuControls.moveTabRight), target: terminalControls)
        terminal.addItem(.separator())
        item(terminal, "Close Pane", #selector(TerminalMenuControls.closePane), key: "w", modifiers: [.command, .shift], target: terminalControls)

        // Window
        let window = submenu(of: main, title: "Window", role: .windowMenu)
        item(window, "Minimize", #selector(NSWindow.performMiniaturize(_:)), key: "m")
        item(window, "Zoom", #selector(NSWindow.performZoom(_:)))
        window.addItem(.separator())
        item(window, "Bring All to Front", #selector(NSApplication.arrangeInFront(_:)))

        // Help
        let help = submenu(of: main, title: "Help", role: .helpMenu)
        item(help, "Carrier on GitHub", #selector(openHelp), target: self)
        return main
    }

    /// The menu of the Dock icon, over the system's own items.
    func dockMenu() -> NSMenu {
        let menu = NSMenu()
        item(menu, "New Session", #selector(newSession), target: self)
        item(menu, "Open Window", #selector(openWindow), target: self)
        return menu
    }

    private func submenu(of main: NSMenu, title: String, role: NSUserInterfaceItemIdentifier? = nil) -> NSMenu {
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        holder.identifier = role
        let menu = NSMenu(title: title)
        holder.submenu = menu
        main.addItem(holder)
        return menu
    }

    @discardableResult
    private func item(
        _ menu: NSMenu, _ title: String, _ action: Selector, key: String = "", modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil
    ) -> NSMenuItem {
        let made = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        if key.isEmpty == false { made.keyEquivalentModifierMask = modifiers }
        made.target = target
        return made
    }

    /// An item that carries the table's combination for its action, none when the table has none.
    @discardableResult
    private func item(_ menu: NSMenu, _ title: String, _ action: Selector, shortcut: ShortcutCommand, in table: ShortcutTable, target: AnyObject?) -> NSMenuItem {
        let combo = table.combo(for: shortcut)
        return item(menu, title, action, key: combo?.key ?? "", modifiers: combo?.modifiers.flags ?? .command, target: target)
    }

    @objc func showAbout() { WindowController.shared.showAbout() }
    @objc func openSettings() { WindowController.shared.showSettings() }
    @objc func openWindow() { WindowController.shared.open() }
    @objc func newSession() { WindowController.shared.show(.newSession) }
    @objc func showHome() { WindowController.shared.show(.home) }
    @objc func showSessions() { WindowController.shared.show(.sessions) }
    @objc func showCarrier() { WindowController.shared.show(.carrier) }
    @objc func showArchive() { WindowController.shared.show(.archive) }
    @objc func goBack() { WindowController.shared.perform(.back) }
    @objc func goForward() { WindowController.shared.perform(.forward) }
    @objc func nextSession() { WindowController.shared.perform(.nextSession) }
    @objc func previousSession() { WindowController.shared.perform(.previousSession) }
    @objc func archiveSession() { WindowController.shared.perform(.archiveSession) }
    @objc func findInSection() { WindowController.shared.search() }
    @objc func focusMessageBox() { WindowController.shared.conversation(.focusBox) }
    @objc func stopAgent() { WindowController.shared.conversation(.stopAgent) }
    @objc func jumpToLatestMessage() { WindowController.shared.conversation(.jumpToLatest) }
    @objc func toggleToolFolds() { WindowController.shared.conversation(.toggleToolFolds) }
    @objc func copyLastAnswer() { WindowController.shared.conversation(.copyLastAnswer) }
    @objc func toggleSidebar() { WindowController.shared.toggleSidebar() }
    @objc func toggleInspector() { WindowController.shared.toggleInspector() }
    @objc func openHelp() { NSWorkspace.shared.open(URL(string: "https://github.com/AshuLab/carrier")!) }
}

/// Validates and dispatches Terminal menu pane commands to the focused terminal pane or active owner tab.
final class TerminalMenuControls: NSObject, NSMenuItemValidation {
    static let shared = TerminalMenuControls()

    private let storeProvider: @MainActor () -> CarrierTerminalStore?
    private let preferredOwnerProvider: @MainActor () -> TerminalOwner?
    private let allowsPreferredFallback: @MainActor () -> Bool
    private let newTerminalAction: @MainActor () -> Void
    private let drawerStateProvider: @MainActor () -> (isOpen: Bool, toggle: @MainActor () -> Void)?

    init(
        storeProvider: @escaping @MainActor () -> CarrierTerminalStore? = { CarrierTerminalStore.sharedIfInitialized },
        preferredOwnerProvider: @escaping @MainActor () -> TerminalOwner? = { WindowController.shared.preferredTerminalOwner },
        allowsPreferredFallback: @escaping @MainActor () -> Bool = { TerminalMenuControls.allowsPreferredFallback() },
        newTerminalAction: @escaping @MainActor () -> Void = { WindowController.shared.openNewTerminal() },
        drawerStateProvider: @escaping @MainActor () -> (isOpen: Bool, toggle: @MainActor () -> Void)? = { WindowController.shared.terminalDrawerToggleState() }
    ) {
        self.storeProvider = storeProvider
        self.preferredOwnerProvider = preferredOwnerProvider
        self.allowsPreferredFallback = allowsPreferredFallback
        self.newTerminalAction = newTerminalAction
        self.drawerStateProvider = drawerStateProvider
    }

    @MainActor
    static func allowsPreferredFallback() -> Bool {
        allowsPreferredFallback(keyWindow: NSApp?.keyWindow, mainWindow: WindowController.shared.mainWindow)
    }

    @MainActor
    static func allowsPreferredFallback(
        keyWindow: NSWindow?,
        mainWindow: NSWindow?
    ) -> Bool {
        guard let keyWindow, let mainWindow else { return false }
        return keyWindow === mainWindow
            && keyWindow.attachedSheet == nil
            && (keyWindow.firstResponder is NSText) == false
    }

    @MainActor
    private func resolveTarget() -> (store: CarrierTerminalStore, tab: TerminalTab, paneId: UUID)? {
        guard NSApp?.keyWindow?.attachedSheet == nil,
              let store = storeProvider()
        else { return nil }
        if let focused = store.focusedPaneTarget() {
            return (store, focused.tab, focused.paneId)
        }
        if allowsPreferredFallback(),
           let target = store.activePaneTarget(preferredOwner: preferredOwnerProvider()) {
            return (store, target.tab, target.paneId)
        }
        return nil
    }

    @MainActor @objc func newTerminal() {
        newTerminalAction()
    }

    @MainActor @objc func toggleTerminalDrawer() {
        drawerStateProvider()?.toggle()
    }

    @MainActor @objc func newTab() {
        guard let target = resolveTarget() else { return }
        _ = target.store.openTab(for: target.tab.owner, workingDirectory: target.tab.workingDirectory)
    }

    @MainActor @objc func splitRight() {
        guard let target = resolveTarget() else { return }
        _ = target.store.splitPane(target.paneId, edge: .trailing)
    }

    @MainActor @objc func splitDown() {
        guard let target = resolveTarget() else { return }
        _ = target.store.splitPane(target.paneId, edge: .bottom)
    }

    @MainActor @objc func toggleZoomPane() {
        guard let target = resolveTarget(), target.tab.panes.count > 1 else { return }
        target.store.toggleZoom(paneId: target.paneId)
    }

    @MainActor @objc func equalizeSplits() {
        guard let target = resolveTarget(), target.tab.panes.count > 1 else { return }
        target.store.equalizeSplits(inTab: target.tab.id)
    }

    @MainActor @objc func movePaneToNewTab() {
        guard let target = resolveTarget(), target.tab.panes.count > 1 else { return }
        _ = target.store.detachPaneToNewTab(target.paneId)
    }

    @MainActor @objc func focusPreviousPane() {
        guard let target = resolveTarget(), target.tab.panes.count > 1 else { return }
        _ = target.store.focusAdjacentPane(offset: -1, inTab: target.tab.id)
    }

    @MainActor @objc func focusNextPane() {
        guard let target = resolveTarget(), target.tab.panes.count > 1 else { return }
        _ = target.store.focusAdjacentPane(offset: 1, inTab: target.tab.id)
    }

    @MainActor @objc func selectPreviousTab() {
        guard let target = resolveTarget() else { return }
        _ = target.store.selectAdjacentTab(offset: -1, for: target.tab.owner)
    }

    @MainActor @objc func selectNextTab() {
        guard let target = resolveTarget() else { return }
        _ = target.store.selectAdjacentTab(offset: 1, for: target.tab.owner)
    }

    @MainActor @objc func moveTabLeft() {
        guard let target = resolveTarget() else { return }
        _ = target.store.moveTabRelative(target.tab.id, offset: -1)
    }

    @MainActor @objc func moveTabRight() {
        guard let target = resolveTarget() else { return }
        _ = target.store.moveTabRelative(target.tab.id, offset: 1)
    }

    @MainActor @objc func closePane() {
        guard let target = resolveTarget() else { return }
        let isSplit = target.tab.panes.count > 1
        Task { @MainActor in
            if isSplit {
                _ = await target.store.closePane(id: target.paneId)
            } else {
                _ = await target.store.closeTab(id: target.tab.id)
            }
        }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        MainActor.assumeIsolated {
            switch item.action {
            case #selector(newTerminal):
                return true
            case #selector(toggleTerminalDrawer):
                guard let drawer = drawerStateProvider() else {
                    item.title = "Show or Hide Terminal"
                    return false
                }
                item.title = drawer.isOpen ? "Hide Terminal" : "Show Terminal"
                return true
            default:
                break
            }
            guard let target = resolveTarget() else { return false }
            let isSplit = target.tab.panes.count > 1
            let tabCount = target.store.tabs(for: target.tab.owner).count
            switch item.action {
            case #selector(toggleZoomPane):
                item.title = target.tab.zoomedPaneId == target.paneId ? "Restore Split View" : "Zoom Pane"
                return isSplit
            case #selector(equalizeSplits), #selector(movePaneToNewTab), #selector(focusPreviousPane), #selector(focusNextPane):
                return isSplit
            case #selector(selectPreviousTab), #selector(selectNextTab):
                return tabCount > 1
            case #selector(moveTabLeft):
                return target.store.registry.canMoveTab(id: target.tab.id, offset: -1)
            case #selector(moveTabRight):
                return target.store.registry.canMoveTab(id: target.tab.id, offset: 1)
            case #selector(newTab), #selector(splitRight), #selector(splitDown):
                return true
            case #selector(closePane):
                item.title = isSplit ? "Close Pane" : "Close Tab"
                return true
            default:
                return false
            }
        }
    }
}

extension NSUserInterfaceItemIdentifier {
    /// The roles of the menus `NSApp` is handed (`setSystemMenus(of:)`).
    static let servicesMenu = NSUserInterfaceItemIdentifier("carrier.menu.services")
    static let windowMenu = NSUserInterfaceItemIdentifier("carrier.menu.window")
    static let helpMenu = NSUserInterfaceItemIdentifier("carrier.menu.help")
}
