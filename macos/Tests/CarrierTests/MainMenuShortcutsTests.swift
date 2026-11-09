import AppKit
import Foundation
import Testing
@testable import CarrierCore
@testable import Carrier

private let fixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")

/// The main menu is built from the shortcut table: its items carry the table's keys, and another table gives other keys.
@MainActor @Suite struct MainMenuShortcutsTests {
    private static let items: [(menu: String, title: String, command: ShortcutCommand)] = [
        ("View", "Home", .home), ("View", "Sessions", .sessions), ("View", "Carrier", .carrier),
        ("File", "New Session", .newSession), ("Edit", "Find…", .search), ("View", "Archive", .archive),
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
}
