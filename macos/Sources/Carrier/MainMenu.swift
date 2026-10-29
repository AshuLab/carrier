import AppKit
import CarrierCore

// The menu bar of the app: what a Mac app has (its own menu, File, Edit, View, Window, Help), so the keys every text field expects work
// (the Edit menu is what makes ⌘C and ⌘V reach a field) and the window is driven from the top of the screen as well as from its sidebar.
// The menu bar item at the right of the screen (the status item) is another thing and stays as it was.
extension AppDelegate {
    func installMainMenu() {
        let main = NSMenu()
        NSApp.mainMenu = main

        // Carrier
        let app = submenu(of: main, title: "Carrier")
        item(app, "About Carrier", #selector(showAbout), target: self)
        app.addItem(.separator())
        item(app, "Settings…", #selector(openSettings), key: ",", target: self)
        app.addItem(.separator())
        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        services.submenu = NSMenu(title: "Services")
        app.addItem(services)
        NSApp.servicesMenu = services.submenu
        app.addItem(.separator())
        item(app, "Hide Carrier", #selector(NSApplication.hide(_:)), key: "h")
        item(app, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), key: "h", modifiers: [.command, .option])
        item(app, "Show All", #selector(NSApplication.unhideAllApplications(_:)))
        app.addItem(.separator())
        item(app, "Quit Carrier", #selector(NSApplication.terminate(_:)), key: "q")

        // File
        let file = submenu(of: main, title: "File")
        item(file, "New Session", #selector(newSession), key: "n", target: self)
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
        item(edit, "Find…", #selector(findInSection), key: "f", target: self)

        // View
        let view = submenu(of: main, title: "View")
        item(view, "Home", #selector(showHome), key: "1", target: self)
        item(view, "Sessions", #selector(showSessions), key: "2", target: self)
        item(view, "Carrier", #selector(showCarrier), key: "3", target: self)
        item(view, "Archive", #selector(showArchive), target: self)
        view.addItem(.separator())
        item(view, "Show or Hide Sidebar", #selector(toggleSidebar), key: "s", modifiers: [.command, .control], target: self)
        item(view, "Show or Hide Inspector", #selector(toggleInspector), key: "i", modifiers: [.command, .option], target: self)
        view.addItem(.separator())
        item(view, "Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), key: "f", modifiers: [.command, .control])

        // Window
        let window = submenu(of: main, title: "Window")
        item(window, "Minimize", #selector(NSWindow.performMiniaturize(_:)), key: "m")
        item(window, "Zoom", #selector(NSWindow.performZoom(_:)))
        window.addItem(.separator())
        item(window, "Bring All to Front", #selector(NSApplication.arrangeInFront(_:)))
        NSApp.windowsMenu = window

        // Help
        let help = submenu(of: main, title: "Help")
        item(help, "Carrier on GitHub", #selector(openHelp), target: self)
        NSApp.helpMenu = help
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

    @objc func showAbout() { WindowController.shared.showAbout() }
    @objc func openSettings() { SettingsWindowController.shared.open() }
    @objc func openWindow() { WindowController.shared.open() }
    @objc func newSession() { WindowController.shared.show(.newSession) }
    @objc func showHome() { WindowController.shared.show(.home) }
    @objc func showSessions() { WindowController.shared.show(.sessions) }
    @objc func showCarrier() { WindowController.shared.show(.carrier) }
    @objc func showArchive() { WindowController.shared.show(.archive) }
    @objc func findInSection() { WindowController.shared.search() }
    @objc func toggleSidebar() { WindowController.shared.toggleSidebar() }
    @objc func toggleInspector() { WindowController.shared.toggleInspector() }
    @objc func openHelp() { NSWorkspace.shared.open(URL(string: "https://github.com/AshuLab/carrier")!) }
}
