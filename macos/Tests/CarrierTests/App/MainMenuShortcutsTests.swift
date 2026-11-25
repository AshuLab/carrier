import AppKit
import Foundation
import Testing
@testable import CarrierCore
@testable import Carrier

private let fixtures = testPaths().fixtures

/// The main menu is built from the shortcut table: its items carry the table's keys, and another table gives other keys.
@MainActor @Suite struct MainMenuShortcutsTests {
    private static let items: [(menu: String, title: String, command: ShortcutCommand)] = [
        ("View", "Home", .home), ("View", "Sessions", .sessions), ("View", "Carrier", .carrier),
        ("File", "New Session", .newSession), ("Edit", "Find…", .search), ("View", "Archive", .archive),
        ("View", "Back", .back), ("View", "Forward", .forward),
        ("File", "Next Session", .nextSession), ("File", "Previous Session", .previousSession), ("File", "Archive Session", .archiveSession),
        ("Conversation", "Focus the Message Box", .focusBox), ("Conversation", "Stop the Agent", .stopAgent),
        ("Conversation", "Jump to the Latest Message", .latestMessage),
        ("Conversation", "Fold or Unfold the Tool Calls", .foldTools), ("Conversation", "Copy the Last Answer", .copyAnswer),
    ]

    private func table() -> ShortcutTable {
        let suite = "menu-shortcuts-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return ShortcutTable(defaults: defaults)
    }

    private func item(_ menu: NSMenu, _ menuTitle: String, _ title: String) throws -> NSMenuItem {
        try #require(menu.item(withTitle: menuTitle)?.submenu?.item(withTitle: title))
    }

    /// The updater is not started in a test, so nothing answers the item: it is there under About and stays dimmed, as in a fixture.
    @Test func theAppMenuHasCheckForUpdatesUnderAboutAndDimmedWithNoUpdater() throws {
        let menu = AppDelegate().makeMainMenu(shortcuts: table())
        let app = try #require(menu.item(withTitle: "Carrier")?.submenu)
        #expect(app.items.prefix(2).map(\.title) == ["About Carrier", "Check for Updates…"])
        let check = try item(menu, "Carrier", "Check for Updates…")
        #expect(check.target == nil && NSApp.target(forAction: check.action!, to: nil, from: check) == nil)
    }

    /// macOS is handed the Services, Window and Help menus by role: with every title changed (as a translation does) the three are still set.
    @Test func theSystemMenusAreSetWithoutLookingAnyUpByItsTitle() throws {
        let app = AppDelegate()
        let menu = app.makeMainMenu(shortcuts: table())
        let services = try item(menu, "Carrier", "Services").submenu
        let window = menu.item(withTitle: "Window")?.submenu
        let help = menu.item(withTitle: "Help")?.submenu
        #expect(services != nil && window != nil && help != nil)
        func retitle(_ menu: NSMenu) {
            menu.title = "Otro"
            for item in menu.items {
                item.title = "Otro \(item.title)"
                if let submenu = item.submenu { retitle(submenu) }
            }
        }
        retitle(menu)
        let shared = NSApplication.shared
        shared.servicesMenu = nil
        shared.windowsMenu = nil
        shared.helpMenu = nil
        app.setSystemMenus(of: menu)
        #expect(shared.servicesMenu === services && shared.windowsMenu === window && shared.helpMenu === help)
    }

    @Test func theItemsCarryTheTablesKeys() throws {
        let table = table()
        let menu = AppDelegate().makeMainMenu(shortcuts: table)
        for entry in Self.items {
            let made = try item(menu, entry.menu, entry.title)
            let combo = try #require(table.combo(for: entry.command))
            #expect(made.keyEquivalent == combo.key && made.keyEquivalentModifierMask == combo.modifiers.flags)
        }
        #expect(try item(menu, "View", "Home").keyEquivalent == "1")
    }

    @Test func aChangedOrClearedCombinationChangesTheItem() throws {
        let table = table()
        table.set(KeyCombo(key: "j", modifiers: [.command, .option]), for: .search)
        table.set(nil, for: .home)
        let menu = AppDelegate().makeMainMenu(shortcuts: table)
        let find = try item(menu, "Edit", "Find…")
        #expect(find.keyEquivalent == "j" && find.keyEquivalentModifierMask == [.command, .option])
        #expect(try item(menu, "View", "Home").keyEquivalent == "")
        #expect(try item(menu, "File", "New Session").keyEquivalent == "n")
    }

