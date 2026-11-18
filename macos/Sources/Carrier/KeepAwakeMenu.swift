import AppKit
import CarrierCore

/// The Keep awake items of the status menu: one that does what its title says (stop, or keep awake for the default length) with the state
/// under it, a submenu of lengths with the one that runs checked, the switch "While agents work", and a way to the page. The titles are
/// worked out each time the menu opens (`validateMenuItem`), so the time left is never stale.
@MainActor final class KeepAwakeMenu: NSObject, NSMenuItemValidation {
    static let shared = KeepAwakeMenu()

    private let controller = KeepAwakeController.shared
    private let toggleItem = NSMenuItem(title: "Keep awake", action: #selector(toggle), keyEquivalent: "")
    private let lengthsItem = NSMenuItem(title: "Keep awake for", action: nil, keyEquivalent: "")
    private let agentsItem = NSMenuItem(title: "Keep awake while agents work", action: #selector(toggleAgents), keyEquivalent: "")
    private let settingsItem = NSMenuItem(title: "Keep awake settings…", action: #selector(openSettings), keyEquivalent: "")

    func install(in menu: NSMenu) {
        toggleItem.target = self
        agentsItem.target = self
        settingsItem.target = self
        showIcon("cup.and.saucer", on: toggleItem)
        let lengths = NSMenu(title: "Keep awake for")
        for minutes in AwakeLength.choices {
            let item = NSMenuItem(title: AwakeLength.title(minutes), action: #selector(chooseLength(_:)), keyEquivalent: "")
            item.target = self
            item.tag = minutes
            lengths.addItem(item)
        }
        lengths.addItem(.separator())
        lengths.addItem(settingsItem)
        lengthsItem.submenu = lengths
        showIcon("timer", on: lengthsItem)
        showIcon("sparkles", on: agentsItem)
        for item in [toggleItem, lengthsItem, agentsItem] { menu.addItem(item) }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let settings = controller.settings
        let decision = controller.decision
        let now = Date()
        if item === toggleItem {
            toggleItem.title = awakeToggleTitle(manualActive: decision.isManual, defaultMinutes: settings.defaultMinutes)
            toggleItem.subtitle = awakeStatus(decision, settings: settings, now: now)
            showIcon(decision.holds ? "cup.and.saucer.fill" : "cup.and.saucer", on: toggleItem)
        } else if item === agentsItem {
            agentsItem.state = settings.followsAgents ? .on : .off
        } else if item.action == #selector(chooseLength(_:)) {
            item.state = decision.isManual && controller.manualMinutes == item.tag ? .on : .off
        }
        return true
    }

    @objc private func toggle() { controller.toggle() }

    @objc private func chooseLength(_ item: NSMenuItem) { controller.start(minutes: item.tag) }

    @objc private func toggleAgents() { controller.setFollowsAgents(controller.settings.followsAgents == false) }

    @objc private func openSettings() { WindowController.shared.showSettings(.keepAwake) }
}
