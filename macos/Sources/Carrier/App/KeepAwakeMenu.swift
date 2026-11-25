import AppKit
import CarrierCore

/// The Sleep row of the status menu, whose submenu has the item that does what its title says (stop, or keep awake for the default length)
/// with the state under it, a submenu of lengths with the one that runs checked, and a way to the page. The row says the state at its right
/// (`refresh`) and the titles inside are worked out each time the menu opens (`validateMenuItem`), so the time left is never stale.
@MainActor final class KeepAwakeMenu: NSObject, NSMenuItemValidation {
    static let shared = KeepAwakeMenu()

    private let controller = KeepAwakeController.shared
    /// The language of the rows' words: the app's, and a test's own.
    private let bundle: Bundle?
    private let locale: Locale
    private let toggleItem: NSMenuItem
    private let lengthsItem: NSMenuItem
    private let sleepItem: NSMenuItem
    private let settingsItem: NSMenuItem

    convenience override init() { self.init(bundle: nil, locale: .current) }

    init(bundle: Bundle?, locale: Locale) {
        (self.bundle, self.locale) = (bundle, locale)
        toggleItem = NSMenuItem(title: Copy.awakeMenuKeepAwake(bundle: bundle, locale: locale), action: #selector(toggle), keyEquivalent: "")
        lengthsItem = NSMenuItem(title: Copy.awakeMenuLengths(bundle: bundle, locale: locale), action: nil, keyEquivalent: "")
        sleepItem = NSMenuItem(title: Copy.awakeMenuSleep(bundle: bundle, locale: locale), action: nil, keyEquivalent: "")
        settingsItem = NSMenuItem(title: Copy.awakeMenuSettings(bundle: bundle, locale: locale), action: #selector(openSettings), keyEquivalent: "")
        super.init()
    }

    func install(in menu: NSMenu) {
        toggleItem.target = self
        settingsItem.target = self
        showIcon("cup.and.saucer", on: toggleItem)
        let lengths = NSMenu(title: Copy.awakeMenuLengths(bundle: bundle, locale: locale))
        for minutes in AwakeLength.choices {
            let item = NSMenuItem(title: AwakeLength.title(minutes, bundle: bundle, locale: locale), action: #selector(chooseLength(_:)), keyEquivalent: "")
            item.target = self
            item.tag = minutes
            lengths.addItem(item)
        }
        lengthsItem.submenu = lengths
        showIcon("timer", on: lengthsItem)
        showIcon("gearshape", on: settingsItem)
        let sleep = NSMenu(title: Copy.awakeMenuSleep(bundle: bundle, locale: locale))
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
        let title = NSMutableAttributedString(string: Copy.awakeMenuSleep(bundle: bundle, locale: locale), attributes: [.font: NSFont.menuFont(ofSize: 0), .foregroundColor: NSColor.labelColor])
        if decision.holds {
            title.append(NSAttributedString(
                string: "   " + awakeStatus(decision, settings: controller.settings, now: Date(), bundle: bundle, locale: locale),
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
            toggleItem.title = awakeToggleTitle(manualActive: decision.isManual, defaultMinutes: settings.defaultMinutes, bundle: bundle, locale: locale)
            toggleItem.subtitle = awakeStatus(decision, settings: settings, now: now, bundle: bundle, locale: locale)
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
