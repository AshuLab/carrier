import AppKit
import CarrierCore
import SwiftUI

extension View {
    /// The session's context menu (`sessionMenu`). It is an AppKit menu, built once when the right button goes down: SwiftUI's rebuilds an open
    /// menu whenever the list behind it changes (the submenu flickered), drops the icons and gets "Ask Siri" added on top.
    /// `filterWorkspace` is only given by the Sessions home.
    /// `inWindow` is for the lists of the main window (the sidebar and the home): they can mark unread and start a session on the branch; the Archive cannot.
    func sessionContextMenu(_ row: SessionRow, filterWorkspace: ((String) -> Void)? = nil, inWindow: Bool = false) -> some View {
        modifier(SessionContextMenu(row: row, filterWorkspace: filterWorkspace, inWindow: inWindow))
    }
}

/// What the host refuses (an archive of a session that is working, a title it cannot write) is told in an alert.
private struct SessionContextMenu: ViewModifier {
    let row: SessionRow
    let filterWorkspace: ((String) -> Void)?
    let inWindow: Bool
    @Environment(SessionActions.self) private var actions
    @AppStorage(Preference.sidebarPinned) private var pinnedStored

    func body(content: Content) -> some View {
        content.overlay(RightClickMenu(menu: menu))
    }

    private func menu() -> NSMenu {
        let menu = NSMenu()
        menu.allowsContextMenuPlugIns = false
        // an item the menu cannot use stays off: with auto-enabling the target it has would turn it on
        menu.autoenablesItems = false
        let context = SessionMenuContext(
            marksUnread: inWindow, viewing: WindowController.shared.viewingSession == row.id, startsSessions: inWindow,
            projectKnown: ProjectsModel.shared.rows.contains { $0.path == row.base })
        let sections = sessionMenu(row, pinned: pinnedIds(pinnedStored).contains(row.id), canFilter: filterWorkspace != nil, canRegenerateTitle: actions.canRegenerateTitle, context: context)
        for (index, section) in sections.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            for item in section { menu.addItem(menuItem(item)) }
        }
        return menu
    }

    private func menuItem(_ item: SessionMenuItem) -> NSMenuItem {
        let entry = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
        // the helper that asks macOS 27 to show the symbol, by key: `preferredImageVisibility` is in the macOS 27 SDK only, and CI builds with Xcode 26
        showIcon(item.icon, on: entry)
        if item.destructive { entry.attributedTitle = NSAttributedString(string: item.title, attributes: [.foregroundColor: NSColor.systemRed]) }
        if let action = item.action {
            let handler = MenuHandler { run(action) }
            entry.target = handler
            entry.action = #selector(MenuHandler.fire)
            entry.representedObject = handler  // the item does not keep its target alive
            if let reason = item.disabledReason {
                entry.isEnabled = false
                entry.toolTip = reason
            }
        } else {
            entry.submenu = NSMenu()
            entry.submenu?.allowsContextMenuPlugIns = false
            item.children.forEach { entry.submenu?.addItem(menuItem($0)) }
        }
        return entry
    }

    private func run(_ action: SessionMenuAction) {
        switch action {
        case .stop: refuse { await actions.stop(row.id) }
        case .pin: pinnedStored = storedPins(pinnedIds(pinnedStored).union([row.id]))
        case .unpin: pinnedStored = storedPins(pinnedIds(pinnedStored).subtracting([row.id]))
        case .rename:
            if let title = askTitle(row.title) { refuse { await actions.rename(row.id, title) } }
        case .regenerateTitle: refuse { await TitleRegeneration.shared.regenerate(row.id, showing: row.title) { await actions.regeneratedTitle(row.id) } }
        case .openInTerminal(let path): openInTerminal(path)
        case .filterWorkspace(let name): filterWorkspace?(name)
        case .archive: refuse { await actions.archive(row.id) }
        case .restore: refuse { await actions.restore(row.id) }
        case .delete: deleteArchived(row, actions)
        case .markUnread: WindowController.shared.setUnread(row.id, true)
        case .markRead: WindowController.shared.setUnread(row.id, false)
        case .newSession(let base, let branch): WindowController.shared.startNewSession(in: base, branch: branch)
        case .openProject(let base): WindowController.shared.showSettings(place: SettingsPlace(.projects, path: [base]))
        case .copy(let text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    private func refuse(_ call: @escaping () async -> String?) {
        Task { if let refusal = await call() { tell(refusal) } }
    }
}

private final class MenuHandler: NSObject {
    let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
    @objc func fire() { run() }
}

/// Covers the row for the right button only (and control-click): any other click goes through to what is under it.
private struct RightClickMenu: NSViewRepresentable {
    let menu: () -> NSMenu

    func makeNSView(context: Context) -> Catcher { Catcher() }
    func updateNSView(_ view: Catcher, context: Context) { view.makeMenu = menu }

    final class Catcher: NSView {
        var makeMenu: () -> NSMenu = { NSMenu() }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else { return nil }
            let secondary = event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
            return secondary ? super.hitTest(point) : nil
        }

        override func menu(for event: NSEvent) -> NSMenu? { makeMenu() }
    }
}

/// Deletes an archived session after asking, unless the person switched the question off.
@MainActor func deleteArchived(_ row: SessionRow, _ actions: SessionActions) {
    Task {
        switch await actions.confirmDelete(row) {
        case .refused(let refusal): tell(refusal)
        case .ask(let question):
            guard ask(question) else { return }
            fallthrough
        case .proceed:
            if let refusal = await actions.delete(row.id) { tell(refusal) }
        }
    }
}

/// Opens Terminal in the folder.
@MainActor private func openInTerminal(_ path: String) {
    guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return tell("Terminal is not installed.") }
    NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
}

/// Asks for a new title in an alert with a field; nil when cancelled or left empty.
@MainActor private func askTitle(_ current: String) -> String? {
    let alert = NSAlert()
    alert.messageText = "Rename session"
    let field = NSTextField(string: current)
    field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
    alert.accessoryView = field
    alert.addButton(withTitle: "Rename")
    alert.addButton(withTitle: "Cancel")
    alert.window.initialFirstResponder = field
    NSApp.activate()
    guard alert.runModal() == .alertFirstButtonReturn else { return nil }
    let title = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    return title.isEmpty ? nil : title
}

/// Asks the question in an alert whose first button, the default, does nothing; true when the person chose the destructive one.
@MainActor func ask(_ question: Question) -> Bool {
    let alert = NSAlert()
    alert.messageText = question.title
    alert.informativeText = question.message
    alert.addButton(withTitle: "Cancel")
    alert.addButton(withTitle: question.confirm).hasDestructiveAction = true
    NSApp.activate()
    return alert.runModal() == .alertSecondButtonReturn
}

/// Says what the host refused, in its words.
@MainActor func tell(_ refusal: String) {
    let alert = NSAlert()
    alert.messageText = refusal
    NSApp.activate()
    alert.runModal()
}
