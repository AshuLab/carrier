import AppKit
import Carbon.HIToolbox
import CarrierCore

/// Everything on a pasteboard, kept to be put back: every item with the bytes of each of its types. Saving only the text would lose an image, the
/// files of a Finder copy and the markers that tell a clipboard manager to skip an item (docs/research/global-dictation-input.md).
struct PasteboardSnapshot {
    private let items: [[(type: NSPasteboard.PasteboardType, data: Data)]]

    init(_ board: NSPasteboard) {
        items = (board.pasteboardItems ?? []).map { item in item.types.compactMap { type in item.data(forType: type).map { (type, $0) } } }
    }

    /// New items, never the ones that were read: an item belongs to the pasteboard it came from and cannot be written again.
    func restore(to board: NSPasteboard) {
        board.clearContents()
        board.writeObjects(
            items.map { saved in
                let item = NSPasteboardItem()
                for part in saved { item.setData(part.data, forType: part.type) }
                return item
            })
    }
}

extension NSPasteboard.PasteboardType {
    /// The convention of nspasteboard.org: a clipboard manager does not keep an item that has it.
    static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
}

/// Pastes a text into the field that has the cursor of another app: the text goes on the clipboard, a ⌘V is sent, and the clipboard is put back as
/// the person had it, unless they copied something in the meantime. Sending the key needs the Accessibility permission, which the caller checks.
@MainActor struct SystemClipboard: Clipboard {
    var board = NSPasteboard.general
    /// How long the other app has to read the clipboard before it is put back.
    /// ponytail: a guess to calibrate on the sweep of the spike's list (restoring too soon pastes the old clipboard); a wait for the change count if apps differ a lot.
    var restoreDelay = Duration.milliseconds(200)
    /// Whether a modifier of the shortcut is still down, which would turn the paste into ⌥⇧⌘V (paste and match style in many apps).
    var modifiersDown = {
        CGEventSource.flagsState(.combinedSessionState).isDisjoint(with: [.maskAlternate, .maskShift, .maskControl, .maskCommand]) == false
    }
    var sendPasteKey: () -> Void = SystemClipboard.sendCommandV
    var sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) }

    func paste(_ text: String) async {
        for _ in 0..<50 where modifiersDown() { try? await sleep(.milliseconds(20)) }
        let saved = PasteboardSnapshot(board)
        // the text stays on this Mac (no Universal Clipboard), and a clipboard manager skips it
        board.prepareForNewContents(with: [.currentHostOnly])
        board.setString(text, forType: .string)
        board.setData(Data(), forType: .transient)
        let written = board.changeCount
        sendPasteKey()
        try? await sleep(restoreDelay)
        // another count is the person copying during the wait: their copy stays; and a clipboard that macOS did not let us read cannot be put back
        guard board.changeCount == written, board.accessBehavior != .alwaysDeny else { return }
        saved.restore(to: board)
    }

    func copy(_ text: String) {
        board.clearContents()
        board.setString(text, forType: .string)
    }

    /// A ⌘V from a source of its own, which does not take the keys that are physically down.
    static func sendCommandV() {
        let source = CGEventSource(stateID: .privateState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}