    // The Carrier controls: in the menu with no key until the table gives one, and run from the menu on the engine's controls.

    private func controls(running: Bool, epicsRunning: Bool = false, confirmStop: Bool = true) throws -> (MenuControls, Box) {
        let box = Box()
        let suite = "menu-controls-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let controls = MenuControls()
        controls.preferences = AppPreferences(defaults: defaults)
        controls.preferences.confirmStop = confirmStop
        controls.deliver = { box.sent.append($0) }
        controls.confirm = { _ in box.asked += 1; return box.answer }
        var snapshot = try decodeSnapshot(Data(contentsOf: fixtures.appendingPathComponent("snapshot.json")))
        snapshot.paused = false
        if epicsRunning == false { snapshot.epics = [] }
        controls.react(to: running ? .running(snapshot) : .stopped)
        return (controls, box)
    }

    @MainActor final class Box {
        var sent: [Command] = []
        var asked = 0
        var answer = true
    }

    private func run(_ made: NSMenuItem) { _ = NSApp.sendAction(made.action!, to: made.target, from: made) }

    @Test func theCarrierControlsAreInTheMenuWithoutAKeyAndRunFromIt() throws {
        let (controls, box) = try controls(running: true)
        let menu = AppDelegate().makeMainMenu(shortcuts: table(), controls: controls)
        let pause = try item(menu, "Engine", "Pause or resume intake")
        let check = try item(menu, "Engine", "Look for ready epics now")
        let startStop = try item(menu, "Engine", "Start or stop Carrier")
        #expect([pause, check, startStop].allSatisfy { $0.keyEquivalent == "" && controls.validateMenuItem($0) })
        run(pause)
        run(check)
        run(startStop)
        #expect(box.sent == [.pause, .checkNow, .stop])
    }

    @Test func aCombinationOfThePersonIsOnTheItemAndPauseBecomesResume() throws {
        let (controls, box) = try controls(running: true)
        let table = table()
        table.set(KeyCombo(key: "p", modifiers: [.command, .option]), for: .pauseOrResume)
        let pause = try item(AppDelegate().makeMainMenu(shortcuts: table, controls: controls), "Engine", "Pause or resume intake")
        #expect(pause.keyEquivalent == "p" && pause.keyEquivalentModifierMask == [.command, .option])
        var snapshot = try decodeSnapshot(Data(contentsOf: fixtures.appendingPathComponent("snapshot.json")))
        snapshot.paused = true
        controls.react(to: .running(snapshot))
        run(pause)
        #expect(box.sent == [.resume])
    }

    @Test func theControlsAreOffWhileCarrierIsStoppedExceptStartOrStop() throws {
        let (controls, box) = try controls(running: false)
        let menu = AppDelegate().makeMainMenu(shortcuts: table(), controls: controls)
        #expect(controls.validateMenuItem(try item(menu, "Engine", "Pause or resume intake")) == false)
        #expect(controls.validateMenuItem(try item(menu, "Engine", "Look for ready epics now")) == false)
        #expect(box.sent.isEmpty)
    }

    @Test func stoppingAsksOnlyWhenThePreferenceIsOnAndEpicsWouldBeInterrupted() throws {
        for (epics, preference, asks) in [(true, true, 1), (true, false, 0), (false, true, 0)] {
            let (controls, box) = try controls(running: true, epicsRunning: epics, confirmStop: preference)
            controls.startOrStop()
            #expect(box.asked == asks && box.sent == [.stop])
        }
        let (controls, box) = try controls(running: true, epicsRunning: true)
        box.answer = false
        controls.startOrStop()
        #expect(box.asked == 1 && box.sent.isEmpty)
    }

    @Test func terminalMenuControlsValidateAndDispatchPaneActions() throws {
        let suite = "menu-terminal-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = CarrierTerminalStore(
            fileStore: TerminalWorkspaceFileStore(fileURL: nil),
            preferences: AppPreferences(defaults: defaults),
            scheme: .dark
        )
        defer { store.teardownAll() }

