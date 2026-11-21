import AppKit
import CarrierCore

/// The epics in the menu, rebuilt each time the menu opens (`menuNeedsUpdate`), so a closed menu costs nothing. It keeps the
/// latest state the monitor delivered. Main thread only.
final class EpicMenuSection: NSObject, NSMenuDelegate {
    static let shared = EpicMenuSection()

    /// Marks the items this section owns, so a rebuild removes exactly them.
    static let tag = 0x4550
    /// Marks the separator that ends the Carrier group: the epics go before it, under the controls.
    static let anchorTag = 0x4541

    private var state = ConnectionState.stopped

    func react(to state: ConnectionState) { self.state = state }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild(menu)
        // the groups under the epics and the Sleep row's state, from what the app keeps alive
        MainActor.assumeIsolated {
            StatusMenuGroups.shared.rebuild(menu)
            KeepAwakeMenu.shared.refresh()
        }
    }

    /// Replaces the section: it goes under the Carrier group's controls, before the separator that ends the group.
    private func rebuild(_ menu: NSMenu) {
        for item in menu.items where item.tag == Self.tag { menu.removeItem(item) }
        guard case .running(let snapshot) = state,
              let section = epicMenu(snapshot, showEpics: AppPreferences().showsEpics),
              let end = menu.items.firstIndex(where: { $0.tag == Self.anchorTag })
        else { return }

        var items = section.items.map(menuItem)
        if let more = section.more { items.append(NSMenuItem(title: more, action: nil, keyEquivalent: "")) }
        for (offset, item) in items.enumerated() {
            item.tag = Self.tag
            menu.insertItem(item, at: end + offset)
        }
    }

    private func menuItem(_ epic: EpicMenuItem) -> NSMenuItem {
        let item = NSMenuItem(title: epic.title, action: #selector(open(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = epic
        item.toolTip = epic.detail
        item.attributedTitle = {
            let text = NSMutableAttributedString(string: epic.title)
            text.append(NSAttributedString(
                string: "\n" + Self.shortened(epic.detail),
                attributes: [.font: NSFont.menuFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
            ))
            return text
        }()
        showIcon(epic.state.symbol, on: item, color: Self.color(epic.state))
        if let badge = epic.badge { item.badge = NSMenuItemBadge(string: badge) }
        return item
    }

    /// A menu is as wide as its longest line, so a long reason (a needs-human note can be a paragraph) would stretch it across the screen:
    /// one line of at most `detailLimit` characters here, the whole text in the tooltip.
    private static let detailLimit = 70
    private static func shortened(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return line.count > detailLimit ? line.prefix(detailLimit - 1).trimmingCharacters(in: .whitespaces) + "…" : line
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
