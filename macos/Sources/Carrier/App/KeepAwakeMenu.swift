import AppKit
import CarrierCore

/// The Sleep row of the status menu, whose submenu has the item that does what its title says (stop, or keep awake for the default length)
/// with the state under it, a submenu of lengths with the one that runs checked, and a way to the page. The row says the state at its right
/// (`refresh`) and the titles inside are worked out each time the menu opens (`validateMenuItem`), so the time left is never stale.
@MainActor final class KeepAwakeMenu: NSObject, NSMenuItemValidation {
    static let shared = KeepAwakeMenu()

    private let controller = KeepAwakeController.shared
    private let toggleItem = NSMenuItem(title: "Keep awake", action: #selector(toggle), keyEquivalent: "")
    private let lengthsItem = NSMenuItem(title: "Keep awake for", action: nil, keyEquivalent: "")
    private let sleepItem = NSMenuItem(title: "Sleep", action: nil, keyEquivalent: "")
    private let settingsItem = NSMenuItem(title: "Keep awake settings…", action: #selector(openSettings), keyEquivalent: "")

    func install(in menu: NSMenu) {
        toggleItem.target = self
        settingsItem.target = self
        showIcon("cup.and.saucer", on: toggleItem)
        let lengths = NSMenu(title: "Keep awake for")
        for minutes in AwakeLength.choices {
            let item = NSMenuItem(title: AwakeLength.title(minutes), action: #selector(chooseLength(_:)), keyEquivalent: "")
            item.target = self
            item.tag = minutes
            lengths.addItem(item)
        }
        lengthsItem.submenu = lengths
        showIcon("timer", on: lengthsItem)
        showIcon("gearshape", on: settingsItem)
        let sleep = NSMenu(title: "Sleep")
        for item in [toggleItem, lengthsItem, .separator(), settingsItem] { sleep.addItem(item) }
        sleepItem.submenu = sleep
        sleepItem.tag = StatusMenuGroups.anchorTag
        showIcon("cup.and.saucer", on: sleepItem)
        menu.addItem(sleepItem)
        refresh()
    }

    /// The row's title: "Sleep", and at its right how long the Mac is kept awake, when it is.
    func refresh() {
        let decision = controller.decision
        let title = NSMutableAttributedString(string: "Sleep", attributes: [.font: NSFont.menuFont(ofSize: 0), .foregroundColor: NSColor.labelColor])
        if decision.holds {
            title.append(NSAttributedString(
                string: "   " + awakeStatus(decision, settings: controller.settings, now: Date()),
                attributes: [.font: NSFont.menuFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]))
        }
        sleepItem.attributedTitle = title
        showIcon(decision.holds ? "cup.and.saucer.fill" : "cup.and.saucer", on: sleepItem)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let settings = controller.settings
        let decision = controller.decision
        let now = Date()
        if item === toggleItem {
            toggleItem.title = awakeToggleTitle(manualActive: decision.isManual, defaultMinutes: settings.defaultMinutes)
            toggleItem.subtitle = awakeStatus(decision, settings: settings, now: now)
            showIcon(decision.holds ? "cup.and.saucer.fill" : "cup.and.saucer", on: toggleItem)
            // the menu shows the keys that do the same from any app, so the shortcut is learned where it is used
            // only keys the system accepted: keys it refused are not shown as if they worked
            let shortcut = controller.registeredShortcut
            let key = awakeMenuKey(shortcut)
            toggleItem.keyEquivalent = key ?? ""
            toggleItem.keyEquivalentModifierMask = key == nil ? [] : (shortcut?.modifiers.flags ?? [])
        } else if item.action == #selector(chooseLength(_:)) {
            item.state = decision.isManual && controller.manualMinutes == item.tag ? .on : .off
        }
        return true
    }

    @objc private func toggle() { controller.toggle() }

    @objc private func chooseLength(_ item: NSMenuItem) { controller.start(minutes: item.tag) }

    @objc private func openSettings() { WindowController.shared.showSettings(.keepAwake) }
}
