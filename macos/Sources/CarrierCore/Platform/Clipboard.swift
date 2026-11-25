import Foundation

/// The clipboard as the global dictation uses it; the app's is the pasteboard (`Carrier/Platform/SystemClipboard.swift`), the tests take a fake.
@MainActor public protocol Clipboard {
    /// Pastes `text` into the field that has the cursor of another app and leaves the clipboard as the person had it.
    func paste(_ text: String) async
    /// Puts `text` on the clipboard, for the person to paste.
    func copy(_ text: String)
}
