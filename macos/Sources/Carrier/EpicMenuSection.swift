import AppKit
import CarrierCore

/// The epics in the menu, rebuilt each time the menu opens (`menuNeedsUpdate`), so a closed menu costs nothing. It keeps the
/// latest state the monitor delivered. Main thread only.
final class EpicMenuSection: NSObject, NSMenuDelegate {
    static let shared = EpicMenuSection()

    /// Marks the items this section owns, so a rebuild removes exactly them.
    static let tag = 0x4550

    private var state = ConnectionState.stopped

    func react(to state: ConnectionState) { self.state = state }

    func menuNeedsUpdate(_ menu: NSMenu) { rebuild(menu) }

    /// Replaces the section: it goes after the first separator, under the status line and the controls.
    private func rebuild(_ menu: NSMenu) {
        for item in menu.items where item.tag == Self.tag { menu.removeItem(item) }
        guard case .running(let snapshot) = state,
              let section = epicMenu(snapshot, showEpics: UserDefaults.standard.object(forKey: showEpicsKey) as? Bool ?? true),
              let separator = menu.items.firstIndex(where: \.isSeparatorItem)
        else { return }

        var items = section.items.map(menuItem)
        if let more = section.more { items.append(NSMenuItem(title: more, action: nil, keyEquivalent: "")) }
        items.append(.separator())
        for (offset, item) in items.enumerated() {
            item.tag = Self.tag
            menu.insertItem(item, at: separator + 1 + offset)
        }
    }

    private func menuItem(_ epic: EpicMenuItem) -> NSMenuItem {
        let item = NSMenuItem(title: epic.title, action: #selector(open(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = epic
        item.attributedTitle = {
            let text = NSMutableAttributedString(string: epic.title)
            text.append(NSAttributedString(
                string: "\n" + epic.detail,
                attributes: [.font: NSFont.menuFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
            ))
            return text
        }()
        showIcon(epic.state.symbol, on: item, color: Self.color(epic.state))
        if let badge = epic.badge { item.badge = NSMenuItemBadge(string: badge) }
        return item
    }

    private static func color(_ state: EpicMenuState) -> NSColor {
        switch state {
        case .needsYou: .systemOrange
        case .running: .systemGreen
        case .waiting: .systemGray
        case .ready: .systemBlue
        case .done: .systemGreen
        case .cancelled: .systemGray
        }
    }

    @objc private func open(_ item: NSMenuItem) {
        WindowController.shared.open(selecting: item.representedObject as? EpicMenuItem)
    }
}
