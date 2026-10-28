import AppKit
import CarrierCore
import SwiftUI

/// The items of a session row's context menu (`sessionMenu`): Archive or Restore, Reveal in Finder and Copy session id. What the host
/// refuses (an archive of a session that is working) is told in an alert.
struct SessionMenuItems: View {
    let row: SessionRow
    @Environment(SessionActions.self) private var actions

    var body: some View {
        ForEach(sessionMenu(row), id: \.title) { item in
            Button(item.title) { run(item.action) }
        }
    }

    private func run(_ action: SessionMenuAction) {
        switch action {
        case .archive: Task { if let refusal = await actions.archive(row.id) { tell(refusal) } }
        case .restore: Task { if let refusal = await actions.restore(row.id) { tell(refusal) } }
        case .reveal(let path): NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        case .copy(let text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }
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