        let owner = TerminalOwner.terminal(UUID())
        var activeOwner: TerminalOwner? = nil
        var allowFallback = true
        var createdTerminals = 0
        var drawerOpen = false
        var drawerAvailable = false
        var drawerToggles = 0
        let terminalControls = TerminalMenuControls(
            storeProvider: { store },
            preferredOwnerProvider: { activeOwner },
            allowsPreferredFallback: { allowFallback },
            newTerminalAction: { createdTerminals += 1 },
            drawerStateProvider: {
                guard drawerAvailable else { return nil }
                return (isOpen: drawerOpen, toggle: {
                    drawerOpen.toggle()
                    drawerToggles += 1
                })
            }
        )
        let menu = AppDelegate().makeMainMenu(shortcuts: table(), terminalControls: terminalControls)
        let newTerminalItem = try item(menu, "Terminal", "New Terminal")
        let toggleDrawerItem = try item(menu, "Terminal", "Show or Hide Terminal")
        let newTabItem = try item(menu, "Terminal", "New Tab")
        let splitRightItem = try item(menu, "Terminal", "Split Right")
        let zoomItem = try item(menu, "Terminal", "Zoom Pane")
        let equalizeItem = try item(menu, "Terminal", "Equalize Splits")
        let detachItem = try item(menu, "Terminal", "Move Pane to New Tab")
        let prevPaneItem = try item(menu, "Terminal", "Focus Previous Pane")
        let nextPaneItem = try item(menu, "Terminal", "Focus Next Pane")
        let prevTabItem = try item(menu, "Terminal", "Select Previous Tab")
        let nextTabItem = try item(menu, "Terminal", "Select Next Tab")
        let moveLeftItem = try item(menu, "Terminal", "Move Tab Left")
        let moveRightItem = try item(menu, "Terminal", "Move Tab Right")
        let closeItem = try item(menu, "Terminal", "Close Pane")

        // New Terminal stays available globally even before any terminal exists.
        #expect(terminalControls.validateMenuItem(newTerminalItem) == true)
        run(newTerminalItem)
        #expect(createdTerminals == 1)

        // Drawer toggle stays disabled until an owner with a drawer is visible.
        #expect(terminalControls.validateMenuItem(toggleDrawerItem) == false)
        #expect(toggleDrawerItem.title == "Show or Hide Terminal")
        drawerAvailable = true
        #expect(terminalControls.validateMenuItem(toggleDrawerItem) == true)
        #expect(toggleDrawerItem.title == "Show Terminal")
        run(toggleDrawerItem)
        #expect(drawerToggles == 1 && drawerOpen == true)
        #expect(terminalControls.validateMenuItem(toggleDrawerItem) == true)
        #expect(toggleDrawerItem.title == "Hide Terminal")

        // No active terminal selected -> Terminal menu pane/tab items stay disabled.
        #expect(terminalControls.validateMenuItem(newTabItem) == false)
        #expect(terminalControls.validateMenuItem(splitRightItem) == false)
        #expect(terminalControls.validateMenuItem(zoomItem) == false)

        let firstTab = store.openTab(for: owner, workingDirectory: "/tmp")
        activeOwner = owner
        #expect(terminalControls.validateMenuItem(newTabItem) == true)
        #expect(terminalControls.validateMenuItem(splitRightItem) == true)
        #expect(terminalControls.validateMenuItem(zoomItem) == false)
        #expect(terminalControls.validateMenuItem(equalizeItem) == false)
        #expect(terminalControls.validateMenuItem(detachItem) == false)
        #expect(terminalControls.validateMenuItem(prevPaneItem) == false)
        #expect(terminalControls.validateMenuItem(nextPaneItem) == false)
        #expect(terminalControls.validateMenuItem(prevTabItem) == false)
        #expect(terminalControls.validateMenuItem(nextTabItem) == false)
        #expect(terminalControls.validateMenuItem(moveLeftItem) == false)
        #expect(terminalControls.validateMenuItem(moveRightItem) == false)
        #expect(terminalControls.validateMenuItem(closeItem) == true)
        #expect(closeItem.title == "Close Tab")

        // Blocked fallback (e.g. text field / popover / secondary window) refuses preferred-owner actions.
        allowFallback = false
        #expect(terminalControls.validateMenuItem(newTabItem) == false)
        #expect(terminalControls.validateMenuItem(splitRightItem) == false)
        #expect(terminalControls.validateMenuItem(closeItem) == false)
        run(splitRightItem)
        #expect(store.activeTab(for: owner)?.paneCount == 1)

