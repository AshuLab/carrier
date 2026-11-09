import AppKit
import CarrierCore
import SwiftUI

/// The items of a session row's context menu (`sessionMenu`), sections apart, with Copy as a submenu. What the host refuses (an archive
/// of a session that is working, a title it cannot write) is told in an alert. `filterWorkspace` is only given by the Sessions home.
struct SessionMenuItems: View {
    let row: SessionRow
    var filterWorkspace: ((String) -> Void)?
    @Environment(SessionActions.self) private var actions
    @AppStorage(SidebarStore.pinnedKey) private var pinnedStored = ""

    var body: some View {
        let sections = sessionMenu(row, pinned: pinnedIds(pinnedStored).contains(row.id), canFilter: filterWorkspace != nil)
        ForEach(sections.indices, id: \.self) { index in
            if index > 0 { Divider() }
            ForEach(sections[index], id: \.title) { entry($0) }
        }
    }

    @ViewBuilder private func entry(_ item: SessionMenuItem) -> some View {
        if item.children.isEmpty {
            leaf(item)
        } else {
            Menu {
                ForEach(item.children, id: \.title) { leaf($0) }
            } label: { Label(item.title, systemImage: item.icon) }
        }
    }

    private func leaf(_ item: SessionMenuItem) -> some View {
        Button(role: item.destructive ? .destructive : nil) {
            if let action = item.action { run(action) }
        } label: { Label(item.title, systemImage: item.icon) }
    }

    private func run(_ action: SessionMenuAction) {
        switch action {
        case .stop: refuse { await actions.stop(row.id) }
        case .pin: pinnedStored = storedPins(pinnedIds(pinnedStored).union([row.id]))
        case .unpin: pinnedStored = storedPins(pinnedIds(pinnedStored).subtracting([row.id]))
        case .rename:
            if let title = askTitle(row.title) { refuse { await actions.rename(row.id, title) } }
        case .regenerateTitle: refuse { await actions.regenerateTitle(row.id) }
        case .openInTerminal(let path): openInTerminal(path)
        case .filterWorkspace(let name): filterWorkspace?(name)
        case .archive: refuse { await actions.archive(row.id) }
        case .restore: refuse { await actions.restore(row.id) }
        case .delete: deleteArchived(row, actions)
        case .copy(let text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    private func refuse(_ call: @escaping () async -> String?) {
        Task { if let refusal = await call() { tell(refusal) } }
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
