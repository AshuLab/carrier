import AppKit
import CarrierCore

/// The groups of the status menu under the epics: Sessions, then Terminals and Dictation. Each is a section header and its rows, put before the
/// Sleep row (the anchor) and rebuilt each time the menu opens, so a closed menu costs nothing and what it says is never stale. They are fed
/// what the app already keeps alive (the session list `watchChatSessions` polls, the terminals' store, the dictation history), never fetched.
@MainActor final class StatusMenuGroups: NSObject {
    static let shared = StatusMenuGroups()

    /// Marks the Sleep row: the groups go before it.
    static let anchorTag = 0x5354
    /// Marks the items the groups own, so a rebuild removes exactly them.
    private static let tag = 0x5347

    private var sessions: [SessionRow] = []

    /// The latest list of the chat host's sessions, from the app's own poll.
    func react(toSessions rows: [SessionRow]) { sessions = rows }

    func rebuild(_ menu: NSMenu) {
        for item in menu.items where item.tag == Self.tag { menu.removeItem(item) }
        guard let anchor = menu.items.firstIndex(where: { $0.tag == Self.anchorTag }) else { return }
        let items = sessionItems() + terminalItems()
        for (offset, item) in items.enumerated() {
            item.tag = Self.tag
            menu.insertItem(item, at: anchor + offset)
        }
    }

    // MARK: sessions

    private func sessionItems() -> [NSMenuItem] {
        // what the window would call unread, worked out here from what the person has seen, without writing it back
        var rows = sessions
        var seen = SessionSeen.stored()
        _ = seen.apply(to: &rows, viewing: nil)
        let waiting = rows.filter { $0.state == .waiting && $0.archived == false }.count
        let (shown, more) = menuSessions(rows)
        var items = [NSMenuItem.sectionHeader(title: waiting > 0 ? "Sessions · \(waiting) need you" : "Sessions")]
        items += shown.map(sessionItem)
        if shown.isEmpty { items.append(disabled("No sessions")) }
        if more.isEmpty == false {
            let parent = NSMenuItem(title: "More sessions", action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: "More sessions")
            for row in more { submenu.addItem(sessionItem(row)) }
            parent.submenu = submenu
            items.append(parent)
        }
        items.append(plain("New session", symbol: "plus", action: #selector(newSession)))
        items.append(.separator())
        return items
    }

    private func sessionItem(_ row: SessionRow) -> NSMenuItem {
        let (symbol, color): (String, NSColor?) = switch row.status {
        case .needsYou: ("circle.fill", .systemOrange)
        case .working: ("circle.fill", .systemPurple)
        case .unread: ("circle.fill", .systemGreen)
        case .idle, .asleep: ("circle", nil)
        }
        let item = rowItem(row.title, secondary: row.workspace, symbol: symbol, color: color, action: #selector(openSession(_:)))
        item.representedObject = row.id
        return item
    }

    @objc private func openSession(_ item: NSMenuItem) {
        if let id = item.representedObject as? String { WindowController.shared.open(session: id) }
    }

    @objc private func newSession() { WindowController.shared.show(.newSession) }

    // MARK: terminals

    private func terminalItems() -> [NSMenuItem] {
        // the store is alive while the app is, window or not; it is only started here if nothing has touched it yet
        let terminals = CarrierTerminalStore.shared.standaloneTerminals()
        var items = [NSMenuItem.sectionHeader(title: terminals.isEmpty ? "Terminals" : "Terminals · \(terminals.count)")]
        items += terminals.prefix(5).map(terminalItem)
        if terminals.count > 5 {
            let parent = NSMenuItem(title: "More terminals", action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: "More terminals")
            for terminal in terminals.dropFirst(5).prefix(12) { submenu.addItem(terminalItem(terminal)) }
            parent.submenu = submenu
            items.append(parent)
        }
        if terminals.isEmpty { items.append(disabled("No terminals")) }
        items.append(plain("New terminal", symbol: "plus", action: #selector(newTerminal)))
        items.append(.separator())
        return items
    }

    private func terminalItem(_ terminal: StandaloneTerminalSummary) -> NSMenuItem {
        let item = rowItem(terminal.title, secondary: abbreviatedTerminalPath(terminal.workingDirectory), symbol: "terminal", action: #selector(openTerminal(_:)))
        item.representedObject = terminal.id
        return item
    }

    @objc private func openTerminal(_ item: NSMenuItem) {
        if let id = item.representedObject as? UUID { WindowController.shared.show(.terminal(id: id)) }
    }

    @objc private func newTerminal() { WindowController.shared.openNewTerminal() }

    // MARK: pieces

    /// A row: the title, and at its right (quieter) what goes with it.
    private func rowItem(_ title: String, secondary: String?, symbol: String, color: NSColor? = nil, action: Selector?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        let text = NSMutableAttributedString(string: Self.clipped(title, to: 40), attributes: [.font: NSFont.menuFont(ofSize: 0), .foregroundColor: NSColor.labelColor])
        if let secondary, secondary.isEmpty == false {
            text.append(NSAttributedString(string: "   " + secondary, attributes: [.font: NSFont.menuFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]))
        }
        item.attributedTitle = text
        showIcon(symbol, on: item, color: color)
        return item
    }

    private func plain(_ title: String, symbol: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        showIcon(symbol, on: item)
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// A title cut to `count` characters, ending in an ellipsis; the menu would cut it its own way and lose the words after it.
    private static func clipped(_ text: String, to count: Int) -> String {
        let one = text.replacingOccurrences(of: "\n", with: " ")
        return one.count > count ? String(one.prefix(count - 1)) + "…" : one
    }
}