        allowFallback = true
        run(newTabItem)
        let tabs = store.tabs(for: owner)
        #expect(tabs.count == 2)
        let secondTab = tabs[1]
        #expect(store.activeTabId(for: owner) == secondTab.id)
        #expect(terminalControls.validateMenuItem(prevTabItem) == true)
        #expect(terminalControls.validateMenuItem(nextTabItem) == true)
        #expect(terminalControls.validateMenuItem(moveLeftItem) == true)
        #expect(terminalControls.validateMenuItem(moveRightItem) == false)

        run(moveLeftItem)
        #expect(store.tabs(for: owner).map(\.id) == [secondTab.id, firstTab.id])
        #expect(terminalControls.validateMenuItem(moveLeftItem) == false)
        #expect(terminalControls.validateMenuItem(moveRightItem) == true)

        run(nextTabItem)
        #expect(store.activeTabId(for: owner) == firstTab.id)
        run(prevTabItem)
        #expect(store.activeTabId(for: owner) == secondTab.id)

        run(splitRightItem)
        #expect(store.activeTab(for: owner)?.paneCount == 2)
        #expect(terminalControls.validateMenuItem(zoomItem) == true)
        #expect(terminalControls.validateMenuItem(equalizeItem) == true)
        #expect(terminalControls.validateMenuItem(detachItem) == true)
        #expect(terminalControls.validateMenuItem(prevPaneItem) == true)
        #expect(terminalControls.validateMenuItem(nextPaneItem) == true)
        #expect(terminalControls.validateMenuItem(closeItem) == true)
        #expect(closeItem.title == "Close Pane")

        let secondPaneId = store.activeTab(for: owner)?.activePaneId
        run(prevPaneItem)
        #expect(store.activeTab(for: owner)?.activePaneId != secondPaneId)
        run(nextPaneItem)
        #expect(store.activeTab(for: owner)?.activePaneId == secondPaneId)

        run(zoomItem)
        #expect(store.activeTab(for: owner)?.zoomedPaneId != nil)
        #expect(terminalControls.validateMenuItem(zoomItem) == true)
        #expect(zoomItem.title == "Restore Split View")
    }

    @Test func terminalMenuFallbackStopsForTextRespondersAndOtherWindows() {
        let mainWindow = NSWindow(
            contentRect: NSRect(x: -4000, y: -4000, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let otherWindow = NSWindow(
            contentRect: NSRect(x: -4000, y: -4000, width: 300, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let plainResponder = NSView()
        let textView = NSTextView()
        mainWindow.contentView = plainResponder

        #expect(TerminalMenuControls.allowsPreferredFallback(keyWindow: mainWindow, mainWindow: mainWindow) == true)
        #expect(TerminalMenuControls.allowsPreferredFallback(keyWindow: nil, mainWindow: mainWindow) == false)
        #expect(TerminalMenuControls.allowsPreferredFallback(keyWindow: mainWindow, mainWindow: nil) == false)
        #expect(TerminalMenuControls.allowsPreferredFallback(keyWindow: otherWindow, mainWindow: mainWindow) == false)

        mainWindow.contentView = textView
        mainWindow.makeFirstResponder(textView)
        #expect(TerminalMenuControls.allowsPreferredFallback(keyWindow: mainWindow, mainWindow: mainWindow) == false)
    }

    @Test func terminalMenuValidationNeverEagerlyInitializesSharedStore() throws {
        let wasInitializedBefore = CarrierTerminalStore.sharedIfInitialized != nil
        let controls = TerminalMenuControls()
        let menu = AppDelegate().makeMainMenu(shortcuts: table(), terminalControls: controls)
        let newTabItem = try item(menu, "Terminal", "New Tab")
        let toggleDrawerItem = try item(menu, "Terminal", "Show or Hide Terminal")
        let splitRightItem = try item(menu, "Terminal", "Split Right")

        _ = controls.validateMenuItem(newTabItem)
        _ = controls.validateMenuItem(toggleDrawerItem)
        _ = controls.validateMenuItem(splitRightItem)

        #expect((CarrierTerminalStore.sharedIfInitialized != nil) == wasInitializedBefore)
    }
}
