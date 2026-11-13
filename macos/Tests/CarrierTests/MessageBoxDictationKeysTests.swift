import AppKit
import CarrierCore
import SwiftUI
import XCTest
@testable import Carrier

/// The keys of the message box while it dictates, pressed on its text view as the system sends them.
@MainActor
final class MessageBoxDictationKeysTests: XCTestCase {
    private var sent = 0
    /// The window stays while the test runs: the box lives in it.
    private var window: NSWindow?

    private func textView(in host: NSView) -> PillTextView? {
        if let view = host as? PillTextView { return view }
        for sub in host.subviews { if let found = textView(in: sub) { return found } }
        return nil
    }

    private func until(_ condition: () -> Bool) async {
        for _ in 0..<2000 where condition() == false { try? await Task.sleep(for: .milliseconds(1)) }
    }

    /// A box with text to send, dictating in `state`.
    private func box(in state: DictationSession.State) async throws -> (DictationController, PillTextView) {
        _ = NSApplication.shared
        UserDefaults.standard.removeObject(forKey: AppPreferences.sendKeyKey)
        let registry = RecognizerRegistry()
        let recognizer = ScriptedRecognizer(atAudioEnd: [.final("")])
        registry.register(recognizer)
        let dictation = DictationController(registry: registry, capture: ScriptedCapture())
        let view = MessageBox(
            text: .constant("hola"), placeholder: "", canSend: true, canSendWithText: true, focus: .constant(false),
            dictationOwner: "box", dictation: dictation, send: { [unowned self] in sent += 1 }
        ) { Text("Claude Code") }
        let host = NSHostingView(rootView: view.frame(width: 600))
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 300)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        self.window = window
        host.layoutSubtreeIfNeeded()
        if state == .gettingReady { recognizer.holdPrepare() }
        if state != .idle {
            dictation.toggle(into: DictationField(owner: "box", text: { "hola" }, caret: { 4 }, put: { _, _, _ in }))
            await until { dictation.session.state == state }
        }
        XCTAssertEqual(dictation.session.state, state)
        return (dictation, try XCTUnwrap(textView(in: host)))
    }

    func testEnterWhileListeningStopsTheDictationAndDoesNotSendAndTheNextEnterSends() async throws {
        let (dictation, view) = try await box(in: .listening)
        view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(sent, 0)
        await until { dictation.session.state == .idle }
        XCTAssertEqual(dictation.session.state, .idle)
        view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(sent, 1)
    }

    func testEnterWhileTheModelGetsReadyCancelsTheDictationAndDoesNotSend() async throws {
        let (dictation, view) = try await box(in: .gettingReady)
        view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(sent, 0)
        XCTAssertEqual(dictation.session.state, .idle)
    }

    func testEscapeWhileListeningCancelsTheDictationAtOnce() async throws {
        let (dictation, view) = try await box(in: .listening)
        view.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        XCTAssertEqual(dictation.session.state, .idle)
        XCTAssertEqual(sent, 0)
    }
}
