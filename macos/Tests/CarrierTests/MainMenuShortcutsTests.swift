import AppKit
import Foundation
import Testing
@testable import CarrierCore
@testable import Carrier

/// The main menu is built from the shortcut table: its items carry the table's keys, and another table gives other keys.
@MainActor @Suite struct MainMenuShortcutsTests {
    private static let items: [(menu: String, title: String, command: ShortcutCommand)] = [
        ("View", "Home", .home), ("View", "Sessions", .sessions), ("View", "Carrier", .carrier),
        ("File", "New Session", .newSession), ("Edit", "Find…", .search), ("View", "Archive", .archive),
        ("File", "Next Session", .nextSession), ("File", "Previous Session", .previousSession), ("File", "Archive Session", .archiveSession),
        ("Conversation", "Focus the Message Box", .focusBox), ("Conversation", "Jump to the Latest Message", .latestMessage),
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
}
