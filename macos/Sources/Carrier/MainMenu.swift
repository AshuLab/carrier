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
        NSApp.servicesMenu = main.item(withTitle: "Carrier")?.submenu?.item(withTitle: "Services")?.submenu
        NSApp.windowsMenu = main.item(withTitle: "Window")?.submenu
        NSApp.helpMenu = main.item(withTitle: "Help")?.submenu
    }

    /// Builds it again when a combination of the table is not the one the menu carries.
    func rebuildMainMenuIfShortcutsChanged() {
        if ShortcutTable().combos != shortcutsInMenu { installMainMenu() }
    }

    func makeMainMenu(shortcuts: ShortcutTable, controls: MenuControls = .shared) -> NSMenu {
        let main = NSMenu()

        // Carrier
        let app = submenu(of: main, title: "Carrier")
        item(app, "About Carrier", #selector(showAbout), target: self)
        app.addItem(.separator())
        item(app, "Settings…", #selector(openSettings), key: ",", target: self)
        app.addItem(.separator())
        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
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

        // Window
        let window = submenu(of: main, title: "Window")
        item(window, "Minimize", #selector(NSWindow.performMiniaturize(_:)), key: "m")
        item(window, "Zoom", #selector(NSWindow.performZoom(_:)))
        window.addItem(.separator())
        item(window, "Bring All to Front", #selector(NSApplication.arrangeInFront(_:)))

        // Help
        let help = submenu(of: main, title: "Help")
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

    private func submenu(of main: NSMenu, title: String) -> NSMenu {
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
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
